import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import katex from 'katex';
import hljs from 'highlight.js/lib/core';
import javascript from 'highlight.js/lib/languages/javascript';
import typescript from 'highlight.js/lib/languages/typescript';
import swift from 'highlight.js/lib/languages/swift';
import python from 'highlight.js/lib/languages/python';
import json from 'highlight.js/lib/languages/json';
import bash from 'highlight.js/lib/languages/bash';
import css from 'highlight.js/lib/languages/css';
import xml from 'highlight.js/lib/languages/xml';
import sql from 'highlight.js/lib/languages/sql';
import yaml from 'highlight.js/lib/languages/yaml';
import { session } from './protocol';
import type { Settings } from './protocol';
import { blocksFor, markdownParser, outlineFor } from './markdown';
import { frontMatterFor, headingSlug, tableOfContentsMarkdown } from './semantic';
import { finishExportAssets } from './exportAssets';

export interface RenderContext { env: Record<string, unknown>; source: string; footnotesHTML?: string; footnoteRefs: Map<number, { number: number; occurrence: number }>; jumps: Map<string, number>; definitions: number[] }

for (const [name, grammar] of Object.entries({ javascript, typescript, swift, python, json, bash, css, xml, sql, yaml })) hljs.registerLanguage(name, grammar);
const md = new MarkdownIt({ html: false, linkify: false, typographer: false, highlight(code, language) {
  if (hljs.getLanguage(language)) return hljs.highlight(code, { language, ignoreIllegals: true }).value;
  return '';
}});
md.use(footnote);

md.renderer.rules.list_item_open = (tokens, index, options, env, renderer) => {
  const token = tokens[index];
  const offset = (env as { taskOffsets?: Map<number, number> }).taskOffsets?.get(token.map?.[0] ?? -1);
  if (offset !== undefined) token.attrSet('data-task-offset', String(offset));
  return renderer.renderToken(tokens, index, options);
};

md.inline.ruler.after('escape', 'math_inline', (state, silent) => {
  const start = state.pos;
  if (state.src[start] !== '$' || state.src[start + 1] === '$' || /\s/.test(state.src[start + 1] ?? ' ')) return false;
  let end = start + 1;
  while ((end = state.src.indexOf('$', end)) !== -1 && state.src[end - 1] === '\\') end++;
  if (end < 0 || /\s/.test(state.src[end - 1]) || /\d/.test(state.src[end + 1] ?? '')) return false;
  if (!silent) { const token = state.push('math_inline', 'math', 0); token.content = state.src.slice(start + 1, end); }
  state.pos = end + 1;
  return true;
});
md.renderer.rules.math_inline = (tokens, idx) => katex.renderToString(tokens[idx].content, {
  trust: false, throwOnError: false, strict: 'ignore', maxSize: 20, maxExpand: 1000,
});

md.renderer.rules.image = (tokens, idx, _options, env) => {
  const token = tokens[idx], src = String(token.attrGet('src') ?? ''), alt = token.content;
  if (/^https?:/i.test(src) && !(env as { settings?: Settings } | undefined)?.settings?.remoteImages) {
    return `<span class="image-placeholder">외부 이미지 · ${md.utils.escapeHtml(alt || src)} <button type="button" data-remote-images>불러오기</button></span>`;
  }
  let url = '';
  if (/^https?:/i.test(src)) url = src;
  else if (!/^[a-z][\w+.-]*:/i.test(src)) url = `app://assets/${encodeURIComponent(session.sessionID)}/${encodeURIComponent(src)}`;
  if (!url) return `<span class="image-placeholder">지원하지 않는 이미지 경로 · ${md.utils.escapeHtml(alt)}</span>`;
  return `<img src="${md.utils.escapeHtml(url)}" alt="${md.utils.escapeHtml(alt)}" loading="lazy" decoding="async">`;
};

export function documentRenderContext(source: string): RenderContext {
  const env: Record<string, unknown> = {};
  const footnoteRefs: RenderContext['footnoteRefs'] = new Map();
  const jumps = new Map<string, number>(), definitions: number[] = [];
  if (!/\[\^|\[toc\]|^\s*\[[^\]]+\]:/im.test(source)) return {env, source, footnoteRefs, jumps, definitions};
  const metadata = frontMatterFor(source);
  // Blank metadata without changing source positions. It must not create
  // references or headings in the document body.
  const parsedSource = metadata ? source.slice(0, metadata.bodyFrom).replace(/[^\n]/g, ' ') + source.slice(metadata.bodyFrom) : source;
  const tokens = md.parse(parsedSource, env);
  const ignored: Array<{from:number;to:number}> = [];
  markdownParser.parse(source).iterate({enter(node) {
    if (['FencedCode', 'CodeBlock', 'InlineCode', 'Escape', 'URL', 'LinkTitle'].includes(node.name)) {
      ignored.push({from:node.from,to:node.to}); return false;
    }
  }});
  const literal = (at:number) => {
    if (at < (metadata?.bodyFrom ?? 0)) return true;
    let low=0, high=ignored.length;
    while(low<high) { const middle=(low+high)>>>1; if(ignored[middle].from<=at) low=middle+1; else high=middle; }
    return low>0 && at<ignored[low-1].to;
  };
  const refs = (env.footnotes as {refs?:Record<string,number>} | undefined)?.refs ?? {};
  const candidates = new Map<string, number[]>();
  for (const match of source.matchAll(/\[\^([^\] \n]+)\]/g)) {
    const at = match.index!, label = match[1];
    if (literal(at) || refs[':' + label] === undefined) continue;
    const start = source.lastIndexOf('\n', at - 1) + 1;
    if (/^ {0,3}$/.test(source.slice(start, at)) && source[at + match[0].length] === ':') {
      definitions.push(start);
      if (refs[':' + label] >= 0) jumps.set('fn' + (refs[':' + label] + 1), start);
      continue;
    }
    const positions = candidates.get(label) ?? [];
    positions.push(at); candidates.set(label, positions);
  }
  // IDs and occurrence numbers come from actual parsed references, never from
  // raw marker counts (examples in code are not footnote references).
  const visit = (items:typeof tokens) => items.forEach(token => {
    if (token.type === 'footnote_ref' && token.meta?.label) {
      const {id,subId,label} = token.meta;
      if (typeof id !== 'number' || typeof subId !== 'number' || typeof label !== 'string') return;
      const at = candidates.get(label)?.[subId];
      if (at !== undefined) {
        footnoteRefs.set(at,{number:id+1,occurrence:subId});
        jumps.set('fnref' + (id+1) + (subId ? ':'+subId : ''),at);
      }
    }
    if (token.children) visit(token.children);
  });
  visit(tokens);
  const footerToken = tokens.findIndex(token => token.type === 'footnote_block_open');
  const rendered = footerToken < 0 ? '' : md.renderer.render(tokens.slice(footerToken), md.options, env);
  const footerStart = rendered.indexOf('<section class="footnotes">');
  return {env,source,footnoteRefs,jumps,definitions,footnotesHTML:footerStart >= 0 ? rendered.slice(footerStart) : undefined};
}

export function needsDocumentContext(source:string, context:RenderContext) {
  return /\[\^|\[toc\]/i.test(source) || (!!context.env.references && source.includes('['));
}

export function renderBlock(source: string, settings: Settings, context?: RenderContext, blockFrom = 0): HTMLElement {
  const element = document.createElement('div');
  element.className = 'rendered-block';
  const definitionsHere = context?.definitions.filter(at => at >= blockFrom && at < blockFrom + source.length) ?? [];
  if (/^---\s*\n[\s\S]*\n---\s*$/.test(source)) {
    const details = document.createElement('details'); details.className = 'front-matter';
    const summary = document.createElement('summary'); summary.textContent = '문서 정보';
    const pre = document.createElement('pre'); pre.textContent = source;
    details.append(summary, pre); element.append(details); return element;
  }
  if (/^\[toc\]\s*$/i.test(source)) {
    element.classList.add('table-of-contents');
    element.innerHTML = `<nav aria-label="문서 목차">${md.render(tableOfContentsMarkdown(context?.source ?? source))}</nav>`;
    const headings = outlineFor(context?.source ?? source), used = new Map<string, number>(), positions = new Map<string, number>();
    for (const heading of headings) {
      const base = headingSlug(heading.title) || 'section', count = used.get(base) ?? 0;
      used.set(base, count + 1); positions.set(count ? `${base}-${count + 1}` : base, heading.from);
    }
    element.querySelectorAll('a[href^="#"]').forEach(anchor => {
      const slug = decodeURIComponent(anchor.getAttribute('href')!.slice(1));
      const from = positions.get(slug);
      if (from !== undefined) anchor.setAttribute('data-jump', String(from));
    });
    return element;
  }
  if (/^\$\$[\s\S]*\$\$\s*$/.test(source.trim())) {
    const math = source.trim().slice(2, -2);
    element.classList.add('math-block');
    try { katex.render(math, element, { displayMode: true, trust: false, throwOnError: true, strict: 'ignore', maxSize: 20, maxExpand: 1000 }); }
    catch (error) { showRenderError(element, source, String(error)); }
  } else {
    const taskOffsets = new Map<number, number>();
    markdownParser.parse(source).iterate({ enter(node) {
      if (node.name === 'TaskMarker') taskOffsets.set(source.slice(0, node.from).split('\n').length - 1, node.from + 1);
    }});
    const shared = context?.env && Object.keys(context.env).length ? JSON.parse(JSON.stringify(context.env)) as Record<string, unknown> : {};
    let html = md.render(source, { ...shared, settings, taskOffsets });
    {
      const footerAt = [html.indexOf('<hr class="footnotes-sep">'), html.indexOf('<section class="footnotes">')].filter(offset => offset >= 0).sort((a, b) => a - b)[0];
      if (footerAt !== undefined) html = html.slice(0, footerAt);
    }
    element.innerHTML = html;
    const references = [...(context?.footnoteRefs ?? [])].filter(([at]) => at >= blockFrom && at < blockFrom + source.length).sort(([a],[b]) => a-b);
    element.querySelectorAll<HTMLAnchorElement>('sup.footnote-ref > a').forEach((anchor, index) => {
      const reference = references[index]?.[1];
      if (!reference) return;
      const suffix = reference.occurrence ? `:${reference.occurrence}` : '';
      anchor.href = `#fn${reference.number}`; anchor.id = `fnref${reference.number}${suffix}`;
      anchor.textContent = `[${reference.number}]`;
    });
    // Keep checkboxes as explicit editor transactions; never rely on mutated DOM as the document.
    element.querySelectorAll('li').forEach(li => {
      if (li.dataset.taskOffset === undefined) return;
      const walker = document.createTreeWalker(li, NodeFilter.SHOW_TEXT);
      let text = walker.nextNode();
      while (text && !text.textContent?.trim()) text = walker.nextNode();
      if (text?.parentElement?.closest('li') !== li || text?.parentElement?.closest('pre, code')) return;
      if (!text || !/^\[[ xX]\] /.test(text.textContent ?? '')) return;
      const checked = /^\[[xX]\]/.test(text.textContent!);
      const button = document.createElement('button');
      button.className = 'task-checkbox'; button.type = 'button';
      button.setAttribute('role', 'checkbox'); button.setAttribute('aria-checked', String(checked));
      button.setAttribute('aria-label', '할 일 완료 상태 변경'); button.dataset.task = li.dataset.taskOffset;
      button.textContent = checked ? '✓' : '';
      text.textContent = text.textContent!.slice(4); text.parentNode!.insertBefore(button, text);
      li.classList.add('task-item');
    });
  }
  if (context?.footnotesHTML && definitionsHere.includes(context.definitions[0])) {
    element.insertAdjacentHTML('beforeend', context.footnotesHTML);
  }
  return element;
}

export function showRenderError(element: HTMLElement, source: string, error: string) {
  element.replaceChildren();
  const pre = document.createElement('pre'); pre.textContent = source;
  const caption = document.createElement('div'); caption.className = 'render-error'; caption.textContent = error.slice(0, 250);
  element.append(pre, caption);
}

export function renderInlineMath(source: string): HTMLElement {
  const span = document.createElement('span');
  span.className = 'md-inline-math';
  katex.render(source.slice(1, -1), span, { trust: false, throwOnError: false, strict: 'ignore', maxSize: 20, maxExpand: 1000 });
  return span;
}

const standaloneCSS = `
:root{color-scheme:light dark;font:17px/1.7 -apple-system,BlinkMacSystemFont,"Segoe UI","Apple SD Gothic Neo",sans-serif}
body{max-width:900px;margin:48px auto;padding:0 32px;color:#282b30;background:#faf9f6} h1,h2,h3{line-height:1.35;break-after:avoid} pre,code{font-family:"SF Mono",Consolas,monospace} pre{overflow:auto;padding:14px;background:#f0efeb;border-radius:6px;white-space:pre-wrap;break-inside:avoid} code{background:#f0efeb;padding:.1em .25em;border-radius:3px} img,svg{max-width:100%;height:auto;break-inside:avoid} table{border-collapse:collapse;display:block;overflow:auto;max-width:100%;break-inside:avoid}th,td{border:1px solid #bbb;padding:8px 12px;text-align:left}.image-placeholder,.front-matter{display:block;padding:12px;border:1px solid #bbb;background:#f6f5f1;color:#555}.front-matter pre{margin:0;background:transparent;padding:0}.task-checkbox{display:inline-block;width:1em;height:1em;margin-right:.4em;border:1px solid #777;border-radius:2px;font-size:.8em;line-height:1;background:transparent}.task-checkbox[aria-checked=true]{background:#376897;color:white}@media print{body{max-width:none;margin:0;padding:0;color:#111!important;background:#fff!important}pre,code,.front-matter{color:#111!important;background:#f5f5f5!important;border-color:#bbb!important}a{color:#111!important;text-decoration:underline}table{overflow:visible}thead{display:table-header-group}}`;

async function dataURLFor(url: string) {
  const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error(`이미지 파일을 읽을 수 없습니다 (${response.status}).`);
  const blob = await response.blob();
  if (!blob.type.startsWith('image/')) throw new Error('이미지 파일 형식을 확인할 수 없습니다.');
  return await new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error('이미지 데이터를 변환할 수 없습니다.'));
    reader.onload = () => resolve(String(reader.result));
    reader.readAsDataURL(blob);
  });
}

/** Render the entire current Markdown source for an offline HTML export. */
export async function renderStandaloneHTML(source: string, settings: Settings, embedLocalAssets = true): Promise<string> {
  const root = document.createElement('main');
  const frontMatter = frontMatterFor(source);
  let body = source;
  if (frontMatter) {
    const section = document.createElement('section');
    section.className = 'front-matter';
    const pre = document.createElement('pre'); pre.textContent = frontMatter.raw;
    section.append(pre); root.append(section);
    body = source.slice(frontMatter.bodyFrom);
  }
  // Remote assets remain blocked in an exported document even when they were
  // enabled for the interactive preview.
  const safeSettings = { ...settings, remoteImages: false };
  const context = documentRenderContext(body);
  if (/\[\^[^\]]+\]/.test(body)) {
    // Footnote definitions are document-scoped in markdown-it, so parse this
    // export as one document to retain repeated references and rich bodies.
    const mathBlocks: string[] = [];
    let documentBody = body;
    // Operate on parsed blocks only. Regex replacement over the whole string
    // would incorrectly turn examples in fenced code into a TOC or equation.
    for (const block of blocksFor(body).reverse()) {
      if (/^\[toc\]\s*$/i.test(block.source.trim())) documentBody = documentBody.slice(0, block.from) + tableOfContentsMarkdown(body) + documentBody.slice(block.to);
      if (block.kind === 'DisplayMath') {
        const math = block.source.trim().slice(2, -2).trim();
        const index = mathBlocks.push(math) - 1;
        documentBody = documentBody.slice(0, block.from) + `@@DISPLAY_MATH_${index}@@` + documentBody.slice(block.to);
      }
    }
    const element = document.createElement('div'); element.className = 'rendered-document'; element.innerHTML = md.render(documentBody, { settings: safeSettings }); root.append(element);
    for (const paragraph of [...element.querySelectorAll<HTMLElement>('p')]) {
      const match = /^@@DISPLAY_MATH_(\d+)@@$/.exec(paragraph.textContent?.trim() ?? '');
      if (!match) continue;
      const math = mathBlocks[Number(match[1])] ?? '';
      try { paragraph.className = 'math-block'; katex.render(math, paragraph, { displayMode: true, trust: false, throwOnError: true, strict: 'ignore', maxSize: 20, maxExpand: 1000 }); }
      catch (error) { showRenderError(paragraph, math, String(error)); }
    }
    for (const code of [...element.querySelectorAll<HTMLElement>('pre > code.language-mermaid')]) {
      const diagram = document.createElement('div');
      const pre = code.parentElement!;
      pre.replaceWith(diagram);
      await renderStandaloneDiagram(diagram, `\`\`\`mermaid\n${code.textContent ?? ''}\n\`\`\``, 'light');
    }
  } else {
    for (const block of blocksFor(body)) {
      const isMermaid = /^\s*(`{3,}|~{3,})mermaid(?:\s|$)/i.test(block.source);
      const element = isMermaid ? document.createElement('div') : renderBlock(block.source, safeSettings, context, block.from);
      if (isMermaid) await renderStandaloneDiagram(element, block.source, 'light');
      root.append(element);
    }
  }
  const headingCounts = new Map<string, number>();
  root.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach(heading => {
    const base = headingSlug(heading.textContent ?? '') || 'section', count = headingCounts.get(base) ?? 0;
    headingCounts.set(base, count + 1); heading.id = count ? `${base}-${count + 1}` : base;
  });
  for (const image of [...root.querySelectorAll('img')]) {
    const src = image.getAttribute('src') ?? '';
    if (!embedLocalAssets || !src.startsWith('app://assets/')) continue;
    image.setAttribute('src', await dataURLFor(src));
    image.setAttribute('loading', 'eager'); image.setAttribute('decoding', 'sync');
  }
  const styles = await finishExportAssets(root);
  return `<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:"><title>Markdown export</title><style>${standaloneCSS}\n${styles}</style></head><body>${root.innerHTML}</body></html>`;
}

let mermaidPromise: Promise<typeof import('mermaid')> | undefined;
let queue = Promise.resolve();
let diagramID = 0;
export function renderDiagram(element: HTMLElement, source: string, theme: string, isCurrent: () => boolean, measured: () => void) {
  const sourceCode = source.replace(/^\s*(`{3,}|~{3,})mermaid[^\n]*\n/i, '').replace(/\n\s*(`{3,}|~{3,})\s*$/, '');
  element.classList.add('diagram-block');
  element.textContent = '다이어그램 불러오는 중…';
  queue = queue.then(async () => {
    if (!element.isConnected || !isCurrent()) return;
    try {
      if (sourceCode.length > 50000) throw new Error('다이어그램이 너무 커 원문으로 표시합니다.');
      mermaidPromise ??= import('mermaid');
      const mermaid = (await mermaidPromise).default;
      mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: theme === 'night' ? 'base' : theme === 'dark' ? 'dark' : 'default',
        themeVariables: theme === 'night' ? {
          darkMode: true, background: '#373b40', primaryColor: '#465363', primaryTextColor: '#dee1e5', primaryBorderColor: '#8393a5',
          lineColor: '#b3b9c2', secondaryColor: '#41464d', tertiaryColor: '#3d434a', textColor: '#dee1e5',
          edgeLabelBackground: '#373b40', clusterBkg: '#30343a', clusterBorder: '#687380',
        } : undefined,
        maxTextSize: 50000, maxEdges: 500, suppressErrorRendering: true, flowchart: { htmlLabels: false } });
      const { svg } = await mermaid.render(`diagram-${++diagramID}`, sourceCode);
      if (element.isConnected && isCurrent()) { element.innerHTML = svg; measured(); }
    } catch (error) {
      if (element.isConnected && isCurrent()) { showRenderError(element, source, String(error)); measured(); }
    }
  }).catch(() => {});
}

async function renderStandaloneDiagram(element: HTMLElement, source: string, theme: string) {
  const sourceCode = source.replace(/^\s*(`{3,}|~{3,})mermaid[^\n]*\n/i, '').replace(/\n\s*(`{3,}|~{3,})\s*$/, '');
  await (queue = queue.then(async () => {
    try {
      if (sourceCode.length > 50000) throw new Error('다이어그램이 너무 커 원문으로 표시합니다.');
      mermaidPromise ??= import('mermaid');
      const mermaid = (await mermaidPromise).default;
      mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: theme === 'night' ? 'base' : theme === 'dark' ? 'dark' : 'default', maxTextSize: 50000, maxEdges: 500, suppressErrorRendering: true, flowchart: { htmlLabels: false } });
      const { svg } = await mermaid.render(`export-diagram-${++diagramID}`, sourceCode);
      element.className = 'diagram-block'; element.innerHTML = svg;
    } catch (error) { showRenderError(element, source, `다이어그램 내보내기 실패: ${String(error)}`); }
  }).catch(() => {}));
}
