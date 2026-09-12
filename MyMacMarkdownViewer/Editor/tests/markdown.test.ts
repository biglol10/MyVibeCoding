import { describe, it, expect } from 'vitest';
import { blocksFor, outlineFor, rebaseMarkdown } from '../src/markdown';
import { frontMatterFor, nextFootnoteLabel, tableOfContentsMarkdown } from '../src/semantic';
import { parseTable, serializeTable, withTableAlignment, withTableColumn, withTableRow } from '../src/table';

describe('source-preserving Markdown parsing', () => {
  it('does not treat code fence contents as headings', () => {
    const source = '# 진짜 제목\n\n```md\n# 코드 안 제목\n```\n\n## 진짜 제목\n';
    expect(outlineFor(source).map(h => h.title)).toEqual(['진짜 제목', '진짜 제목']);
    expect(outlineFor(source)[1].from).toBe(source.indexOf('## 진짜'));
  });
  it('keeps complete multi-paragraph display math in one block', () => {
    const source = '# Math\n\n$$\nx = 1\n\ny = 2\n$$\n\n끝';
    const math = blocksFor(source).find(b => b.kind === 'DisplayMath');
    expect(math?.source).toBe('$$\nx = 1\n\ny = 2\n$$');
  });
  it('rebases Markdown destinations but preserves code, external links, anchors and Korean', () => {
    const source = '[문서](notes/a.md#제목)\n\n![이미지](assets/a.png)\n\n[web](https://example.com)\n\n[here](#제목)\n\n```md\n[keep](assets/a.png)\n```\n';
    expect(rebaseMarkdown(source, 'file:///Users/me/old/', 'file:///Users/me/new/')).toBe(source.replace('notes/a.md#제목', '../old/notes/a.md#%EC%A0%9C%EB%AA%A9').replace('![이미지](assets/a.png)', '![이미지](../old/assets/a.png)'));
  });
  it('rebases reference-style image destinations with spaces while keeping titles', () => {
    const source = '![그림][image]\n\n[image]: <assets/한 글.png> "원래 제목"\n';
    expect(rebaseMarkdown(source, 'file:///notes/old/', 'file:///notes/new/')).toBe('![그림][image]\n\n[image]: <../old/assets/%ED%95%9C%20%EA%B8%80.png> "원래 제목"\n');
  });
  it('keeps internal folder links unchanged while rebasing links outside the moved folder', () => {
    const source = '![그림](assets/한글.png)\n\n[밖](../other.md#here)\n\n[안](child/a.md)';
    expect(rebaseMarkdown(source, 'file:///notes/old/', 'file:///notes/deep/new/', {
      source: 'file:///notes/old', destination: 'file:///notes/deep/new', directory: true,
    })).toBe(source.replace('../other.md#here', '../../other.md#here'));
  });
  it('updates self references on rename but never changes another document or literal code', () => {
    const source = '[self](a.md#one) [other](b.md) `a.md`\n\n```md\n[self](a.md)\n```';
    expect(rebaseMarkdown(source, 'file:///notes/', 'file:///notes/', {
      source: 'file:///notes/a.md', destination: 'file:///notes/new.md', directory: false,
    })).toBe(source.replace('(a.md#one)', '(new.md#one)'));
  });
});

it('uses absolute file URLs across Windows drives and UNC shares', () => {
  expect(rebaseMarkdown('![그림](assets/a.png)', 'file:///C:/docs/', 'file:///D:/notes/')).toBe('![그림](file:///C:/docs/assets/a.png)');
  expect(rebaseMarkdown('[문서](a.md)', 'file://server/share/docs/', 'file://other/share/notes/')).toBe('[문서](file://server/share/docs/a.md)');
  expect(rebaseMarkdown('[문서](a.md)', 'file:///C:/docs/', 'file:///C:/docs/sub/')).toBe('[문서](../a.md)');
});

describe('document semantics', () => {
  it('recognizes only an opening front matter fence and makes a safe unique TOC', () => {
    const source = '---\ntitle: [안전]\n---\n\n# 같은 제목\n\n# 같은 제목\n';
    expect(frontMatterFor(source)?.entries).toEqual([{ key: 'title', value: '[안전]' }]);
    expect(tableOfContentsMarkdown(source)).toContain('[같은 제목](#같은-제목)');
    expect(tableOfContentsMarkdown(source)).toContain('[같은 제목](#같은-제목-2)');
  });
  it('does not expose a front matter hash as a document outline heading', () => {
    const source = '---\ntitle: "# metadata"\n---\n\n# 본문\n';
    expect(outlineFor(source).map(heading => heading.title)).toEqual(['본문']);
  });
  it('does not reuse a referenced but not yet defined footnote label', () => {
    expect(nextFootnoteLabel('본문[^1]\n\n[^2]: 정의')).toBe('3');
  });
});

describe('table source operations', () => {
  const source = '| 이름 | 값 |\n| :--- | ---: |\n| 한글 | 123 |';
  it('keeps direct cell ranges and serializes structural changes', () => {
    const table = parseTable(source, 10)!;
    expect(table.cells[2][0]).toMatchObject({ from: source.indexOf('한글') + 10, text: '한글' });
    const expanded = withTableColumn(withTableRow(table, 'add', 2), 'add', 0);
    expect(serializeTable(expanded)).toContain('| 이름 |  | 값 |');
    expect(serializeTable(withTableAlignment(table, 1, 'center'))).toContain('| :--- | :---: |');
  });
});
