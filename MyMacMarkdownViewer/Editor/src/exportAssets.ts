import katexCSS from 'katex/dist/katex.min.css?raw';

let mathStyles: Promise<string> | undefined;

async function embeddedMathStyles() {
  const { fontURLs } = await import('./exportFonts');
  const replacements = new Map<string, string>();
  const sources = [...katexCSS.matchAll(/src:([^;}]+)/g)];
  // WOFF2 is supported by all three minimum platform versions. Do not embed
  // duplicate WOFF/TTF copies or leave filesystem/bundle URLs in exported HTML.
  for (const match of sources) {
    const name = /url\(["']?fonts\/([^"')]+\.woff2)/.exec(match[1])?.[1];
    const url = name && Object.entries(fontURLs).find(([key]) => key.endsWith('/' + name))?.[1];
    if (!url?.startsWith('data:')) throw new Error('수식 글꼴을 찾을 수 없습니다. 다시 내보내 주세요.');
    replacements.set(match[0], `src:url("${url}") format("woff2")`);
  }
  return katexCSS.replace(/src:([^;}]+)/g, source => replacements.get(source)!);
}

const documentCSS = `
html{color-scheme:light}body{overflow-wrap:anywhere}
blockquote{border-left:3px solid #aaa;margin:1em 0;padding:.1em 1em}
pre{white-space:pre-wrap;overflow-wrap:anywhere}pre code{background:transparent}
table{width:100%;table-layout:auto;break-inside:auto}thead{display:table-header-group}
th,td{overflow-wrap:anywhere;vertical-align:top}tr,img,svg{break-inside:avoid}
.katex-display{overflow-x:auto;overflow-y:hidden}
.task-checkbox{display:inline-block!important;color:inherit;vertical-align:middle}
.footnotes{font-size:.9em;border-top:1px solid #bbb;margin-top:2em}
.front-matter{white-space:pre-wrap}a{color:#246799}
@page{size:A4;margin:15mm}
@media print{
 :root{color-scheme:light}body{max-width:none;margin:0;padding:0;background:white!important;color:#202124!important;font-size:11pt}
 h1,h2,h3,h4,h5,h6{break-after:avoid;color:#202124!important}
 pre,code,.front-matter{background:#f4f4f4!important;color:#202124!important}
 table{display:table;overflow:visible;font-size:.9em}
 img,svg{max-height:240mm}.katex-display{overflow:visible}
 a{color:inherit;text-decoration:underline}
}
`;

/** Styles for a portable, offline document, independent of the editor DOM. */
export async function exportStyles(includeMath = true) {
  if (!includeMath) return documentCSS;
  mathStyles ??= embeddedMathStyles().catch(error => { mathStyles = undefined; throw error; });
  return (await mathStyles) + '\n' + documentCSS;
}

/** Remove interactive editor affordances while preserving their information. */
export async function finishExportAssets(root: HTMLElement) {
  root.querySelectorAll<HTMLElement>('.task-checkbox').forEach(button => {
    const checked = button.getAttribute('aria-checked') === 'true';
    const indicator = document.createElement('span');
    indicator.className = 'task-checkbox';
    indicator.textContent = checked ? '☑' : '☐';
    indicator.setAttribute('aria-label', checked ? '완료' : '미완료');
    button.replaceWith(indicator);
  });
  // Whole-document Markdown rendering also needs display-only GFM tasks.
  root.querySelectorAll('li').forEach(item => {
    const first = item.firstChild?.nodeType === Node.TEXT_NODE ? item.firstChild : item.querySelector(':scope > p')?.firstChild;
    if (!first || first.nodeType !== Node.TEXT_NODE || !/^\[[ xX]\] /.test(first.textContent ?? '')) return;
    first.textContent = first.textContent!.replace(/^\[([ xX])\] /, (_, value) => value === ' ' ? '☐ ' : '☑ ');
  });
  root.querySelectorAll('[data-remote-images]').forEach(button => button.remove());
  root.querySelectorAll('img').forEach(image => { image.loading = 'eager'; image.decoding = 'sync'; });
  return exportStyles(!!root.querySelector('.katex'));
}
