import { outlineFor } from './markdown';

/**
 * Portable Markdown reading helpers. They deliberately return plain data so a
 * read-only host (including Android) can use the same document semantics
 * without importing CodeMirror or touching the DOM.
 */
export interface FrontMatter { raw: string; bodyFrom: number; entries: ReadonlyArray<{ key: string; value: string }> }

export function frontMatterFor(source: string): FrontMatter | undefined {
  if (!source.startsWith('---')) return undefined;
  const firstEnd = source.indexOf('\n');
  if (firstEnd < 0 || source.slice(0, firstEnd).trim() !== '---') return undefined;
  const closing = /^---\s*$/m.exec(source.slice(firstEnd + 1));
  if (!closing || closing.index === undefined) return undefined;
  const end = firstEnd + 1 + closing.index + closing[0].length;
  const raw = source.slice(0, end);
  const entries = raw.split(/\r?\n/).slice(1, -1).flatMap(line => {
    const match = /^([A-Za-z][\w-]*):\s*(.*)$/.exec(line);
    return match ? [{ key: match[1], value: match[2] }] : [];
  });
  return { raw, bodyFrom: end + (source[end] === '\n' ? 1 : 0), entries };
}

export function headingSlug(title: string) {
  return title.toLowerCase().trim().replace(/[^\p{L}\p{N}\s-]/gu, '').replace(/\s+/g, '-').replace(/-+/g, '-');
}

export function tableOfContentsMarkdown(source: string) {
  const frontMatter = frontMatterFor(source);
  const headings = outlineFor(source).filter(heading => heading.title && heading.level > 0 && (!frontMatter || heading.from >= frontMatter.bodyFrom));
  if (!headings.length) return '> 목차를 만들 제목이 없습니다.\n';
  const used = new Map<string, number>();
  return headings.map(heading => {
    const base = headingSlug(heading.title) || 'section', count = used.get(base) ?? 0;
    used.set(base, count + 1);
    const slug = count ? `${base}-${count + 1}` : base;
    const title = heading.title.replace(/([\\\[\]])/g, '\\$1');
    return `${'  '.repeat(Math.max(0, heading.level - 1))}- [${title}](#${slug})`;
  }).join('\n') + '\n';
}

export function nextFootnoteLabel(source: string) {
  const used = new Set([...source.matchAll(/\[\^([^\]]+)\]/g)].map(match => match[1]));
  let number = 1;
  while (used.has(String(number))) number++;
  return String(number);
}
