import { StateEffect, StateField, EditorSelection, type EditorState, type Range, type Transaction } from '@codemirror/state';
import { EditorView, Decoration, WidgetType, type DecorationSet } from '@codemirror/view';
import { undo, redo } from '@codemirror/commands';
import { TreeFragment, type SyntaxNode, type Tree } from '@lezer/common';
import { blocksFor, markdownParser, type Block } from './markdown';
import { documentRenderContext, needsDocumentContext, renderBlock, renderDiagram, type RenderContext } from './render';
import { defaultSettings, post, session, type Settings } from './protocol';
import { decorateTextBlock, toggleTaskAt } from './textPreview';
import { escapeCellPipes, parseTable, serializeTable, withTableAlignment, withTableColumn, withTableRow } from './table';
import { codeFenceInfo, codeLanguageLabel, codeLanguageOptions } from './codeLanguage';

export const setSourceMode = StateEffect.define<boolean>();
export const setComposition = StateEffect.define<boolean>();
export const updateSettings = StateEffect.define<Settings>();
export const setTableEditing = StateEffect.define<number | null>();
export const setDiagramEditing = StateEffect.define<number | null>();
let tableCompositionActive = false;
export function isTableComposing() { return tableCompositionActive; }
export function clearTableComposition() { tableCompositionActive = false; }
export const previewOptions = StateField.define({
  create: () => ({ sourceMode: false, composing: false, settings: { ...defaultSettings }, generation: 0, tableEditing: null as number | null, diagramEditing: null as number | null }),
  update(value, transaction) {
    if (transaction.docChanged && value.tableEditing !== null) value = { ...value, tableEditing: transaction.changes.mapPos(value.tableEditing, 1) };
    if (transaction.docChanged && value.diagramEditing !== null) value = { ...value, diagramEditing: transaction.changes.mapPos(value.diagramEditing, 1) };
    for (const effect of transaction.effects) {
      if (effect.is(setSourceMode)) value = { ...value, sourceMode: effect.value };
      if (effect.is(setComposition)) value = { ...value, composing: effect.value };
      if (effect.is(updateSettings)) value = { ...value, settings: effect.value, generation: value.generation + 1 };
      if (effect.is(setTableEditing)) value = { ...value, tableEditing: effect.value };
      if (effect.is(setDiagramEditing)) value = { ...value, diagramEditing: effect.value };
    }
    return value;
  },
});

function isMermaidBlock(block: Block) { return codeFenceInfo(block.source)?.language.toLowerCase() === 'mermaid'; }
function isCodeBlock(block: Block) { return block.kind === 'FencedCode' || block.kind === 'CodeBlock'; }
function sourceSelected(state: EditorState, block: Block) {
  return state.selection.ranges.some(range => range.empty ? range.from >= block.from && range.from < block.to : range.from < block.to && range.to > block.from);
}

function nestedCodeBlocks(state: EditorState, block: Block) {
  const nested: Block[] = [];
  const cursor = block.node?.cursor();
  if (!cursor) return nested;
  while (cursor.next()) {
    const node = cursor.node;
    if (node.from >= block.to) break; // A SyntaxNode cursor can continue into later sibling blocks.
    if (!isCodeBlock({ ...block, kind: node.name })) continue;
    nested.push({ from: node.from, to: node.to, kind: node.name, source: state.sliceDoc(node.from, node.to), node });
  }
  return nested;
}

function currentBlockForDOM(view: EditorView, dom: HTMLElement, fallbackFrom: number) {
  try {
    const at = view.posAtDOM(dom);
    const blocks = view.state.field(livePreview).blocks;
    return blocks.find(block => block.from === at) ?? blocks.find(block => block.to === at) ?? blocks.find(block => block.from <= at && at <= block.to)
      ?? blocks.find(block => block.from === fallbackFrom);
  } catch {
    return view.state.field(livePreview).blocks.find(block => block.from === fallbackFrom);
  }
}

function codeBlockAt(state: EditorState, position: number): Block | undefined {
  const tree = state.field(livePreview).tree;
  const bounded = Math.max(0, Math.min(state.doc.length, position));
  // A header inside a list item's replacement maps to the outer List node in
  // CodeMirror. Walk the syntax tree instead, so nested fences retain their
  // actual source range and never rewrite the list or blockquote prefix.
  for (const at of [bounded, Math.min(state.doc.length, bounded + 1)]) {
    let node: SyntaxNode | null = tree.resolveInner(at, 1);
    while (node) {
      if (node.name === 'FencedCode' || node.name === 'CodeBlock') {
        return { from: node.from, to: node.to, kind: node.name, source: state.sliceDoc(node.from, node.to), node };
      }
      node = node.parent;
    }
  }
}

function currentCodeBlockForDOM(view: EditorView, dom: HTMLElement, fallbackFrom: number) {
  const preview = dom.closest<HTMLElement>('.preview-widget');
  if (preview) {
    const outer = currentBlockForDOM(view, preview, fallbackFrom);
    if (outer) {
      const candidates = isCodeBlock(outer) ? [outer] : nestedCodeBlocks(view.state, outer);
      const headers = [...preview.querySelectorAll<HTMLElement>('[data-code-language]')];
      const candidate = candidates[headers.indexOf(dom)];
      if (candidate) return candidate;
    }
  }
  try {
    const found = codeBlockAt(view.state, view.posAtDOM(dom));
    if (found) return found;
  } catch { /* Widgets can map to their containing list or quote. */ }
  return codeBlockAt(view.state, fallbackFrom)
    ?? view.state.field(livePreview).blocks.find(block => block.from === fallbackFrom && isCodeBlock(block));
}

function codeContentBounds(state: EditorState, block: Block) {
  if (block.kind !== 'FencedCode') return { from: block.from, to: block.to };
  const first = state.doc.lineAt(block.from), last = state.doc.lineAt(Math.max(block.from, block.to - 1));
  // Fenced blocks use their first and last source lines as delimiters. A
  // malformed one-line fence has no editable body, so leave its source intact.
  if (first.number >= last.number) return { from: block.from, to: block.to };
  const marks = block.node?.getChildren('CodeMark') ?? [];
  const closed = marks.length > 1 && state.doc.lineAt(marks.at(-1)!.from).number === last.number;
  return { from: Math.min(block.to, first.to + 1), to: closed ? Math.max(first.to + 1, last.from - 1) : block.to };
}

function previewReplacementFrom(state: EditorState, block: Block) {
  // A CodeBlock node starts after its four-space marker. Replacing from the
  // physical line start prevents that marker from becoming a leftover empty
  // display line before the reading widget.
  return block.kind === 'CodeBlock' ? state.doc.lineAt(block.from).from : block.from;
}

function previewReplacementEnd(state: EditorState, block: Block, nextBlockFrom?: number) {
  if (nextBlockFrom === undefined) return block.to;
  if (!isCodeBlock(block)) return Math.max(block.to, nextBlockFrom - 1);
  // A fenced closing line has no live height. Replace that line's terminating
  // break, but leave every following blank source line in place so reading and
  // editing preserve the same paragraph position after a code block.
  return Math.min(nextBlockFrom, block.to < state.doc.length ? block.to + 1 : block.to);
}

function isEmptyFencedCode(state: EditorState, block: Block) {
  if (block.kind !== 'FencedCode') return false;
  const marks = block.node?.getChildren('CodeMark') ?? [];
  return marks.length > 1 && state.doc.lineAt(marks[0].from).number + 1 === state.doc.lineAt(marks.at(-1)!.from).number;
}

function codeSourceLines(state: EditorState, block: Block, ranges: Range<Decoration>[], extraClass = '') {
  const fenced = block.kind === 'FencedCode';
  const fenceLines = new Set(block.node?.getChildren('CodeMark').map(mark => state.doc.lineAt(mark.from).number) ?? []);
  const first = state.doc.lineAt(block.from).number, last = state.doc.lineAt(Math.max(block.from, block.to - 1)).number;
  const openingFence = fenced && fenceLines.has(first);
  const bodyLines: number[] = [];
  for (let number = first; number <= last; number++) {
    if (!(fenced && fenceLines.has(number))) bodyLines.push(number);
  }
  const firstBody = bodyLines[0], lastBody = bodyLines.at(-1);
  for (let number = first; number <= last; number++) {
    const line = state.doc.line(number);
    const fence = fenced && fenceLines.has(number);
    const languageLine = openingFence && number === first;
    // The frame belongs to editable source lines, never to fence delimiters.
    // Keeping delimiter geometry independent from the selection prevents an
    // arrow-key visit to either fence from moving the header or code surface.
    const edge = `${number === firstBody ? ' code-source-first' : ''}${number === lastBody ? ' code-source-last' : ''}`;
    ranges.push(Decoration.line({ class: `code-source-line${edge}${fence && !languageLine ? ' code-fence-line' : ''}${languageLine ? ' code-language-line' : ''}${extraClass}` }).range(line.from));
    if (languageLine) {
      // Replacing the whole opening line leaves the document's fence and its
      // optional trailing attributes untouched while exposing only the
      // language picker in the live code header. Delimiters remain source-mode
      // edits, so this replacement stays in place even when a keyboard cursor
      // reaches the opening fence.
      ranges.push(Decoration.replace({ widget: new CodeLanguageWidget(block.source, block.from, true) }).range(line.from, line.to));
    } else if (fence) {
      // Pair the hidden closing delimiter with the view's atomic range set so
      // normal live-mode arrows and deletion cannot land in invisible syntax.
      ranges.push(Decoration.replace({}).range(line.from, line.to));
    }
  }
  if (!fenced) {
    // CodeBlock nodes begin after their four-space source marker, but line
    // decorations begin at the physical line start. Put the block widget at
    // that same start so it does not split the code line into an unstyled
    // prefix and a separate body line.
    ranges.push(Decoration.widget({ widget: new CodeLanguageWidget(block.source, block.from, true), block: true, side: -1 }).range(state.doc.lineAt(block.from).from));
  }
}

function stopCodeLanguageEvent(event: Event) {
  // Ordinary picker keys stay local and cannot type into the contenteditable
  // document behind the control. Mod+Z is handled directly by the picker.
  if (event instanceof KeyboardEvent && (event.metaKey || event.ctrlKey || event.altKey)) return;
  event.stopPropagation();
}

function codeLanguageHeader(view: EditorView, source: string, fallbackFrom: number, sourceHeader: boolean) {
  const info = codeFenceInfo(source);
  const header = document.createElement('div');
  header.className = `code-language-header${sourceHeader ? ' code-language-live-header' : ''}${sourceHeader && !info ? ' code-language-source-header' : ''}`;
  header.dataset.codeLanguage = ''; header.dataset.codeBlockFrom = String(fallbackFrom);
  const label = codeLanguageLabel(info?.language ?? '');
  if (!info) {
    const staticLabel = document.createElement('span');
    staticLabel.className = 'code-language-label'; staticLabel.textContent = label;
    staticLabel.setAttribute('aria-label', '코드 언어'); header.append(staticLabel); return header;
  }
  const select = document.createElement('select');
  select.className = 'code-language-select'; select.setAttribute('aria-label', '코드 언어');
  select.disabled = view.state.readOnly;
  // Aliases such as py and plaintext use their canonical option without
  // rewriting source merely because the picker is opened. Unknown tokens get
  // one visible option of their own so their spelling is preserved.
  const selectedValue = codeLanguageOptions.find(option => option.label === label)?.value ?? info.language;
  const options = codeLanguageOptions.some(option => option.value === selectedValue)
    ? codeLanguageOptions : [{ value: info.language, label }, ...codeLanguageOptions];
  for (const option of options) {
    const element = document.createElement('option'); element.value = option.value; element.textContent = option.label;
    if (option.value === selectedValue) element.selected = true;
    select.append(element);
  }
  // A native select remains fully keyboard-operable, but its keys must not
  // reach CodeMirror's contenteditable selection and insert source text.
  select.addEventListener('keydown', event => {
    if (!(event.metaKey || event.ctrlKey) || event.key.toLowerCase() !== 'z') return;
    event.preventDefault(); event.stopPropagation();
    const current = currentCodeBlockForDOM(view, header, fallbackFrom);
    (event.shiftKey ? redo : undo)(view);
    const blockFrom = current?.from ?? fallbackFrom;
    queueMicrotask(() => [...view.dom.querySelectorAll<HTMLElement>('[data-code-language]')]
      .find(element => Number(element.dataset.codeBlockFrom) === blockFrom)
      ?.querySelector<HTMLSelectElement>('.code-language-select')?.focus({ preventScroll: true }));
  });
  for (const event of ['mousedown', 'keydown', 'keyup', 'keypress', 'beforeinput']) select.addEventListener(event, stopCodeLanguageEvent);
  select.addEventListener('change', event => {
    event.stopPropagation();
    if (view.state.readOnly || view.composing || view.state.field(previewOptions).composing) return;
    const current = currentCodeBlockForDOM(view, header, fallbackFrom);
    if (!current) return;
    const currentInfo = codeFenceInfo(current.source);
    if (!currentInfo) return;
    const openingLineEnd = current.source.search(/\r?\n/);
    const trailingInfo = current.source.slice(currentInfo.to, openingLineEnd < 0 ? current.source.length : openingLineEnd);
    // Removing a language in front of fence attributes would turn the first
    // attribute into a new language token. Keep an explicit text token only
    // for that case; otherwise an empty language remains genuinely empty.
    const nextLanguage = !select.value && /\S/.test(trailingInfo) ? 'text' : select.value;
    if (currentInfo.language === nextLanguage) return;
    view.dispatch({ changes: {
      from: current.from + currentInfo.from,
      to: current.from + currentInfo.to,
      insert: nextLanguage,
    }, userEvent: 'input.code-language' });
    // Changing an option replaces its widget. Restore focus without changing
    // the viewport so native keyboard selection can immediately undo/redo.
    queueMicrotask(() => [...view.dom.querySelectorAll<HTMLElement>('[data-code-language]')]
      .find(element => Number(element.dataset.codeBlockFrom) === current.from)
      ?.querySelector<HTMLSelectElement>('.code-language-select')?.focus({ preventScroll: true }));
  });
  header.append(select); return header;
}

class CodeLanguageWidget extends WidgetType {
  constructor(readonly source: string, readonly blockFrom: number, readonly sourceHeader: boolean) { super(); }
  eq(other: CodeLanguageWidget) { return this.source === other.source && this.blockFrom === other.blockFrom && this.sourceHeader === other.sourceHeader; }
  toDOM(view: EditorView) { return codeLanguageHeader(view, this.source, this.blockFrom, this.sourceHeader); }
  ignoreEvent() { return true; }
}

function protectDiagramControl(button: HTMLButtonElement) {
  // These controls live inside CodeMirror's contenteditable container. WebKit
  // otherwise inserts printable keys at its retained document selection even
  // while the button has focus. Preserve native Enter/Space button activation.
  button.addEventListener('keydown', event => {
    if (event.key.length === 1 && event.key !== ' ' && !event.metaKey && !event.ctrlKey && !event.altKey) event.preventDefault();
  });
}

function diagramDOM(view: EditorView, source: string, theme: string, sessionID: string, generation: number, editing: boolean, blockFrom: number) {
  const dom = document.createElement('div');
  dom.className = `diagram-block${editing ? ' diagram-block-editing' : ''}`;
  dom.dataset.kind = 'Mermaid'; dom.dataset.blockFrom = String(blockFrom);
  const canvas = document.createElement('div'); canvas.className = 'diagram-render'; dom.append(canvas);
  if (editing) {
    const finish = document.createElement('button'); finish.type = 'button'; finish.className = 'diagram-edit-toggle'; finish.dataset.diagramFinish = '';
    finish.textContent = '편집 완료'; finish.setAttribute('aria-label', '다이어그램 편집 완료');
    protectDiagramControl(finish);
    finish.addEventListener('mousedown', event => { event.preventDefault(); event.stopPropagation(); });
    finish.addEventListener('click', event => {
      event.preventDefault();
      if (view.state.readOnly || view.composing || view.state.field(previewOptions).composing) return;
      const current = currentBlockForDOM(view, dom, blockFrom);
      if (!current) return;
      const at = Math.min(view.state.doc.length, current.to + 1);
      view.dispatch({ selection: EditorSelection.cursor(at), effects: setDiagramEditing.of(null) });
      // Completing a block must not leave typing at the end of its closing
      // fence. Restore focus to its reading control, including at document EOF.
      queueMicrotask(() => {
        const canvas = [...view.dom.querySelectorAll<HTMLElement>('.diagram-block[data-block-from]')]
          .find(element => Number(element.dataset.blockFrom) === current.from);
        canvas?.closest('.preview-widget')?.querySelector<HTMLButtonElement>('[data-diagram-edit]')?.focus({ preventScroll: true });
      });
    });
    dom.append(finish);
  }
  queueMicrotask(() => renderDiagram(canvas, source, theme,
    () => session.sessionID === sessionID && view.state.field(previewOptions).generation === generation,
    () => view.requestMeasure()));
  return dom;
}

class PreviewWidget extends WidgetType {
  constructor(readonly block: Block, readonly settings: Settings, readonly generation: number, readonly sessionID: string, readonly active: boolean, readonly context: RenderContext) { super(); }
  eq(other: PreviewWidget) { return this.block.from === other.block.from && this.block.source === other.block.source && this.generation === other.generation && this.sessionID === other.sessionID && this.active === other.active && this.context === other.context; }
  toDOM(view: EditorView) {
    const isMermaid = isMermaidBlock(this.block);
    // Lezer's CodeBlock range begins after the four-space marker. Restore it
    // only for rendering so indented code keeps the same code surface without
    // changing the document or its source offsets.
    const renderSource = this.block.kind === 'CodeBlock'
      ? this.block.source.split(/\r?\n/).map(line => `    ${line}`).join('\n') : this.block.source;
    const dom = isMermaid ? document.createElement('div') : renderBlock(renderSource, this.settings, this.context, this.block.from);
    dom.classList.add('preview-widget'); if (this.active) dom.classList.add('focus-active'); dom.dataset.kind = this.block.kind;
    dom.setAttribute('aria-label', '클릭하여 이 블록 편집');
    const visibleCodeBlocks = isCodeBlock(this.block) ? [this.block] : nestedCodeBlocks(view.state, this.block);
    const codePreviews = [...dom.querySelectorAll('pre')];
    visibleCodeBlocks.forEach((code, index) => {
      const header = codeLanguageHeader(view, code.source, code.from, false);
      const preview = codePreviews[index];
      if (preview) preview.before(header);
      else if (code === this.block) dom.prepend(header);
    });
    if (isMermaid) {
      dom.append(diagramDOM(view, this.block.source, this.settings.theme, this.sessionID, this.generation, false, this.block.from));
      if (!view.state.readOnly) {
        const edit = document.createElement('button'); edit.type = 'button'; edit.className = 'diagram-edit-toggle'; edit.dataset.diagramEdit = '';
        edit.textContent = '편집'; edit.setAttribute('aria-label', '다이어그램 편집');
        protectDiagramControl(edit);
        edit.addEventListener('mousedown', event => { event.preventDefault(); event.stopPropagation(); });
        edit.addEventListener('click', event => {
          event.preventDefault();
          if (view.state.readOnly || view.composing || view.state.field(previewOptions).composing) return;
          const current = currentBlockForDOM(view, dom, this.block.from);
          if (!current) return;
          const at = codeContentBounds(view.state, current).from;
          view.dispatch({ selection: EditorSelection.cursor(at), effects: [setDiagramEditing.of(current.from), EditorView.scrollIntoView(at, { y: 'center' })] });
          view.focus();
        });
        dom.prepend(edit);
      }
    }
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
      if (anchor) {
        event.preventDefault();
        const rawJump = anchor.getAttribute('data-jump');
        if (rawJump !== null) {
          const jump = Number(rawJump);
          if (Number.isInteger(jump) && jump >= 0) { view.dispatch({ selection: EditorSelection.cursor(jump), effects: EditorView.scrollIntoView(jump, { y: 'center' }) }); view.focus(); return; }
        }
        const href = anchor.getAttribute('href') ?? '';
        const semanticPosition = href.startsWith('#') ? this.context.jumps.get(href.slice(1)) : undefined;
        if (semanticPosition !== undefined) {
          view.dispatch({ selection: EditorSelection.cursor(semanticPosition), effects: EditorView.scrollIntoView(semanticPosition, { y: 'center' }) }); view.focus(); return;
        }
        if (href.startsWith('#')) {
          const destination = document.getElementById(href.slice(1))?.closest<HTMLElement>('.preview-widget');
          if (destination) {
            try { const at = view.posAtDOM(destination); view.dispatch({ selection: EditorSelection.cursor(at), effects: EditorView.scrollIntoView(at, { y: 'center' }) }); view.focus(); return; } catch { /* host fallback */ }
          }
        }
        post('openLink', { href }); return;
      }
      if (target.closest('[data-task]')) {
        event.preventDefault();
        return;
      }
      if (isMermaid || view.state.readOnly || view.composing || view.state.field(previewOptions).composing) {
        event.preventDefault(); event.stopPropagation(); return;
      }
      let from: number;
      try { from = view.posAtDOM(dom); } catch { return; }
      event.preventDefault();
      const rect = dom.getBoundingClientRect();
      const fraction = Math.max(0, Math.min(1, (event.clientY - rect.top) / Math.max(1, rect.height)));
      const lines = this.block.source.split('\n');
      const line = Math.min(lines.length - 1, Math.floor(fraction * lines.length));
      const offset = lines.slice(0, line).reduce((total, value) => total + value.length + 1, 0);
      const current = currentBlockForDOM(view, dom, this.block.from);
      const bounds = codeContentBounds(view.state, current ?? this.block);
      // A block replacement can map its DOM back to the end of an indented
      // CodeBlock. Its syntax range is the stable source anchor for clicks.
      const selectionFrom = isCodeBlock(this.block) ? (current ?? this.block).from : from;
      const selectionTarget = Math.min(view.state.doc.length, selectionFrom + offset);
      view.dispatch({ selection: EditorSelection.cursor(isCodeBlock(this.block) ? Math.max(bounds.from, Math.min(bounds.to, selectionTarget)) : selectionTarget), scrollIntoView: false });
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

class DiagramWidget extends WidgetType {
  constructor(readonly block: Block, readonly settings: Settings, readonly generation: number, readonly sessionID: string) { super(); }
  eq(other: DiagramWidget) { return this.block.from === other.block.from && this.block.source === other.block.source && this.generation === other.generation && this.sessionID === other.sessionID; }
  toDOM(view: EditorView) { return diagramDOM(view, this.block.source, this.settings.theme, this.sessionID, this.generation, true, this.block.from); }
  ignoreEvent() { return true; }
  get estimatedHeight() { return Math.min(500, Math.max(60, this.block.source.split('\n').length * 29)); }
}

class TableWidget extends WidgetType {
  constructor(readonly block: Block, readonly generation: number, readonly editing: boolean, readonly context: RenderContext) { super(); }
  eq(other: TableWidget) { return this.block.from === other.block.from && this.block.source === other.block.source && this.generation === other.generation && this.editing === other.editing && this.context === other.context; }
  toDOM(view: EditorView) {
    const table = parseTable(this.block.source, this.block.from);
    if (!table) return renderBlock(this.block.source, view.state.field(previewOptions).settings);
    const dom = document.createElement('div'); dom.className = 'preview-widget table-widget'; dom.dataset.kind = 'Table';
    if (!this.editing) {
      const reading = renderBlock(this.block.source, view.state.field(previewOptions).settings, this.context, this.block.from);
      const edit = document.createElement('button'); edit.type = 'button'; edit.className = 'table-edit-toggle'; edit.textContent = '표 편집';
      edit.addEventListener('mousedown', event => { event.preventDefault(); event.stopPropagation(); });
      edit.addEventListener('click', event => { event.preventDefault(); if (!view.state.readOnly) view.dispatch({ effects: setTableEditing.of(this.block.from) }); });
      dom.append(reading, edit); return dom;
    }
    const locked = () => view.state.readOnly || view.composing || view.state.field(previewOptions).composing;
    const currentTable = () => {
      const current = view.state.field(livePreview).blocks.find(candidate => candidate.kind === 'Table' && candidate.from === table.from);
      return current ? parseTable(current.source, current.from) : undefined;
    };
    const replaceTable = (next: typeof table) => {
      if (locked()) return;
      const current = currentTable();
      if (!current) return;
      view.dispatch({ changes: { from: current.from, to: current.to, insert: serializeTable(next) }, userEvent: 'input' });
    };
    const controls = document.createElement('div'); controls.className = 'table-controls'; controls.setAttribute('aria-label', '표 편집');
    let selectedColumn = 0, selectedRow = 2;
    const action = (label: string, run: () => void) => {
      const button = document.createElement('button'); button.type = 'button'; button.textContent = label; button.disabled = locked();
      button.addEventListener('mousedown', event => {
        event.preventDefault();
        const active = document.activeElement;
        if (active instanceof HTMLInputElement && active.classList.contains('table-cell-input')) active.blur();
        setTimeout(run, 0);
      });
      button.addEventListener('click', event => { if (event.detail === 0) run(); });
      controls.append(button); return button;
    };
    action('행 추가', () => { const fresh = currentTable(); if (fresh) replaceTable(withTableRow(fresh, 'add', selectedRow)); });
    const deleteRow = action('행 삭제', () => { const fresh = currentTable(); if (fresh) replaceTable(withTableRow(fresh, 'delete', selectedRow)); });
    action('열 추가', () => { const fresh = currentTable(); if (fresh) replaceTable(withTableColumn(fresh, 'add', selectedColumn)); });
    const deleteColumn = action('열 삭제', () => { const fresh = currentTable(); if (fresh) replaceTable(withTableColumn(fresh, 'delete', selectedColumn)); });
    deleteRow.disabled = locked() || table.rows.length <= 2;
    deleteColumn.disabled = locked() || table.rows[0].length <= 1;
    action('읽기', () => view.dispatch({ effects: setTableEditing.of(null) }));
    const align = document.createElement('select'); align.setAttribute('aria-label', '열 정렬'); align.disabled = locked();
    for (const [value, label] of [['none', '기본'], ['left', '왼쪽'], ['center', '가운데'], ['right', '오른쪽']] as const) {
      const option = document.createElement('option'); option.value = value; option.textContent = label; align.append(option);
    }
    align.addEventListener('change', () => { const fresh = currentTable(); if (fresh) replaceTable(withTableAlignment(fresh, selectedColumn, align.value as 'left' | 'center' | 'right' | 'none')); });
    controls.append(align); dom.append(controls);
    const htmlTable = document.createElement('table');
    table.cells.forEach((row, rowIndex) => {
      if (rowIndex === 1) return; // alignment is controlled above, never exposed as accidental cell text.
      const tr = document.createElement('tr');
      Array.from({ length: Math.max(row.length, table.rows[0].length) }, (_, column) => row[column]).forEach((existingCell, column) => {
        const cell = existingCell ?? { text: '', from: table.to, to: table.to };
        const tag = rowIndex === 0 ? 'th' : 'td', td = document.createElement(tag);
        const input = document.createElement('input'); input.className = 'table-cell-input'; input.value = cell.text; input.disabled = locked();
        input.setAttribute('aria-label', `${rowIndex === 0 ? 1 : rowIndex}행 ${column + 1}열`);
        let composing = false, committing = false;
        const commit = () => {
          if (composing || committing || !input.isConnected || locked() || input.value === cell.text) return;
          const value = escapeCellPipes(input.value.replace(/\n/g, ' '));
          // Replacing a table widget can synchronously blur its focused input
          // in Chromium. Never start a second transaction during that update.
          committing = true;
          try {
          if (!existingCell) {
            const fresh = currentTable();
            if (!fresh) return;
            const rows = fresh.rows.map(values => [...values]);
            while (rows[rowIndex].length <= column) rows[rowIndex].push('');
            rows[rowIndex][column] = value;
            replaceTable({ ...fresh, rows });
          } else view.dispatch({ changes: { from: cell.from, to: cell.to, insert: value }, userEvent: 'input' });
          } finally { committing = false; }
        };
        input.dataset.tableId = String(table.from); input.dataset.row = String(rowIndex); input.dataset.column = String(column);
        input.addEventListener('mousedown', event => event.stopPropagation());
        input.addEventListener('focus', () => { selectedColumn = column; selectedRow = rowIndex; deleteRow.disabled = locked() || rowIndex < 2; align.value = table.alignments[column] ?? 'none'; });
        // Keep a native input stable while typing. Committing per keystroke would
        // replace this widget and break IME/focus; blur, Tab and Enter make one
        // ordinary CodeMirror undo step instead.
        input.addEventListener('blur', commit);
        input.addEventListener('compositionstart', () => { composing = true; tableCompositionActive = true; post('composition', { active: true }); });
        input.addEventListener('compositionend', () => { composing = false; tableCompositionActive = false; post('composition', { active: false }); });
        input.addEventListener('keydown', event => {
          if (event.key === 'Enter') { event.preventDefault(); commit(); return; }
          if (event.key !== 'Tab') return;
          event.preventDefault(); commit();
          const currentRow = rowIndex, currentColumn = column, direction = event.shiftKey ? -1 : 1;
          requestAnimationFrame(() => {
            const inputs = [...document.querySelectorAll<HTMLInputElement>(`.table-cell-input[data-table-id="${table.from}"]`)];
            const current = inputs.findIndex(candidate => Number(candidate.dataset.row) === currentRow && Number(candidate.dataset.column) === currentColumn);
            const next = inputs[current + direction];
            if (next) next.focus();
            else if (!event.shiftKey) {
              const fresh = currentTable();
              if (fresh) {
                const newRow = fresh.rows.length;
                replaceTable(withTableRow(fresh, 'add', fresh.rows.length - 1));
                requestAnimationFrame(() => document.querySelector<HTMLInputElement>(`.table-cell-input[data-table-id="${table.from}"][data-row="${newRow}"][data-column="0"]`)?.focus());
              }
            } else align.focus();
          });
        });
        td.append(input); tr.append(td);
      }); htmlTable.append(tr);
    });
    dom.append(htmlTable); return dom;
  }
  ignoreEvent() { return true; }
  get estimatedHeight() { return Math.max(100, this.block.source.split('\n').length * 42); }
}

const spacerDecoration = Decoration.line({ class: 'md-spacer' });

function decorations(state: EditorState, blocks: Block[], context: RenderContext): DecorationSet {
  const options = state.field(previewOptions);
  if (options.sourceMode) return Decoration.none;
  const ranges = [];
  // Blank source lines keep the same height even while the caret is on them.
  // This makes heading and paragraph spacing independent of focus.
  for (let number = 1; number <= state.doc.lines; number++) {
    const line = state.doc.line(number);
    if (!line.length) ranges.push(spacerDecoration.range(line.from));
  }
  for (let index = 0; index < blocks.length; index++) decorateBlock(state, blocks, index, ranges, context);
  return Decoration.set(ranges, true);
}

function decorateBlock(state: EditorState, blocks: Block[], index: number, ranges: Range<Decoration>[], context: RenderContext) {
    const options = state.field(previewOptions);
    const block = blocks[index];
    const end = blocks[index + 1]?.from ?? state.doc.length;
    const active = state.selection.ranges.some(range => range.empty
      ? range.from >= block.from && (range.from < end || (end === state.doc.length && range.from === end))
      : range.from < end && range.to > block.from);
    if (block.kind === 'Table' && block.from < block.to) {
      const replacementEnd = blocks[index + 1] ? Math.max(block.to, end - 1) : block.to;
      ranges.push(Decoration.replace({ widget: new TableWidget(block, options.generation, options.tableEditing === block.from, context), block: true, inclusive: false }).range(block.from, replacementEnd));
      return;
    }
    const mermaid = isMermaidBlock(block);
    const code = isCodeBlock(block);
    // With no editable body, retain the same framed preview and language
    // picker in live mode. Source mode still exposes both delimiters.
    if (code && isEmptyFencedCode(state, block)) {
      const replacementEnd = previewReplacementEnd(state, block, blocks[index + 1]?.from);
      ranges.push(Decoration.replace({ widget: new PreviewWidget(block, options.settings, options.generation, session.sessionID, active, context), block: true, inclusive: false }).range(previewReplacementFrom(state, block), replacementEnd));
      return;
    }
    const diagramEditing = mermaid && !state.readOnly && (options.diagramEditing === block.from || sourceSelected(state, block));
    // Mermaid stays rendered while its source is edited. Ordinary clicks never
    // select a preview widget; only the explicit button can enter this state.
    if (diagramEditing) {
      codeSourceLines(state, block, ranges, ' diagram-source-line');
      ranges.push(Decoration.widget({ widget: new DiagramWidget(block, options.settings, options.generation, session.sessionID), block: true, side: 1 }).range(block.to));
      return;
    }
    // A transition to read-only must not leave an already-selected source block
    // exposed as an editable-looking surface.
    if (state.readOnly && code && block.from < block.to) {
      const replacementEnd = previewReplacementEnd(state, block, blocks[index + 1]?.from);
      ranges.push(Decoration.replace({ widget: new PreviewWidget(block, options.settings, options.generation, session.sessionID, false, context), block: true, inclusive: false }).range(previewReplacementFrom(state, block), replacementEnd));
      return;
    }
    // Reference links and notes need the cached whole-document markdown-it
    // environment; line decorations cannot resolve definitions in another block.
    const documentScoped = needsDocumentContext(block.source, context);
    if (!documentScoped && decorateTextBlock(state, block, ranges, current => current.field(previewOptions).composing)) {
      if (options.settings.focusMode) {
        for (let pos = state.doc.lineAt(block.from).from; pos <= block.to;) {
          ranges.push(Decoration.line({ class: active ? 'focus-active-line' : 'focus-muted-line' }).range(pos));
          const line = state.doc.lineAt(pos); if (line.to >= state.doc.length) break; pos = line.to + 1;
        }
      }
      return;
    }
    // A cursor on the separator immediately after a Mermaid block is outside
    // its source. This lets the Finish button return to the rendered diagram
    // even though CodeMirror's wider display span still considers it active.
    if (mermaid && !sourceSelected(state, block) && block.from < block.to) {
      const replacementEnd = previewReplacementEnd(state, block, blocks[index + 1]?.from);
      ranges.push(Decoration.replace({ widget: new PreviewWidget(block, options.settings, options.generation, session.sessionID, false, context), block: true, inclusive: false }).range(block.from, replacementEnd));
      return;
    }
    if (active && code && !state.readOnly) {
      codeSourceLines(state, block, ranges);
    } else if (active) {
      const heading = /^(?:ATX|Setext)Heading([1-6])$/.exec(block.kind);
      const nested = code ? [] : nestedCodeBlocks(state, block);
      const nestedLines = new Set<number>();
      for (const nestedBlock of nested) {
        codeSourceLines(state, nestedBlock, ranges);
        const first = state.doc.lineAt(nestedBlock.from).number, last = state.doc.lineAt(Math.max(nestedBlock.from, nestedBlock.to - 1)).number;
        for (let number = first; number <= last; number++) nestedLines.add(state.doc.line(number).from);
      }
      for (let pos = state.doc.lineAt(block.from).from; pos <= block.to;) {
        if (!nestedLines.has(pos)) ranges.push(Decoration.line({ class: `active-source-line${heading ? ` source-heading-${heading[1]}` : ''}` }).range(pos));
        const line = state.doc.lineAt(pos); if (line.to >= state.doc.length) break; pos = line.to + 1;
      }
    } else if (block.from < block.to) {
      // Leave code separators to the source-line geometry used while editing.
      const replacementEnd = previewReplacementEnd(state, block, blocks[index + 1]?.from);
      ranges.push(Decoration.replace({ widget: new PreviewWidget(block, options.settings, options.generation, session.sessionID, active, context), block: true, inclusive: false }).range(previewReplacementFrom(state, block), replacementEnd));
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
function updateEditedDecorations(previous: { blocks: Block[]; decorations: DecorationSet; context: RenderContext }, tr: Transaction, blocks: Block[], context: RenderContext): DecorationSet {
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
  if (context !== previous.context) {
    blocks.forEach((block,index) => { if (block.kind === 'Table' || needsDocumentContext(block.source,context)) dirtyNew.add(index); });
    old.forEach((block,index) => { if (block.kind === 'Table' || needsDocumentContext(block.source,previous.context)) dirtyOld.add(index); });
  }
  const oldSpans = mergeSpans([...dirtyOld].map(index => ({ from: tr.startState.doc.lineAt(old[index].from).from, to: old[index + 1]?.from ?? tr.startState.doc.length + 1 })));
  const oldLines: Span[] = [], newLines: Span[] = [];
  tr.changes.iterChangedRanges((fromA, toA, fromB, toB) => {
    oldLines.push({ from: tr.startState.doc.lineAt(fromA).from, to: tr.startState.doc.lineAt(toA).to + 1 });
    newLines.push({ from: tr.state.doc.lineAt(fromB).from, to: tr.state.doc.lineAt(toB).to + 1 });
  });
  const oldLineSpans = mergeSpans(oldLines), additions: Range<Decoration>[] = [];
  for (const index of [...dirtyNew].sort((a, b) => a - b)) decorateBlock(tr.state, blocks, index, additions, context);
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

function codeFenceAtomicRanges(state: EditorState, tree: Tree): DecorationSet {
  const ranges: Range<Decoration>[] = [];
  tree.iterate({ enter(node) {
    if (node.name !== 'FencedCode') return;
    for (const mark of node.node.getChildren('CodeMark')) {
      const line = state.doc.lineAt(mark.from);
      ranges.push(Decoration.mark({}).range(line.from, line.to));
    }
    return false;
  } });
  return Decoration.set(ranges, true);
}

function fencedCodeAt(state: EditorState, position: number) {
  const bounded = Math.max(0, Math.min(state.doc.length, position));
  for (const at of [bounded, Math.max(0, bounded - 1), Math.min(state.doc.length, bounded + 1)]) {
    let node: SyntaxNode | null = state.field(livePreview).tree.resolveInner(at, 1);
    while (node) {
      if (node.name === 'FencedCode') return node;
      node = node.parent;
    }
  }
}

function hiddenFenceCursorTarget(state: EditorState, position: number, direction: number) {
  if (state.field(previewOptions).sourceMode) return position;
  const node = fencedCodeAt(state, position);
  if (!node) return position;
  const marks = node.getChildren('CodeMark');
  const opening = marks[0] && state.doc.lineAt(marks[0].from);
  const closing = marks.length > 1 ? state.doc.lineAt(marks.at(-1)!.from) : undefined;
  if (!opening) return position;
  for (const mark of marks) {
    const line = state.doc.lineAt(mark.from);
    if (position < line.from || position > line.to) continue;
    const backward = direction < 0;
    if (closing && closing.number === opening.number + 1) {
      return backward ? (opening.from > 0 ? opening.from - 1 : Math.min(state.doc.length, closing.to + 1))
        : (closing.to < state.doc.length ? closing.to + 1 : Math.max(0, opening.from - 1));
    }
    if (line.number === opening.number) return backward ? (line.from > 0 ? line.from - 1 : Math.min(state.doc.length, line.to + 1))
      : Math.min(state.doc.length, line.to + 1);
    return backward ? Math.max(0, line.from - 1) : (line.to < state.doc.length ? line.to + 1 : Math.max(0, line.from - 1));
  }
  return position;
}

function fenceBoundaryExit(state: EditorState, position: number, key: string) {
  const node = fencedCodeAt(state, position);
  if (!node) return position;
  const marks = node.getChildren('CodeMark');
  const opening = marks[0] && state.doc.lineAt(marks[0].from);
  const closing = marks.length > 1 ? state.doc.lineAt(marks.at(-1)!.from) : undefined;
  if (!opening || !closing) return position;
  if (key === 'ArrowUp' && position === opening.to + 1) return opening.from > 0 ? opening.from - 1 : position;
  if (key === 'ArrowDown' && position === closing.from - 1) return closing.to < state.doc.length ? closing.to + 1 : position;
  return position;
}

export const livePreview = StateField.define<{ blocks: Block[]; decorations: DecorationSet; atomics: DecorationSet; fragments: readonly TreeFragment[]; tree: Tree; context: RenderContext }>({
  create(state) {
    const source = state.doc.toString(), tree = markdownParser.parse(source), blocks = blocksFor(source, tree);
    const context = documentRenderContext(source); return { blocks, decorations: decorations(state, blocks, context), atomics: codeFenceAtomicRanges(state, tree), fragments: TreeFragment.addTree(tree), tree, context };
  },
  update(value, tr) {
    const options = tr.state.field(previewOptions);
    let fragments = value.fragments;
    if (tr.docChanged) {
      const changes: {fromA:number; toA:number; fromB:number; toB:number}[] = [];
      tr.changes.iterChangedRanges((fromA, toA, fromB, toB) => changes.push({fromA, toA, fromB, toB}));
      fragments = TreeFragment.applyChanges(fragments, changes);
    }
    if (options.composing) return { blocks: value.blocks, decorations: value.decorations.map(tr.changes), atomics: value.atomics.map(tr.changes), fragments, tree: value.tree, context: value.context };
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
      for (const index of indices) decorateBlock(tr.state, value.blocks, index, ranges, value.context);
      return { ...value, decorations: value.decorations.update({
        filterFrom: spans[0].from, filterTo: spans.at(-1)!.to,
        filter: (from, _to, decoration) => decoration === spacerDecoration || !spans.some(span => from >= span.from && from < span.to),
        add: ranges, sort: true,
      }) };
    }
    const previouslyComposing = tr.startState.field(previewOptions).composing;
    let blocks = value.blocks, tree = value.tree, context = value.context, atomics = value.atomics;
    if (tr.docChanged || previouslyComposing) {
      const source = tr.state.doc.toString(); tree = markdownParser.parse(source, fragments);
      blocks = blocksFor(source, tree); fragments = TreeFragment.addTree(tree); context = documentRenderContext(source); atomics = codeFenceAtomicRanges(tr.state, tree);
    }
    const nextDecorations = tr.docChanged && !previouslyComposing && !previewChanged && !options.sourceMode
      ? updateEditedDecorations(value, tr, blocks, context) : decorations(tr.state, blocks, context);
    return { blocks, decorations: nextDecorations, atomics, fragments, tree, context };
  },
  provide: field => [
    EditorView.decorations.from(field, value => value.decorations),
    EditorView.atomicRanges.of(view => view.state.field(previewOptions).sourceMode ? Decoration.none : view.state.field(field).atomics),
    EditorView.domEventHandlers({ keydown(event, view) {
      const options = view.state.field(previewOptions);
      if (options.sourceMode || options.composing || view.composing || event.isComposing || event.shiftKey || event.metaKey || event.ctrlKey || event.altKey
        || (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') || !view.state.selection.main.empty) return false;
      const target = fenceBoundaryExit(view.state, view.state.selection.main.head, event.key);
      if (target === view.state.selection.main.head) return false;
      event.preventDefault();
      view.dispatch({ selection: EditorSelection.cursor(target) });
      return true;
    } }),
    EditorView.updateListener.of(update => {
      const selection = update.state.selection.main;
      if (update.state.field(previewOptions).composing || update.view.composing || !update.selectionSet || !selection.empty) return;
      const target = hiddenFenceCursorTarget(update.state, selection.head, Math.sign(selection.head - update.startState.selection.main.head));
      if (target !== selection.head) update.view.dispatch({ selection: EditorSelection.cursor(target) });
    }),
  ],
});
