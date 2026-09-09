import { StateEffect, StateField, EditorSelection, type EditorState, type Range, type Transaction } from '@codemirror/state';
import { EditorView, Decoration, WidgetType, type DecorationSet } from '@codemirror/view';
import { TreeFragment, type Tree } from '@lezer/common';
import { blocksFor, markdownParser, type Block } from './markdown';
import { renderBlock, renderDiagram } from './render';
import { defaultSettings, post, session, type Settings } from './protocol';
import { decorateTextBlock, toggleTaskAt } from './textPreview';

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
    dom.addEventListener('click', event => {
      const button = (event.target as HTMLElement).closest('[data-task]');
      if (!button) return;
      event.preventDefault(); event.stopPropagation();
      if (view.state.readOnly || view.composing || view.state.field(previewOptions).composing) return;
      let from: number;
      try { from = view.posAtDOM(dom); } catch { return; }
      const offset = Number(button.getAttribute('data-task'));
      if (Number.isInteger(offset) && offset > 0 && offset < this.block.source.length) {
        toggleTaskAt(view, button, from + offset, this.block.source[offset] === ' ' ? 'x' : ' ');
      }
    });
    dom.addEventListener('mousedown', event => {
      const target = event.target as HTMLElement;
      if (target.closest('[data-remote-images]')) { event.preventDefault(); post('remoteImages'); return; }
      const anchor = target.closest('a');
      if (anchor) { event.preventDefault(); post('openLink', { href: anchor.getAttribute('href') }); return; }
      let from: number;
      try { from = view.posAtDOM(dom); } catch { return; }
      if (target.closest('[data-task]')) {
        event.preventDefault();
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

const spacerDecoration = Decoration.line({ class: 'md-spacer' });

function decorations(state: EditorState, blocks: Block[]): DecorationSet {
  const options = state.field(previewOptions);
  if (options.sourceMode) return Decoration.none;
  const ranges = [];
  // Blank source lines keep the same height even while the caret is on them.
  // This makes heading and paragraph spacing independent of focus.
  for (let number = 1; number <= state.doc.lines; number++) {
    const line = state.doc.line(number);
    if (!line.length) ranges.push(spacerDecoration.range(line.from));
  }
  for (let index = 0; index < blocks.length; index++) decorateBlock(state, blocks, index, ranges);
  return Decoration.set(ranges, true);
}

function decorateBlock(state: EditorState, blocks: Block[], index: number, ranges: Range<Decoration>[]) {
    const options = state.field(previewOptions);
    const block = blocks[index];
    if (decorateTextBlock(state, block, ranges, current => current.field(previewOptions).composing)) return;
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

type Span = { from: number; to: number };
function mergeSpans(spans: Span[]): Span[] {
  const result: Span[] = [];
  for (const span of spans.sort((a, b) => a.from - b.from)) {
    const previous = result.at(-1);
    if (previous && span.from <= previous.to) previous.to = Math.max(previous.to, span.to);
    else result.push({ ...span });
  }
  return result;
}
function contains(spans: Span[], position: number): boolean {
  let low = 0, high = spans.length;
  while (low < high) { const mid = (low + high) >>> 1; if (spans[mid].to <= position) low = mid + 1; else high = mid; }
  return low < spans.length && spans[low].from <= position;
}
function selectedBlocks(state: EditorState, blocks: Block[]): Set<number> {
  const result = new Set<number>();
  for (const range of state.selection.ranges) {
    let low = 0, high = blocks.length;
    while (low < high) { const mid = (low + high) >>> 1; if ((blocks[mid + 1]?.from ?? state.doc.length + 1) < range.from) low = mid + 1; else high = mid; }
    for (let index = low; index < blocks.length && blocks[index].from <= range.to; index++) result.add(index);
  }
  return result;
}
function updateEditedDecorations(previous: { blocks: Block[]; decorations: DecorationSet }, tr: Transaction, blocks: Block[]): DecorationSet {
  const old = previous.blocks, mappedStarts = new Map<number, number[]>();
  old.forEach((block, index) => {
    const from = tr.changes.mapPos(block.from, 1), bucket = mappedStarts.get(from);
    if (bucket) bucket.push(index); else mappedStarts.set(from, [index]);
  });
  const selectedOld = selectedBlocks(tr.startState, old), dirtyNew = selectedBlocks(tr.state, blocks);
  const matchedOld = new Set<number>(), dirtyOld = new Set<number>(selectedOld);
  blocks.forEach((block, index) => {
    const end = blocks[index + 1]?.from ?? tr.state.doc.length;
    const match = mappedStarts.get(block.from)?.find(oldIndex => {
      const before = old[oldIndex], oldEnd = old[oldIndex + 1]?.from ?? tr.startState.doc.length;
      return before.kind === block.kind && before.source === block.source && tr.changes.mapPos(before.to, -1) === block.to
        && tr.changes.mapPos(Math.max(before.to, oldEnd - 1), -1) === Math.max(block.to, end - 1);
    });
    if (match === undefined) dirtyNew.add(index);
    else {
      matchedOld.add(match);
      if (selectedOld.has(match)) dirtyNew.add(index);
      if (dirtyNew.has(index)) dirtyOld.add(match);
    }
  });
  old.forEach((_, index) => { if (!matchedOld.has(index)) dirtyOld.add(index); });
  const oldSpans = mergeSpans([...dirtyOld].map(index => ({ from: tr.startState.doc.lineAt(old[index].from).from, to: old[index + 1]?.from ?? tr.startState.doc.length + 1 })));
  const oldLines: Span[] = [], newLines: Span[] = [];
  tr.changes.iterChangedRanges((fromA, toA, fromB, toB) => {
    oldLines.push({ from: tr.startState.doc.lineAt(fromA).from, to: tr.startState.doc.lineAt(toA).to + 1 });
    newLines.push({ from: tr.state.doc.lineAt(fromB).from, to: tr.state.doc.lineAt(toB).to + 1 });
  });
  const oldLineSpans = mergeSpans(oldLines), additions: Range<Decoration>[] = [];
  for (const index of [...dirtyNew].sort((a, b) => a - b)) decorateBlock(tr.state, blocks, index, additions);
  for (const span of mergeSpans(newLines)) {
    for (let number = tr.state.doc.lineAt(span.from).number; number <= tr.state.doc.lines; number++) {
      const line = tr.state.doc.line(number);
      if (line.from >= span.to) break;
      if (!line.length) additions.push(spacerDecoration.range(line.from));
    }
  }
  return previous.decorations.update({
    filter: (from, _to, decoration) => !contains(decoration === spacerDecoration ? oldLineSpans : oldSpans, from),
  }).map(tr.changes).update({ add: additions, sort: true });
}

export const livePreview = StateField.define<{ blocks: Block[]; decorations: DecorationSet; fragments: readonly TreeFragment[]; tree: Tree }>({
  create(state) {
    const source = state.doc.toString(), tree = markdownParser.parse(source), blocks = blocksFor(source, tree);
    return { blocks, decorations: decorations(state, blocks), fragments: TreeFragment.addTree(tree), tree };
  },
  update(value, tr) {
    const options = tr.state.field(previewOptions);
    let fragments = value.fragments;
    if (tr.docChanged) {
      const changes: {fromA:number; toA:number; fromB:number; toB:number}[] = [];
      tr.changes.iterChangedRanges((fromA, toA, fromB, toB) => changes.push({fromA, toA, fromB, toB}));
      fragments = TreeFragment.applyChanges(fragments, changes);
    }
    if (options.composing) return { blocks: value.blocks, decorations: value.decorations.map(tr.changes), fragments, tree: value.tree };
    const before = tr.startState.field(previewOptions);
    const previewChanged = options !== before;
    // Read-only locks, scroll requests and unrelated effects do not change Markdown decoration.
    if (!tr.docChanged && !tr.selection && !previewChanged) return value;
    if (!tr.docChanged && !previewChanged) {
      if (options.sourceMode || tr.startState.selection.eq(tr.state.selection)) return value;
      const affected = new Set<number>();
      for (const selection of [tr.startState.selection, tr.state.selection]) {
        for (const range of selection.ranges) {
          // Find the first block whose display span can overlap this selection.
          let low = 0, high = value.blocks.length;
          while (low < high) { const mid = (low + high) >>> 1; if ((value.blocks[mid + 1]?.from ?? tr.state.doc.length + 1) < range.from) low = mid + 1; else high = mid; }
          for (let index = low; index < value.blocks.length && value.blocks[index].from <= range.to; index++) affected.add(index);
        }
      }
      if (!affected.size) return value;
      const indices = [...affected].sort((a, b) => a - b);
      const spans: { from: number; to: number }[] = [];
      for (const index of indices) {
        const from = tr.state.doc.lineAt(value.blocks[index].from).from, to = value.blocks[index + 1]?.from ?? tr.state.doc.length + 1;
        const previous = spans.at(-1);
        if (previous && from <= previous.to) previous.to = to;
        else spans.push({ from, to });
      }
      const ranges: Range<Decoration>[] = [];
      for (const index of indices) decorateBlock(tr.state, value.blocks, index, ranges);
      return { ...value, decorations: value.decorations.update({
        filterFrom: spans[0].from, filterTo: spans.at(-1)!.to,
        filter: (from, _to, decoration) => decoration === spacerDecoration || !spans.some(span => from >= span.from && from < span.to),
        add: ranges, sort: true,
      }) };
    }
    const previouslyComposing = tr.startState.field(previewOptions).composing;
    let blocks = value.blocks, tree = value.tree;
    if (tr.docChanged || previouslyComposing) {
      const source = tr.state.doc.toString(); tree = markdownParser.parse(source, fragments);
      blocks = blocksFor(source, tree); fragments = TreeFragment.addTree(tree);
    }
    const nextDecorations = tr.docChanged && !previouslyComposing && !previewChanged && !options.sourceMode
      ? updateEditedDecorations(value, tr, blocks) : decorations(tr.state, blocks);
    return { blocks, decorations: nextDecorations, fragments, tree };
  },
  provide: field => EditorView.decorations.from(field, value => value.decorations),
});
