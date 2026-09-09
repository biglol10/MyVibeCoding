import { EditorState, type Range } from '@codemirror/state';
import { Decoration, WidgetType, type EditorView } from '@codemirror/view';
import type { SyntaxNode } from '@lezer/common';
import type { Block } from './markdown';
import { renderInlineMath } from './render';

type Item = { from: number; to: number; depth: number; prefixTo: number; label: string; task?: number };
type Inline = { from: number; to: number; kind: string; marks: { from: number; to: number }[]; href?: string; labelTo?: number };
type Heading = { from: number; to: number; level: number; marks: { from: number; to: number }[] };
type Plan = { items: Item[]; inlines: Inline[]; headings: Heading[] };
const plans = new WeakMap<Block, Plan | null>();

function planFor(block: Block): Plan | null {
  if (plans.has(block)) return plans.get(block)!;
  if (!block.node || !/^(Paragraph|ATXHeading[1-6]|BulletList|OrderedList|Blockquote)$/.test(block.kind)) return null;
  const plan: Plan = { items: [], inlines: [], headings: [] };
  const ordinals = new Map<number, number>();
  let supported = true;
  function walk(node: SyntaxNode, depth = 0) {
    if (/^(Image|FencedCode|CodeBlock|Table|HTMLBlock|HorizontalRule|SetextHeading)/.test(node.name)) { supported = false; return; }
    // Complex quote/list combinations keep the existing block renderer.
    if (block.kind === 'Blockquote' && /^(BulletList|OrderedList|Blockquote)$/.test(node.name) && node !== block.node) { supported = false; return; }
    const heading = /^ATXHeading([1-6])$/.exec(node.name);
    if (heading) {
      const marks = node.getChildren('HeaderMark').map((mark, index) => {
        let from = mark.from, to = mark.to;
        // The parser, rather than a line-start regex, identifies headings inside containers.
        if (index === 0) to += /^[ \t]*/.exec(block.source.slice(to - block.from))![0].length;
        else while (from > node.from && /[ \t]/.test(block.source[from - block.from - 1])) from--;
        return { from, to };
      });
      plan.headings.push({ from: node.from, to: node.to, level: Number(heading[1]), marks });
    }
    if (node.name === 'ListItem') {
      const mark = node.getChild('ListMark');
      if (mark) {
        const rest = block.source.slice(mark.to - block.from);
        const whitespace = /^\s*/.exec(rest)![0].split('\n')[0].length;
        let prefixTo = mark.to + whitespace;
        const task = node.getChild('Task')?.getChild('TaskMarker');
        const raw = block.source.slice(mark.from - block.from, mark.to - block.from);
        let label = raw === '-' || raw === '+' || raw === '*' ? '•' : raw;
        if (node.parent?.name === 'OrderedList') {
          const first = node.parent.firstChild?.getChild('ListMark');
          const ordinal = ordinals.get(node.parent.from) ?? Number(first ? block.source.slice(first.from - block.from, first.to - block.from).replace(/[.)]/, '') : 1);
          label = String(ordinal) + '.';
          ordinals.set(node.parent.from, ordinal + 1);
        }
        if (task) prefixTo = task.to + (/^[ \t]+/.exec(block.source.slice(task.to - block.from))?.[0].length ?? 0);
        plan.items.push({ from: node.from, to: node.to, depth, prefixTo, label, task: task?.from });
      }
      depth++;
    }
    if (/^(StrongEmphasis|Emphasis|Strikethrough|InlineCode|Link)$/.test(node.name)) {
      const marks: Inline['marks'] = [];
      for (let child = node.firstChild; child; child = child.nextSibling) {
        if (/^(EmphasisMark|StrikethroughMark|CodeMark|LinkMark)$/.test(child.name)) marks.push({ from: child.from, to: child.to });
      }
      const url = node.getChild('URL');
      const labelTo = node.name === 'Link' ? marks.find(mark => block.source[mark.from - block.from] === ']')?.from : undefined;
      plan.inlines.push({ from: node.from, to: node.to, kind: node.name, marks, labelTo,
        href: url ? block.source.slice(url.from - block.from, url.to - block.from).replace(/^<|>$/g, '') : undefined });
    }
    for (let child = node.firstChild; child; child = child.nextSibling) walk(child, depth);
  }
  walk(block.node);
  plans.set(block, supported ? plan : null);
  return supported ? plan : null;
}

class PrefixWidget extends WidgetType {
  constructor(readonly label: string, readonly heading = false, readonly checked: boolean | null = null,
    readonly isComposing: (state: EditorState) => boolean = () => false) { super(); }
  eq(other: PrefixWidget) { return this.label === other.label && this.heading === other.heading && this.checked === other.checked; }
  toDOM(view: EditorView) {
    const span = document.createElement('span'); span.className = 'md-prefix md-prefix-preview';
    if (this.checked !== null) {
      const button = document.createElement('button'); button.className = 'task-checkbox'; button.type = 'button';
      button.setAttribute('role', 'checkbox'); button.setAttribute('aria-checked', String(this.checked));
      button.setAttribute('aria-label', '할 일 완료 상태 변경'); button.dataset.task = '';
      button.textContent = this.checked ? '✓' : '';
      button.addEventListener('mousedown', event => { event.preventDefault(); event.stopPropagation(); });
      button.addEventListener('click', event => {
        event.preventDefault(); event.stopPropagation();
        if (view.state.readOnly || view.composing || this.isComposing(view.state)) return;
        const from = view.posAtDOM(span), line = view.state.doc.lineAt(from);
        const match = /\[([ xX])\]/.exec(line.text);
        if (match) toggleTaskAt(view, button, line.from + match.index + 1, this.checked ? ' ' : 'x');
      });
      span.append(button);
    } else { span.textContent = this.heading ? '' : this.label; span.setAttribute('aria-hidden', 'true'); }
    return span;
  }
  ignoreEvent() { return this.checked !== null; }
}

export function toggleTaskAt(view: EditorView, button: Element, from: number, insert: string) {
  const restoreFocus = document.activeElement === button;
  const index = [...view.dom.querySelectorAll('.task-checkbox')].indexOf(button);
  view.dispatch({ changes: { from, to: from + 1, insert }, userEvent: 'input' });
  if (restoreFocus) queueMicrotask(() => view.dom.querySelectorAll<HTMLButtonElement>('.task-checkbox')[index]?.focus());
}

class MathWidget extends WidgetType {
  constructor(readonly source: string) { super(); }
  eq(other: MathWidget) { return this.source === other.source; }
  toDOM() { return renderInlineMath(this.source); }
  ignoreEvent() { return false; }
}

function touches(state: EditorState, from: number, to: number) {
  return state.selection.ranges.some(range => range.empty ? range.head >= from && range.head <= to : range.from < to && range.to > from);
}

// Keep prose in CodeMirror's actual editable lines. Only syntax markers are
// decorated, so selecting a list item never replaces its siblings or their DOM.
export function decorateTextBlock(state: EditorState, block: Block, ranges: Range<Decoration>[], isComposing: (state: EditorState) => boolean): boolean {
  const plan = planFor(block);
  if (!plan) return false;
  const heading = /^ATXHeading([1-6])$/.exec(block.kind);
  const activeItems = new Set<Item>();
  for (const selection of state.selection.ranges) {
    if (selection.empty) {
      const item = plan.items.filter(item => selection.head >= item.from && selection.head <= item.to).sort((a,b) => b.depth - a.depth)[0];
      if (item) activeItems.add(item);
    } else for (const item of plan.items) if (selection.from < item.to && selection.to > item.from) activeItems.add(item);
  }
  let itemIndex = 0;
  let headingIndex = 0;
  const itemStack: Item[] = [];
  for (let number = state.doc.lineAt(block.from).number, last = state.doc.lineAt(block.to).number; number <= last; number++) {
    const line = state.doc.line(number);
    while (headingIndex < plan.headings.length && plan.headings[headingIndex].to < line.from) headingIndex++;
    const candidate = plan.headings[headingIndex];
    const lineHeading = candidate && candidate.from <= line.to && candidate.to >= line.from ? candidate : undefined;
    while (itemStack.length && itemStack.at(-1)!.to < line.from) itemStack.pop();
    while (itemIndex < plan.items.length && plan.items[itemIndex].from <= line.to) {
      const next = plan.items[itemIndex++];
      while (itemStack.length && itemStack.at(-1)!.to < next.from) itemStack.pop();
      itemStack.push(next);
    }
    const item = itemStack.at(-1);
    let kind = 'md-prose', prefixTo = line.from, label = '', active = false, task: number | undefined;
    let style = '';
    if (heading) {
      kind += ` md-heading md-h${heading[1]}`;
      if (line.from === block.from) prefixTo = lineHeading?.marks[0]?.to ?? line.from;
      active = touches(state, block.from, block.to);
    } else if (item) {
      const first = item.from >= line.from && item.from <= line.to;
      kind += first ? ' md-list-line' : ' md-list-continuation';
      prefixTo = first ? item.prefixTo : line.from + (/^[ \t]*/.exec(line.text)?.[0].length ?? 0);
      label = first ? item.label : ''; active = activeItems.has(item); task = first ? item.task : undefined;
      style = `--list-depth:${item.depth};`;
      if (active) kind += ' md-editing-item';
    } else if (block.kind === 'Blockquote') {
      kind += ' md-quote-line';
      prefixTo = line.from + (/^[ \t]*>[ \t]?/.exec(line.text)?.[0].length ?? 0);
      active = touches(state, line.from, line.to);
    }
    if (lineHeading && !heading) kind += ` md-nested-heading md-h${lineHeading.level}`;
    const attributes: Record<string, string> = { style };
    if (lineHeading) { attributes.role = 'heading'; attributes['aria-level'] = String(lineHeading.level); }
    ranges.push(Decoration.line({ class: kind, attributes }).range(line.from));
    if (prefixTo > line.from) {
      if (kind.includes('md-list-continuation')) ranges.push(Decoration.replace({}).range(line.from, prefixTo));
      else if (active) ranges.push(Decoration.mark({ class: 'md-prefix md-prefix-source' }).range(line.from, prefixTo));
      else {
        const checked = task == null ? null : /[xX]/.test(state.sliceDoc(task, task + 3));
        ranges.push(Decoration.replace({ widget: new PrefixWidget(label, !!heading || block.kind === 'Blockquote', checked, isComposing) }).range(line.from, prefixTo));
      }
    }
  }
  for (const nested of plan.headings) {
    const active = touches(state, nested.from, nested.to);
    // Top-level opening markers are already covered by the fixed heading gutter.
    for (const mark of nested.marks.slice(heading ? 1 : 0)) {
      if (mark.from < mark.to) ranges.push((active ? Decoration.mark({ class: 'md-syntax' }) : Decoration.replace({})).range(mark.from, mark.to));
    }
  }
  for (const inline of plan.inlines) {
    const active = touches(state, inline.from, inline.to);
    const classes: Record<string,string> = { StrongEmphasis: 'md-strong', Emphasis: 'md-emphasis', Strikethrough: 'md-strike', InlineCode: 'md-code', Link: 'md-link' };
    if (inline.kind === 'Link' && inline.labelTo != null && inline.href) {
      ranges.push(Decoration.mark({ class: 'md-link', attributes: { 'data-href': inline.href, title: '⌘클릭하여 링크 열기' } }).range(inline.from + 1, inline.labelTo));
      if (!active) {
        ranges.push(Decoration.replace({}).range(inline.from, inline.from + 1));
        ranges.push(Decoration.replace({}).range(inline.labelTo, inline.to));
        continue;
      }
    } else ranges.push(Decoration.mark({ class: classes[inline.kind] }).range(inline.from, inline.to));
    for (const mark of inline.marks) ranges.push((active ? Decoration.mark({ class: 'md-syntax' }) : Decoration.replace({})).range(mark.from, mark.to));
  }
  // Inline math keeps its own rendering boundary without replacing a paragraph.
  const math = /(?<![\\$])\$(?![\s$])(?:\\.|[^$\\\n])*(?<!\s)\$(?!\d)/g;
  for (const match of block.source.matchAll(math)) {
    const from = block.from + match.index!, to = from + match[0].length;
    if (plan.inlines.some(inline => ['InlineCode', 'Link'].includes(inline.kind) && inline.from < to && inline.to > from) || touches(state, from, to)) continue;
    ranges.push(Decoration.replace({ widget: new MathWidget(match[0]) }).range(from, to));
  }
  return true;
}
