import { StateEffect, StateField, EditorSelection, type EditorState, type Range, type Transaction } from '@codemirror/state';
import { EditorView, Decoration, WidgetType, type DecorationSet } from '@codemirror/view';
import { TreeFragment, type Tree } from '@lezer/common';
import { blocksFor, markdownParser, type Block } from './markdown';
import { documentRenderContext, needsDocumentContext, renderBlock, renderDiagram, type RenderContext } from './render';
import { defaultSettings, post, session, type Settings } from './protocol';
import { decorateTextBlock, toggleTaskAt } from './textPreview';
import { escapeCellPipes, parseTable, serializeTable, withTableAlignment, withTableColumn, withTableRow } from './table';

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

function isMermaidBlock(block: Block) { return /^\s*(`{3,}|~{3,})mermaid(?:\s|$)/i.test(block.source); }
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

function codeSourceLines(state: EditorState, block: Block, ranges: Range<Decoration>[], extraClass = '') {
  const fenced = block.kind === 'FencedCode';
  const fenceLines = new Set(block.node?.getChildren('CodeMark').map(mark => state.doc.lineAt(mark.from).number) ?? []);
  const first = state.doc.lineAt(block.from).number, last = state.doc.lineAt(Math.max(block.from, block.to - 1)).number;
  for (let number = first; number <= last; number++) {
    const line = state.doc.line(number);
    const fence = fenced && fenceLines.has(number);
    // A keyboard cursor can intentionally reach a fence. Keep that one line
    // visible so it can be edited, while live clicks always target code text.
    const selectedFence = fence && state.selection.ranges.some(range => range.from >= line.from && range.from <= line.to);
    const edge = number === first ? ' code-source-first' : number === last ? ' code-source-last' : '';
    ranges.push(Decoration.line({ class: `code-source-line${edge}${fence && !selectedFence ? ' code-fence-line' : ''}${selectedFence ? ' code-fence-caret-line' : ''}${extraClass}` }).range(line.from));
  }
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
    const dom = isMermaid ? document.createElement('div') : renderBlock(this.block.source, this.settings, this.context, this.block.from);
    dom.classList.add('preview-widget'); if (this.active) dom.classList.add('focus-active'); dom.dataset.kind = this.block.kind;
    dom.setAttribute('aria-label', '클릭하여 이 블록 편집');
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
      const selectionTarget = Math.min(view.state.doc.length, from + offset);
      const current = currentBlockForDOM(view, dom, this.block.from);
      const bounds = codeContentBounds(view.state, current ?? this.block);
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
      const replacementEnd = blocks[index + 1] ? Math.max(block.to, end - 1) : block.to;
      ranges.push(Decoration.replace({ widget: new PreviewWidget(block, options.settings, options.generation, session.sessionID, false, context), block: true, inclusive: false }).range(block.from, replacementEnd));
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
      const replacementEnd = blocks[index + 1] ? Math.max(block.to, end - 1) : block.to;
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
      // Keep one source line break between widgets so CodeMirror can virtualize separate block lines.
      const replacementEnd = blocks[index + 1] ? Math.max(block.to, end - 1) : block.to;
      ranges.push(Decoration.replace({ widget: new PreviewWidget(block, options.settings, options.generation, session.sessionID, active, context), block: true, inclusive: false }).range(block.from, replacementEnd));
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

export const livePreview = StateField.define<{ blocks: Block[]; decorations: DecorationSet; fragments: readonly TreeFragment[]; tree: Tree; context: RenderContext }>({
  create(state) {
    const source = state.doc.toString(), tree = markdownParser.parse(source), blocks = blocksFor(source, tree);
    const context = documentRenderContext(source); return { blocks, decorations: decorations(state, blocks, context), fragments: TreeFragment.addTree(tree), tree, context };
  },
  update(value, tr) {
    const options = tr.state.field(previewOptions);
    let fragments = value.fragments;
    if (tr.docChanged) {
      const changes: {fromA:number; toA:number; fromB:number; toB:number}[] = [];
      tr.changes.iterChangedRanges((fromA, toA, fromB, toB) => changes.push({fromA, toA, fromB, toB}));
      fragments = TreeFragment.applyChanges(fragments, changes);
    }
    if (options.composing) return { blocks: value.blocks, decorations: value.decorations.map(tr.changes), fragments, tree: value.tree, context: value.context };
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
    let blocks = value.blocks, tree = value.tree, context = value.context;
    if (tr.docChanged || previouslyComposing) {
      const source = tr.state.doc.toString(); tree = markdownParser.parse(source, fragments);
      blocks = blocksFor(source, tree); fragments = TreeFragment.addTree(tree); context = documentRenderContext(source);
    }
    const nextDecorations = tr.docChanged && !previouslyComposing && !previewChanged && !options.sourceMode
      ? updateEditedDecorations(value, tr, blocks, context) : decorations(tr.state, blocks, context);
    return { blocks, decorations: nextDecorations, fragments, tree, context };
  },
  provide: field => EditorView.decorations.from(field, value => value.decorations),
});
