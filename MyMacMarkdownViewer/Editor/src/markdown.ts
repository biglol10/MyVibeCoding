import { parser, GFM } from '@lezer/markdown';
import type { Tree, SyntaxNode } from '@lezer/common';
import type { Heading } from './protocol';

export const markdownParser = parser.configure(GFM);
export interface Block { from: number; to: number; kind: string; source: string; node?: SyntaxNode }

export function blocksFor(text: string, tree: Tree = markdownParser.parse(text)): Block[] {
  const blocks: Block[] = [];
  let node = tree.topNode.firstChild;
  while (node) {
    blocks.push({ from: node.from, to: node.to, kind: node.name, source: text.slice(node.from, node.to), node });
    node = node.nextSibling;
  }
  // YAML-style front matter is document metadata, not a horizontal rule plus
  // prose. Keep it as one non-editing preview block while preserving source.
  if (text.startsWith('---\n')) {
    const closing = /^---\s*$/m.exec(text.slice(4));
    if (closing?.index !== undefined) {
      const end = 4 + closing.index + closing[0].length;
      const bodyFrom = end + (text[end] === '\n' ? 1 : 0);
      const retained = blocks.filter(block => block.from >= bodyFrom);
      retained.unshift({ from: 0, to: end, kind: 'FrontMatter', source: text.slice(0, end) });
      blocks.splice(0, blocks.length, ...retained);
    }
  }
  // A footnote's indented continuation belongs to its definition, even when
  // Lezer represents it as a separate code block after a blank source line.
  for (let i = 0; i < blocks.length; i++) {
    if (!/^ {0,3}\[\^[^\] \n]+\]:/.test(blocks[i].source)) continue;
    while (blocks[i + 1]?.kind === 'CodeBlock'
      && /^\s*$/.test(text.slice(blocks[i].to, blocks[i + 1].from))) {
      const from = blocks[i].from, to = blocks[i + 1].to;
      blocks.splice(i, 2, { from, to, kind: 'FootnoteDefinition', source: text.slice(from, to) });
    }
  }
  // The CommonMark parser sees multiline display math as adjacent paragraphs. Merge only complete $$ pairs.
  for (let i = 0; i < blocks.length; i++) {
    if (!/^\$\$(?:\s|$)/.test(blocks[i].source)) continue;
    const from = blocks[i].from;
    const end = text.indexOf('$$', from + 2);
    if (end < 0) continue;
    let j = i;
    while (j + 1 < blocks.length && blocks[j].to < end + 2) j++;
    if (blocks[j].to < end + 2) continue;
    blocks.splice(i, j - i + 1, { from, to: blocks[j].to, kind: 'DisplayMath', source: text.slice(from, blocks[j].to) });
  }
  return blocks;
}

export function outlineFor(text: string, tree: Tree = markdownParser.parse(text)): Heading[] {
  const headings: Heading[] = [];
  tree.iterate({ enter(node) {
    const match = /^(?:ATX|Setext)Heading([1-6])$/.exec(node.name);
    if (!match) return;
    const source = text.slice(node.from, node.to);
    headings.push({ from: node.from, level: Number(match[1]),
      title: source.replace(/^#{1,6}\s*/, '').replace(/\n[=-]+\s*$/, '').replace(/\s+#+\s*$/, '').replace(/[*_`]/g, '').trim() });
  }});
  if (text.startsWith('---\n')) {
    const closing = /^---\s*$/m.exec(text.slice(4));
    if (closing?.index !== undefined) {
      const end = 4 + closing.index + closing[0].length;
      return headings.filter(heading => heading.from > end);
    }
  }
  return headings;
}

export interface Relocation { source: string; destination: string; directory: boolean }

export function relativeDestination(destination: string, oldBase: string, newBase: string, relocation?: Relocation): string {
  if (!destination || /^(?:[a-z][\w+.-]*:|\/|#)/i.test(destination)) return destination;
  try {
    const target = new URL(destination, oldBase);
    const newURL = new URL(newBase);
    if (target.protocol !== 'file:' || newURL.protocol !== 'file:') return destination;
    // Windows volumes and UNC shares cannot be expressed by walking up with ../.
    const volume = (url: URL) => url.host ? `${url.host.toLowerCase()}/${url.pathname.split('/')[1]?.toLowerCase()}` : /^\/[a-z]:\//i.test(url.pathname) ? url.pathname.slice(1, 3).toLowerCase() : '';
    if (volume(target) !== volume(newURL)) return target.href;
    if (relocation) {
      const source = new URL(relocation.source).pathname.replace(/\/$/, '');
      const moved = new URL(relocation.destination).pathname.replace(/\/$/, '');
      if (target.pathname === source || (relocation.directory && target.pathname.startsWith(source + '/'))) {
        target.pathname = moved + target.pathname.slice(source.length);
      }
      // Moving a whole folder keeps its internal relative references byte-identical.
      if (new URL(destination, newBase).href === target.href) return destination;
    }
    const targetParts = target.pathname.split('/').filter(Boolean);
    const baseParts = newURL.pathname.split('/').filter(Boolean);
    while (targetParts.length && baseParts.length && targetParts[0] === baseParts[0]) { targetParts.shift(); baseParts.shift(); }
    return [...baseParts.map(() => '..'), ...targetParts].join('/') + target.search + target.hash;
  } catch { return destination; }
}

export function rebaseMarkdown(text: string, oldBase: string, newBase: string, relocation?: Relocation): string {
  if (!oldBase || (oldBase === newBase && !relocation)) return text;
  const edits: { from: number; to: number; insert: string }[] = [];
  markdownParser.parse(text).iterate({ enter(node) {
    if (node.name !== 'URL') return;
    const raw = text.slice(node.from, node.to);
    const angle = raw.startsWith('<') && raw.endsWith('>');
    const value = angle ? raw.slice(1, -1) : raw;
    const next = relativeDestination(value, oldBase, newBase, relocation);
    if (next !== value) edits.push({ from: node.from, to: node.to, insert: angle ? `<${next}>` : next });
  }});
  for (const edit of edits.reverse()) text = text.slice(0, edit.from) + edit.insert + text.slice(edit.to);
  return text;
}
