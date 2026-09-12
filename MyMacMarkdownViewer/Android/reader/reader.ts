import './reader.css';
import { documentRenderContext, renderBlock, renderDiagram } from '../../Editor/src/render';
import { blocksFor, outlineFor } from '../../Editor/src/markdown';
import { frontMatterFor, headingSlug } from '../../Editor/src/semantic';
import { defaultSettings, setSession } from '../../Editor/src/protocol';
import type { Settings } from '../../Editor/src/protocol';

const $ = <T extends HTMLElement = HTMLElement>(selector: string) => document.querySelector<T>(selector)!;
const article = $('#document'), reading = $('#reading');
let settings: Settings = { ...defaultSettings, theme: 'night', fontSize: 17, lineHeight: 1.8 };
try {
  const stored = JSON.parse(localStorage.getItem('reader-settings') || '{}');
  // Apply the approved Night default once on upgrade, then respect later choices.
  if (stored.nightDefaultVersion === 1 && ['dark', 'light', 'night'].includes(stored.theme)) settings.theme = stored.theme;
  if (Number.isFinite(stored.fontSize)) settings.fontSize = Math.max(14, Math.min(28, stored.fontSize));
  if (Number.isFinite(stored.lineHeight)) settings.lineHeight = Math.max(1.5, Math.min(2.2, stored.lineHeight));
} catch { /* A corrupt preference never prevents opening a document. */ }
let current: { id: string; name: string; text: string; hasFolder: boolean } | null = null;
let folder: { id: string; name: string; parentId: string | null; error?: string; entries: { id: string; name: string; directory: boolean }[] } | null = null;
let generation = 0, remoteAllowed = false;
let positionTimer: ReturnType<typeof setTimeout> | undefined;
let lastPosition = 0, resizeFrame = 0, renderingPosition = false;
let matches: HTMLElement[] = [], matchIndex = -1, searchLimited = false;
type OutlineNode = { from: number; level: number; depth: number; title: string; heading: HTMLElement; parent?: OutlineNode; children: OutlineNode[]; row: HTMLElement; jump: HTMLButtonElement; toggle?: HTMLButtonElement; collapsed: boolean };
let outlineNodes: OutlineNode[] = [], outlineCollapsed = new Map<number, boolean>(), outlineFrame = 0, outlinePositionsDirty = true, activeOutlineNode: OutlineNode | undefined;
let outlinePositions: number[] = [];
const normalizeFind = (value: string) => value.normalize('NFC').trim().toLocaleLowerCase();
const native = (type: string, extra: Record<string, unknown> = {}) => {
  const bridge = (window as any).AndroidBridge;
  if (bridge?.postMessage) bridge.postMessage(JSON.stringify({ type, ...extra }));
  else notice('파일 열기는 Android 앱에서 사용할 수 있습니다.');
};
function notice(message: string) { $('#notice span').textContent = message; $('#notice').hidden = false; }
$('#notice button').onclick = () => { $('#notice').hidden = true; };
function persistSettings() {
  document.documentElement.dataset.theme = settings.theme;
  document.documentElement.style.setProperty('--font-size', `${settings.fontSize}px`);
  document.documentElement.style.setProperty('--line-height', String(settings.lineHeight));
  try { localStorage.setItem('reader-settings', JSON.stringify({ ...settings, nightDefaultVersion: 1 })); } catch { /* Reading remains available without preference storage. */ }
  document.querySelectorAll<HTMLElement>('.theme-options [data-theme]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.theme === settings.theme)));
  $('#size-value').textContent = `${settings.fontSize}px`;
  $('#line-value').textContent = String(settings.lineHeight);
}
persistSettings();
function navigation(open: boolean) {
  $('#sidebar').classList.toggle('open', open); $('#sidebar').inert = !open;
  $('#scrim').hidden = !open; $('#navigation').setAttribute('aria-expanded', String(open));
  if (!open && $('#sidebar').contains(document.activeElement)) $('#navigation').focus();
}
$('#navigation').onclick = () => navigation(!$('#sidebar').classList.contains('open'));
$('#close-navigation').onclick = () => navigation(false); $('#scrim').onclick = () => navigation(false);
const wide = matchMedia('(min-width:840px)');
navigation(wide.matches); wide.addEventListener('change', () => navigation(wide.matches));
document.querySelectorAll<HTMLElement>('[data-native]').forEach(b => b.onclick = () => native(b.dataset.native!));
document.querySelectorAll<HTMLElement>('[data-tab]').forEach(b => b.onclick = () => {
  document.querySelectorAll<HTMLElement>('[data-tab]').forEach(t => t.setAttribute('aria-selected', String(t === b)));
  $('#files-panel').hidden = b.dataset.tab !== 'files'; $('#outline-panel').hidden = b.dataset.tab !== 'outline';
});
$('#preferences').onclick = () => {
  $('#font-size').setAttribute('value', String(settings.fontSize));
  ($<HTMLInputElement>('#font-size')).value = String(settings.fontSize);
  ($<HTMLInputElement>('#line-height')).value = String(settings.lineHeight);
  $<HTMLDialogElement>('#settings').showModal();
};
document.querySelectorAll<HTMLElement>('.theme-options [data-theme]').forEach(b => b.onclick = () => {
  settings.theme = b.dataset.theme as Settings['theme']; persistSettings(); native('theme', { theme: settings.theme });
  if (current) void renderDocument(true);
});
$<HTMLInputElement>('#font-size').oninput = event => { settings.fontSize = Number((event.target as HTMLInputElement).value); persistSettings(); };
$<HTMLInputElement>('#line-height').oninput = event => { settings.lineHeight = Number((event.target as HTMLInputElement).value); persistSettings(); };
function renderFolder() {
  $<HTMLInputElement>('#folder-query').disabled = !folder;
  if (!folder) return;
  $('#folder-title').textContent = folder.name; $('#folder-up').hidden = !folder.parentId; $('#refresh-folder').hidden = false;
  const list = $('#files'); list.replaceChildren();
  if (folder.error) { const p = document.createElement('p'); p.className = 'muted'; p.setAttribute('role', 'status'); p.textContent = folder.error; list.append(p); return; }
  const query = normalizeFind($<HTMLInputElement>('#folder-query').value);
  const entries = query ? folder.entries.filter(entry => normalizeFind(entry.name).includes(query)) : folder.entries;
  for (const entry of entries) {
    const button = document.createElement('button');
    button.setAttribute('aria-current', String(entry.name === current?.name));
    const icon = document.createElement('span'); icon.className = 'file-icon'; icon.setAttribute('aria-hidden', 'true'); icon.textContent = entry.directory ? '›' : '≡';
    const name = document.createElement('span'); name.textContent = entry.name;
    button.append(icon, name); button.onclick = () => native(entry.directory ? 'listFolder' : 'openEntry', { id: entry.id }); list.append(button);
  }
  if (!entries.length) { const p = document.createElement('p'); p.className = 'muted'; p.setAttribute('role', 'status'); p.textContent = query ? '일치하는 파일 또는 폴더가 없습니다.' : '이 폴더에는 Markdown 문서가 없습니다.'; list.append(p); }
}
$('#refresh-folder').onclick = () => { if (folder) native('listFolder', { id: folder.id }); };
$('#folder-up').onclick = () => { if (folder?.parentId) native('listFolder', { id: folder.parentId }); };
$<HTMLInputElement>('#folder-query').oninput = () => { $('#clear-folder-query').hidden = !$<HTMLInputElement>('#folder-query').value; renderFolder(); };
$('#clear-folder-query').onclick = () => { $<HTMLInputElement>('#folder-query').value = ''; $('#clear-folder-query').hidden = true; renderFolder(); $<HTMLInputElement>('#folder-query').focus(); };
function applyOutlineFilter() {
  const query = normalizeFind($<HTMLInputElement>('#outline-query').value);
  $('#clear-outline-query').hidden = !query;
  $('#collapse-outline').toggleAttribute('disabled', Boolean(query)); $('#expand-outline').toggleAttribute('disabled', Boolean(query));
  const visible = new Set<OutlineNode>();
  if (query) for (const node of outlineNodes) if (normalizeFind(node.title).includes(query)) for (let cursor: OutlineNode | undefined = node; cursor; cursor = cursor.parent) visible.add(cursor);
  for (const node of outlineNodes) {
    const allowed = !query || visible.has(node);
    const ancestorCollapsed = !query && ancestorIsCollapsed(node);
    node.row.hidden = !allowed || ancestorCollapsed;
    if (node.toggle) { const expanded = query || !node.collapsed; node.toggle.disabled = Boolean(query); node.toggle.setAttribute('aria-expanded', String(expanded)); node.toggle.setAttribute('aria-label', `${node.title} ${expanded ? '접기' : '펼치기'}`); node.toggle.textContent = expanded ? '⌄' : '›'; }
  }
  $('#outline-search-status').textContent = query && !visible.size ? '일치하는 제목이 없습니다.' : '';
}
function ancestorIsCollapsed(node: OutlineNode) { for (let parent = node.parent; parent; parent = parent.parent) if (parent.collapsed) return true; return false; }
function setOutlineCollapsed(node: OutlineNode, collapsed: boolean) {
  node.collapsed = collapsed; outlineCollapsed.set(node.from, collapsed);
  applyOutlineFilter();
}
function makeOutline(source: string, preserveState = false) {
  const outline = $('#outline'); outline.replaceChildren();
  const metadata = frontMatterFor(source);
  const headings = outlineFor(source).filter(item => !metadata || item.from >= metadata.bodyFrom);
  const rendered = [...article.querySelectorAll<HTMLElement>('h1,h2,h3,h4,h5,h6')];
  const used = new Map<string, number>(), targets = new Map<number, HTMLElement>();
  rendered.forEach((heading, index) => {
    const item = headings[index];
    const base = headingSlug(item?.title ?? heading.textContent ?? '') || 'section', count = used.get(base) ?? 0;
    used.set(base, count + 1); heading.id = count ? `${base}-${count + 1}` : base;
    if (item) targets.set(item.from, heading);
  });
  if (!preserveState) outlineCollapsed.clear();
  outlineNodes = []; activeOutlineNode = undefined; const stack: OutlineNode[] = [];
  rendered.forEach((heading, index) => {
    const item = headings[index], level = Number(heading.tagName[1]);
    while (stack.length && stack.at(-1)!.level >= level) stack.pop();
    const parent = stack.at(-1), row = document.createElement('div'); row.className = 'outline-row';
    const node: OutlineNode = { from: item?.from ?? index, level, depth: parent ? parent.depth + 1 : 0, title: heading.textContent || '', heading, parent, children: [], row, jump: document.createElement('button'), collapsed: preserveState && Boolean(outlineCollapsed.get(item?.from ?? index)) };
    row.style.setProperty('--depth', String(node.depth));
    node.parent?.children.push(node); stack.push(node); outlineNodes.push(node);
    node.jump.className = 'outline-jump'; node.jump.textContent = node.title; node.jump.setAttribute('aria-current', 'false');
    node.jump.onclick = () => { heading.scrollIntoView({ block: 'start' }); if (!wide.matches) navigation(false); };
    row.append(node.jump); outline.append(row);
  });
  for (const node of outlineNodes) if (node.children.length) {
    const toggle = document.createElement('button'); toggle.type = 'button'; toggle.className = 'outline-toggle'; node.toggle = toggle;
    toggle.onclick = event => { event.stopPropagation(); setOutlineCollapsed(node, !node.collapsed); };
    node.row.prepend(toggle);
  }
  applyOutlineFilter(); markOutlinePositionsDirty();
  if (!outline.childElementCount) {
    outline.textContent = '이 문서에는 제목이 없습니다.';
    $('#outline-search-status').textContent = ''; $('#outline-status').textContent = '';
    $('#collapse-outline').disabled = true; $('#expand-outline').disabled = true;
  }
  return targets;
}
$<HTMLInputElement>('#outline-query').oninput = () => applyOutlineFilter();
$('#clear-outline-query').onclick = () => { $<HTMLInputElement>('#outline-query').value = ''; applyOutlineFilter(); $<HTMLInputElement>('#outline-query').focus(); };
$('#collapse-outline').onclick = () => { for (const node of outlineNodes) if (node.children.length) { node.collapsed = true; outlineCollapsed.set(node.from, true); } applyOutlineFilter(); };
$('#expand-outline').onclick = () => { for (const node of outlineNodes) if (node.children.length) { node.collapsed = false; outlineCollapsed.set(node.from, false); } applyOutlineFilter(); };
function scrollRatio() {
  const range = reading.scrollHeight - reading.clientHeight;
  return range > 1 ? Math.max(0, Math.min(1, reading.scrollTop / range)) : 0;
}
function restoreScroll(ratio: number) {
  const range = reading.scrollHeight - reading.clientHeight;
  lastPosition = Math.max(0, Math.min(1, ratio));
  const behavior = reading.style.scrollBehavior;
  reading.style.scrollBehavior = 'auto';
  reading.scrollTop = Math.round(lastPosition * Math.max(0, range));
  reading.style.scrollBehavior = behavior;
}
function sendPosition() {
  if (!current || renderingPosition) return;
  native('position', { id: current.id, ratio: scrollRatio() });
}
function schedulePosition() {
  if (positionTimer) clearTimeout(positionTimer);
  positionTimer = setTimeout(() => { positionTimer = undefined; sendPosition(); }, 350);
}
async function renderDocument(keepPosition = false, requestedPosition = 0) {
  if (!current) return;
  const captured = current, revision = ++generation, oldPosition = scrollRatio();
  renderingPosition = true;
  $('#loading').hidden = false; $('#welcome').hidden = true; article.hidden = false;
  article.replaceChildren(); matches = []; matchIndex = -1;
  const options = { ...settings, remoteImages: remoteAllowed };
  const context = documentRenderContext(captured.text);
  setSession({ documentID: captured.id, sessionID: captured.id, revision: 0, baseURL: '' });
  await new Promise(resolve => setTimeout(resolve, 0));
  if (revision !== generation) return;
  const blocks = blocksFor(captured.text);
  for (let index = 0; index < blocks.length; index++) {
    if (revision !== generation) return;
    const block = blocks[index], source = captured.text.slice(block.from, block.to);
    const node = renderBlock(source, options, context, block.from);
    // The reader uses the display renderer only: no editor, writable inputs, or edit commands.
    node.querySelectorAll<HTMLElement>('.task-checkbox').forEach(button => {
      const indicator = document.createElement('span'); indicator.className = 'task-checkbox';
      indicator.textContent = button.textContent;
      indicator.setAttribute('role', 'img'); indicator.setAttribute('aria-label', button.getAttribute('aria-checked') === 'true' ? '완료한 항목' : '미완료 항목');
      button.replaceWith(indicator);
    });
    node.querySelectorAll<HTMLImageElement>('img').forEach(img => {
      const src = img.getAttribute('src') || '';
      if (src.startsWith('app://assets/')) img.src = `https://appassets.androidplatform.net/media/${encodeURIComponent(captured.id)}/${src.split('/').slice(4).join('/')}`;
      img.onerror = () => {
        if (revision !== generation) return;
        const placeholder = document.createElement('span'); placeholder.className = 'image-placeholder';
        placeholder.textContent = `${img.alt || '이미지'} · ${captured.hasFolder ? '이미지를 찾거나 표시할 수 없습니다.' : '함께 있는 이미지를 읽으려면 문서가 든 폴더를 열어 주세요.'}`;
        img.replaceWith(placeholder);
      };
    });
    node.querySelectorAll('table').forEach(table => { const scroller = document.createElement('div'); scroller.className = 'table-scroll'; scroller.tabIndex = 0; scroller.setAttribute('aria-label', '표, 가로로 스크롤'); table.replaceWith(scroller); scroller.append(table); });
    article.append(node);
    if (block.kind === 'FencedCode' && /^\s*(`{3,}|~{3,})mermaid\b/.test(source)) renderDiagram(node, source, settings.theme, () => revision === generation, () => {});
    if (index % 24 === 23) await new Promise(resolve => setTimeout(resolve, 0));
  }
  if (revision !== generation) return;
  if (!blocks.length) { const empty = document.createElement('p'); empty.className = 'muted'; empty.textContent = '내용이 없는 문서입니다.'; article.append(empty); }
  const headingTargets = makeOutline(captured.text, keepPosition);
  article.querySelectorAll<HTMLElement>('[data-jump]').forEach(link => {
    link.onclick = event => {
      event.preventDefault();
      const target = headingTargets.get(Number(link.dataset.jump));
      if (target) { target.scrollIntoView({ block: 'start' }); if (!wide.matches) navigation(false); }
    };
  });
  $('#loading').hidden = true;
  restoreScroll(keepPosition ? oldPosition : requestedPosition); renderingPosition = false; updateProgress(); markOutlinePositionsDirty();
  if ($<HTMLInputElement>('#query').value) search();
  article.dataset.ready = captured.id;
}
article.addEventListener('click', event => {
  const target = event.target as HTMLElement;
  if (target.closest('[data-remote-images]')) { native('allowRemote', { id: current?.id }); return; }
  const link = target.closest('a'); if (!link) return;
  event.preventDefault(); const href = link.getAttribute('href') || '';
  if (href.startsWith('#')) {
    let wanted = ''; try { wanted = decodeURIComponent(href.slice(1)); } catch { return; }
    const elements = [...article.querySelectorAll<HTMLElement>('[id],h1,h2,h3,h4,h5,h6')];
    const destination = elements.find(element => element.id === wanted || (!element.id && element.textContent?.trim().toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu, '').replace(/\s+/g, '-') === wanted.toLowerCase()));
    if (destination) destination.scrollIntoView({ block: 'start' }); else notice('해당 위치를 찾을 수 없습니다.');
  } else native('openLink', { id: current?.id, href });
});
function updateProgress() {
  if (!current) { $('#progress').textContent = ''; return; }
  const range = reading.scrollHeight - reading.clientHeight;
  $('#progress').textContent = range <= 1 ? '전체 문서' : `${Math.round(reading.scrollTop / range * 100)}%`;
}
function markOutlinePositionsDirty() { outlinePositionsDirty = true; scheduleOutlineCurrent(); }
function updateOutlineCurrent() {
  outlineFrame = 0;
  if (!outlineNodes.length) return;
  if (outlinePositionsDirty) {
    const readingTop = reading.getBoundingClientRect().top;
    outlinePositions = outlineNodes.map(node => node.heading.getBoundingClientRect().top - readingTop + reading.scrollTop);
    outlinePositionsDirty = false;
  }
  const range = reading.scrollHeight - reading.clientHeight;
  let index = 0;
  if (range > 1 && reading.scrollTop >= range - 1) index = outlineNodes.length - 1;
  else {
    const top = reading.scrollTop + 18; let low = 0, high = outlinePositions.length - 1;
    while (low <= high) { const mid = (low + high) >> 1; if (outlinePositions[mid] <= top) { index = mid; low = mid + 1; } else high = mid - 1; }
  }
  const active = outlineNodes[index];
  if (active === activeOutlineNode) return;
  if (activeOutlineNode) { activeOutlineNode.jump.setAttribute('aria-current', 'false'); activeOutlineNode.row.classList.remove('current-outline'); }
  activeOutlineNode = active; active.jump.setAttribute('aria-current', 'true'); active.row.classList.add('current-outline');
  $('#outline-status').textContent = `현재 읽는 절: ${active.title}`;
}
function scheduleOutlineCurrent() { if (!outlineFrame) outlineFrame = requestAnimationFrame(updateOutlineCurrent); }
reading.addEventListener('scroll', () => { if (!renderingPosition) { lastPosition = scrollRatio(); schedulePosition(); } updateProgress(); scheduleOutlineCurrent(); }, { passive: true });
new ResizeObserver(() => {
  updateProgress(); markOutlinePositionsDirty();
  if (!renderingPosition && !resizeFrame) resizeFrame = requestAnimationFrame(() => {
    resizeFrame = 0;
    if (renderingPosition) return;
    restoreScroll(lastPosition); updateProgress(); markOutlinePositionsDirty();
  });
}).observe(article);
article.addEventListener('load', markOutlinePositionsDirty, true);
function clearMatches() {
  article.querySelectorAll('mark.reader-match').forEach(mark => mark.replaceWith(document.createTextNode(mark.textContent || '')));
  article.normalize(); matches = []; matchIndex = -1;
}
function search() {
  clearMatches(); searchLimited = false;
  const query = $<HTMLInputElement>('#query').value.trim();
  if (!query || !current) { $('#match-count').textContent = !current ? '먼저 문서를 열어 주세요' : '검색어를 입력하세요'; return; }
  const regex = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'giu');
  const walker = document.createTreeWalker(article, NodeFilter.SHOW_TEXT, { acceptNode(node) { return (node.parentElement?.closest('.katex,svg,button,mark') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT); } });
  const nodes: Text[] = []; while (walker.nextNode()) nodes.push(walker.currentNode as Text);
  for (const text of nodes) {
    if (matches.length >= 500) { searchLimited = true; break; }
    const value = text.data, fragment = document.createDocumentFragment(); let offset = 0, hit: RegExpExecArray | null;
    regex.lastIndex = 0;
    while ((hit = regex.exec(value)) && matches.length < 500) {
      fragment.append(value.slice(offset, hit.index)); const mark = document.createElement('mark'); mark.className = 'reader-match'; mark.textContent = hit[0]; fragment.append(mark); matches.push(mark); offset = hit.index + hit[0].length;
    }
    if (offset) { fragment.append(value.slice(offset)); text.replaceWith(fragment); }
  }
  moveMatch(1);
}
function moveMatch(direction: number) {
  if (!matches.length) { $('#match-count').textContent = '일치하는 내용이 없습니다'; return; }
  matches[matchIndex]?.classList.remove('current-match'); matchIndex = (matchIndex + direction + matches.length) % matches.length;
  matches[matchIndex].classList.add('current-match'); matches[matchIndex].scrollIntoView({ block: 'center' });
  $('#match-count').textContent = `${matchIndex + 1} / ${matches.length}${searchLimited ? '+' : ''}`;
}
$('#find').onclick = () => { $<HTMLDialogElement>('#search-dialog').showModal(); $<HTMLInputElement>('#query').focus(); if (!current) $('#match-count').textContent = '먼저 문서를 열어 주세요'; };
$('#close-search').onclick = () => $<HTMLDialogElement>('#search-dialog').close();
let searchTimer: ReturnType<typeof setTimeout>;
$<HTMLInputElement>('#query').oninput = () => { clearTimeout(searchTimer); searchTimer = setTimeout(search, 180); };
$('#search-form').onsubmit = event => { event.preventDefault(); clearTimeout(searchTimer); if (!matches.length) search(); else moveMatch(1); };
$('#previous-match').onclick = () => moveMatch(-1);
(window as any).ReaderHost = { receive(event: any) {
  if (!event || typeof event !== 'object') return;
  if (event.type === 'document') {
    if (typeof event.id !== 'string' || typeof event.text !== 'string') return;
    current = event; remoteAllowed = false; $('#notice').hidden = true;
    $('#title').textContent = event.name || 'Markdown 문서'; $('#subtitle').textContent = '읽기 전용';
    $<HTMLInputElement>('#query').value = ''; $<HTMLInputElement>('#outline-query').value = ''; outlineCollapsed.clear(); renderFolder();
    if (!wide.matches) navigation(false);
    const position = typeof event.position === 'number' && Number.isFinite(event.position) ? event.position : 0;
    void renderDocument(false, position).catch(() => { $('#loading').hidden = true; notice('문서를 표시하지 못했습니다. 다른 파일을 열어 주세요.'); });
  } else if (event.type === 'folder') {
    const changedFolder = folder?.id !== event.id;
    folder = event;
    if (changedFolder) { $<HTMLInputElement>('#folder-query').value = ''; $('#clear-folder-query').hidden = true; }
    renderFolder(); if (!event.passive) navigation(true); if (event.truncated) notice(event.message || '항목이 많아 일부만 표시합니다.');
  }
  else if (event.type === 'remoteAllowed' && event.id === current?.id) { remoteAllowed = true; void renderDocument(true); }
  else if (event.type === 'error') { $('#loading').hidden = true; notice(String(event.message || '파일을 열 수 없습니다.')); }
}, flushPosition() {
  if (positionTimer) { clearTimeout(positionTimer); positionTimer = undefined; }
  sendPosition();
}, back() {
  const dialog = document.querySelector<HTMLDialogElement>('dialog[open]');
  if (dialog) { dialog.close(); return true; }
  if ($('#sidebar').classList.contains('open')) { navigation(false); return true; }
  return false;
}, snapshot() { return { id: current?.id, name: current?.name, ready: article.dataset.ready, theme: settings.theme, remoteAllowed, position: scrollRatio(), writableElements: article.querySelectorAll('input,textarea,[contenteditable=true]').length }; } };
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') (window as any).ReaderHost.flushPosition(); });
window.addEventListener('pagehide', () => (window as any).ReaderHost.flushPosition());
document.addEventListener('keydown', event => { if (event.key === 'Escape' && $('#sidebar').classList.contains('open')) navigation(false); });
native('ready');
native('theme', { theme: settings.theme });
