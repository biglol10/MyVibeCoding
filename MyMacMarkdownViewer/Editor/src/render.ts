import MarkdownIt from 'markdown-it';
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

for (const [name, grammar] of Object.entries({ javascript, typescript, swift, python, json, bash, css, xml, sql, yaml })) hljs.registerLanguage(name, grammar);
const md = new MarkdownIt({ html: false, linkify: false, typographer: false, highlight(code, language) {
  if (hljs.getLanguage(language)) return hljs.highlight(code, { language, ignoreIllegals: true }).value;
  return '';
}});

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

export function renderBlock(source: string, settings: Settings): HTMLElement {
  const element = document.createElement('div');
  element.className = 'rendered-block';
  if (/^\$\$[\s\S]*\$\$\s*$/.test(source.trim())) {
    const math = source.trim().slice(2, -2);
    element.classList.add('math-block');
    try { katex.render(math, element, { displayMode: true, trust: false, throwOnError: true, strict: 'ignore', maxSize: 20, maxExpand: 1000 }); }
    catch (error) { showRenderError(element, source, String(error)); }
  } else {
    element.innerHTML = md.render(source, { settings });
    // Keep checkboxes as explicit editor transactions; never rely on mutated DOM as the document.
    element.querySelectorAll('li').forEach(li => {
      const walker = document.createTreeWalker(li, NodeFilter.SHOW_TEXT);
      const text = walker.nextNode();
      if (!text || !/^\[[ xX]\] /.test(text.textContent ?? '')) return;
      const checked = /^\[[xX]\]/.test(text.textContent!);
      const button = document.createElement('button');
      button.className = 'task-checkbox'; button.type = 'button';
      button.setAttribute('role', 'checkbox'); button.setAttribute('aria-checked', String(checked));
      button.setAttribute('aria-label', '할 일 완료 상태 변경'); button.dataset.task = '';
      button.textContent = checked ? '✓' : '';
      text.textContent = text.textContent!.slice(4); text.parentNode!.insertBefore(button, text);
      li.classList.add('task-item');
    });
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
