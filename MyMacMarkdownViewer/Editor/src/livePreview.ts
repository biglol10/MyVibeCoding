import { StateEffect, StateField, EditorSelection, type EditorState } from '@codemirror/state';
import { EditorView, Decoration, WidgetType, type DecorationSet } from '@codemirror/view';
import { TreeFragment } from '@lezer/common';
import { blocksFor, markdownParser, type Block } from './markdown';
import { renderBlock, renderDiagram } from './render';
import { defaultSettings, post, session, type Settings } from './protocol';
import { decorateTextBlock } from './textPreview';

export const setSourceMode = StateEffect.define<boolean>();
export const setComposition = StateEffect.define<boolean>();
export const updateSettings = StateEffect.define<Settings>();
export const previewOptions = StateField.define({
  create: () => ({ sourceMode: false, composing: false, settings: { ...defaultSettings }, generation: 0 }),
  update(value, transaction) {
    for (const effect of transaction.effects) {
      if (effect.is(setSourceMode)) value = { ...value, sourceMode: effect.value };
      if (effect.is(setComposition)) value = { ...value, composing: effect.value };
      if (effect.is(updateSettings)) value = { ...value, settings: effect.value, generation: value.generation + 1 };
    }
    return value;
  },
});

class PreviewWidget extends WidgetType {
  constructor(readonly block: Block, readonly settings: Settings, readonly generation: number, readonly sessionID: string) { super(); }
  eq(other: PreviewWidget) { return this.block.source === other.block.source && this.generation === other.generation && this.sessionID === other.sessionID; }
  toDOM(view: EditorView) {
    const isMermaid = /^\s*(`{3,}|~{3,})mermaid(?:\s|$)/i.test(this.block.source);
    const dom = isMermaid ? document.createElement('div') : renderBlock(this.block.source, this.settings);
    dom.classList.add('preview-widget'); dom.dataset.kind = this.block.kind;
    dom.setAttribute('aria-label', '클릭하여 이 블록 편집');
    if (isMermaid) queueMicrotask(() => renderDiagram(dom, this.block.source, this.settings.theme,
      () => session.sessionID === this.sessionID && view.state.field(previewOptions).generation === this.generation,
      () => view.requestMeasure()));
    dom.addEventListener('mousedown', event => {
      const target = event.target as HTMLElement;
      if (target.closest('[data-remote-images]')) { event.preventDefault(); post('remoteImages'); return; }
      const anchor = target.closest('a');
      if (anchor) { event.preventDefault(); post('openLink', { href: anchor.getAttribute('href') }); return; }
      let from: number;
      try { from = view.posAtDOM(dom); } catch { return; }
      if (target.closest('[data-task]')) {
        event.preventDefault();
        if (view.state.readOnly || view.composing || view.state.field(previewOptions).composing) return;
        const index = [...dom.querySelectorAll('[data-task]')].indexOf(target.closest('[data-task]')!);
        const matches = [...this.block.source.matchAll(/^[ \t]*(?:[-+*]|\d+[.)])\s+\[([ xX])\]/gm)];
        const match = matches[index];
        if (match) {
          const offset = from + match.index! + match[0].lastIndexOf('[') + 1;
          view.dispatch({ changes: { from: offset, to: offset + 1, insert: match[1] === ' ' ? 'x' : ' ' }, userEvent: 'input' });
        }
        return;
      }
      event.preventDefault();
      const rect = dom.getBoundingClientRect();
      const fraction = Math.max(0, Math.min(1, (event.clientY - rect.top) / Math.max(1, rect.height)));
      const lines = this.block.source.split('\n');
      const line = Math.min(lines.length - 1, Math.floor(fraction * lines.length));
      const offset = lines.slice(0, line).reduce((total, value) => total + value.length + 1, 0);
      view.dispatch({ selection: EditorSelection.cursor(Math.min(view.state.doc.length, from + offset)), scrollIntoView: false });
      view.focus();
    });
    dom.querySelectorAll('img').forEach(img => {
      img.addEventListener('load', () => view.requestMeasure());
      img.addEventListener('error', () => {
        const placeholder = document.createElement('button'); placeholder.className = 'image-placeholder';
        placeholder.textContent = `이미지를 읽을 수 없습니다 · ${img.alt || '경로 확인'} · 폴더 접근 허용`;
        placeholder.addEventListener('mousedown', event => { event.stopPropagation(); event.preventDefault(); post('grantFolder'); });
        img.replaceWith(placeholder); view.requestMeasure();
      });
    });
    return dom;
  }
  ignoreEvent() { return true; }
  get estimatedHeight() { return Math.min(500, Math.max(35, this.block.source.split('\n').length * 29)); }
}

function decorations(state: EditorState, blocks: Block[]): DecorationSet {
  const options = state.field(previewOptions);
  if (options.sourceMode) return Decoration.none;
  const ranges = [];
  // Blank source lines keep the same height even while the caret is on them.
  // This makes heading and paragraph spacing independent of focus.
  for (let number = 1; number <= state.doc.lines; number++) {
    const line = state.doc.line(number);
    if (!line.length) ranges.push(Decoration.line({ class: 'md-spacer' }).range(line.from));
  }
  for (let index = 0; index < blocks.length; index++) {
    const block = blocks[index];
    if (decorateTextBlock(state, block, ranges, current => current.field(previewOptions).composing)) continue;
    const end = blocks[index + 1]?.from ?? state.doc.length;
    const active = state.selection.ranges.some(range => range.empty
      ? range.from >= block.from && (range.from < end || (end === state.doc.length && range.from === end))
      : range.from < end && range.to > block.from);
    if (active) {
      const heading = /^(?:ATX|Setext)Heading([1-6])$/.exec(block.kind);
      for (let pos = state.doc.lineAt(block.from).from; pos <= block.to;) {
        ranges.push(Decoration.line({ class: `active-source-line${heading ? ` source-heading-${heading[1]}` : ''}` }).range(pos));
        const line = state.doc.lineAt(pos); if (line.to >= state.doc.length) break; pos = line.to + 1;
      }
    } else if (block.from < block.to) {
      // Keep one source line break between widgets so CodeMirror can virtualize separate block lines.
      const replacementEnd = blocks[index + 1] ? Math.max(block.to, end - 1) : block.to;
      ranges.push(Decoration.replace({ widget: new PreviewWidget(block, options.settings, options.generation, session.sessionID), block: true, inclusive: false }).range(block.from, replacementEnd));
    }
  }
  return Decoration.set(ranges, true);
}

export const livePreview = StateField.define<{ blocks: Block[]; decorations: DecorationSet; fragments: readonly TreeFragment[] }>({
  create(state) {
    const source = state.doc.toString(), tree = markdownParser.parse(source), blocks = blocksFor(source, tree);
    return { blocks, decorations: decorations(state, blocks), fragments: TreeFragment.addTree(tree) };
  },
  update(value, tr) {
    const options = tr.state.field(previewOptions);
    let fragments = value.fragments;
    if (tr.docChanged) {
      const changes: {fromA:number; toA:number; fromB:number; toB:number}[] = [];
      tr.changes.iterChangedRanges((fromA, toA, fromB, toB) => changes.push({fromA, toA, fromB, toB}));
      fragments = TreeFragment.applyChanges(fragments, changes);
    }
    if (options.composing) return { blocks: value.blocks, decorations: value.decorations.map(tr.changes), fragments };
    if (!tr.docChanged && !tr.selection && !tr.effects.length) return value;
    const previouslyComposing = tr.startState.field(previewOptions).composing;
    let blocks = value.blocks;
    if (tr.docChanged || previouslyComposing) {
      const source = tr.state.doc.toString(), tree = markdownParser.parse(source, fragments);
      blocks = blocksFor(source, tree); fragments = TreeFragment.addTree(tree);
    }
    return { blocks, decorations: decorations(tr.state, blocks), fragments };
  },
  provide: field => EditorView.decorations.from(field, value => value.decorations),
});
