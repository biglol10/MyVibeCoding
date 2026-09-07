import { EditorState, Compartment, EditorSelection } from '@codemirror/state';
import { EditorView, keymap, drawSelection, highlightActiveLine, dropCursor } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap, undo, redo, indentWithTab } from '@codemirror/commands';
import { search, searchKeymap, openSearchPanel } from '@codemirror/search';
import { markdown, markdownKeymap } from '@codemirror/lang-markdown';
import { languages } from '@codemirror/language-data';
import { syntaxHighlighting, defaultHighlightStyle, bracketMatching } from '@codemirror/language';
import { GFM } from '@lezer/markdown';
import { livePreview, previewOptions, setSourceMode, setComposition, updateSettings } from './livePreview';
import { outlineFor, rebaseMarkdown } from './markdown';
import { post, session, setSession, defaultSettings, accepts, type Settings } from './protocol';
import 'katex/dist/katex.min.css';
import './style.css';

const initialTheme = document.documentElement.dataset.theme;
let settings: Settings = { ...defaultSettings, theme: initialTheme === 'night' || initialTheme === 'light' ? initialTheme : 'dark' };
let sourceMode = false;
let loading = false;
let navigationAnchor: number | null = null;
let metadataTimer: ReturnType<typeof setTimeout>;
const readOnly = new Compartment();
const theme = new Compartment();
const welcome = `# 조용한 문서 공간\n\n긴 글을 편하게 읽고, 필요한 부분만 자연스럽게 고쳐 보세요.\n\n문서나 폴더를 열어 시작할 수 있습니다. **현재 블록**에서는 Markdown 원문이 보입니다.\n\n## 읽기와 편집\n\n- 왼쪽 사이드바에서 파일과 목차를 전환합니다.\n- **⌘P**로 파일을 빠르게 찾고 **⌘F**로 문서 안을 검색합니다.\n- **⌘⇧M**으로 원문 모드를 전환합니다.\n\n> 기본 테마는 다크 모드입니다. 설정에서 글꼴과 읽기 폭을 조절할 수 있습니다.\n`;

function emitMetadata() {
  clearTimeout(metadataTimer);
  metadataTimer = setTimeout(() => {
    const text = view.state.doc.toString();
    post('metadata', { headings: outlineFor(text), characters: [...text].length, words: text.trim() ? text.trim().split(/\s+/).length : 0, lines: view.state.doc.lines });
  }, 180);
}

function visibleFrom() {
  if (navigationAnchor !== null) return navigationAnchor;
  return view.lineBlockAtHeight(Math.max(0, view.scrollDOM.getBoundingClientRect().top + 32 - view.documentTop)).from;
}
function position() {
  const from = visibleFrom();
  post('position', { anchor: view.state.selection.main.anchor, head: view.state.selection.main.head, visibleFrom: from, scrollTop: view.scrollDOM.scrollTop });
}

function wrap(left: string, right = left) {
  if (!canEdit()) return;
  const selection = view.state.selection.main;
  const text = view.state.sliceDoc(selection.from, selection.to);
  view.dispatch({ changes: { from: selection.from, to: selection.to, insert: left + text + right },
    selection: EditorSelection.range(selection.from + left.length, selection.from + left.length + text.length), userEvent: 'input' });
  view.focus();
}

function prefix(value: string) {
  if (!canEdit()) return;
  const selection = view.state.selection.main;
  const first = view.state.doc.lineAt(selection.from).number;
  const last = view.state.doc.lineAt(selection.to).number;
  const changes = [];
  for (let i = first; i <= last; i++) changes.push({ from: view.state.doc.line(i).from, insert: value });
  view.dispatch({ changes, userEvent: 'input' }); view.focus();
}

const view = new EditorView({
  parent: document.querySelector('#editor')!,
  state: makeState(welcome),
});

function makeState(text: string, anchor = 0, head = anchor) {
  return EditorState.create({ doc: text, selection: EditorSelection.range(Math.min(anchor, text.length), Math.min(head, text.length)), extensions: [
    EditorState.phrases.of({
      'Find': '찾기', 'Replace': '바꿀 내용', 'next': '다음', 'previous': '이전',
      'all': '모두 선택', 'match case': '대소문자 구분', 'regexp': '정규식', 'by word': '단어 단위',
      'replace': '바꾸기', 'replace all': '모두 바꾸기', 'close': '닫기',
      'replaced $ matches': '$개 항목을 바꿨습니다', 'replaced match on line $': '$번째 줄을 바꿨습니다',
      'current match': '현재 일치 항목', 'on line': '줄',
    }),
    history(), drawSelection(), dropCursor(), bracketMatching(),
    markdown({ codeLanguages: languages, extensions: GFM }),
    syntaxHighlighting(defaultHighlightStyle),
    search({ top: true }), readOnly.of(EditorState.readOnly.of(false)),
    theme.of(EditorView.theme({}, { dark: settings.theme !== 'light' })),
    previewOptions, livePreview, highlightActiveLine(), EditorView.lineWrapping,
    EditorView.editorAttributes.of(view => ({ 'data-mode': view.state.field(previewOptions).sourceMode ? 'source' : 'live' })),
    EditorView.contentAttributes.of({ spellcheck: 'false', autocorrect: 'off', autocapitalize: 'off', 'aria-label': 'Markdown 편집기' }),
    keymap.of([
      { key: 'Mod-s', run: () => { post('save'); return true; } },
      { key: 'Mod-Shift-m', run: () => { command('source'); return true; } },
      { key: 'Mod-b', run: () => { wrap('**'); return true; } },
      { key: 'Mod-i', run: () => { wrap('*'); return true; } },
      { key: 'Mod-k', run: () => { wrap('[', '](https://)'); return true; } },
      ...markdownKeymap, ...defaultKeymap, ...historyKeymap, ...searchKeymap, indentWithTab,
    ]),
    EditorView.domEventHandlers({
      mousedown(event) {
        const link = (event.target as HTMLElement).closest<HTMLElement>('.md-link[data-href]');
        if (link && event.metaKey) { event.preventDefault(); post('openLink', { href: link.dataset.href }); return true; }
        return false;
      },
      compositionstart() { view.dispatch({ effects: setComposition.of(true) }); post('composition', { active: true }); },
      compositionend() {
        setTimeout(() => { view.dispatch({ effects: setComposition.of(false) }); post('composition', { active: false }); emitMetadata(); }, 0);
      },
      dragover(event) { if (event.dataTransfer?.types.includes('Files')) { event.preventDefault(); return true; } return false; },
      drop(event) {
        const files = [...(event.dataTransfer?.files ?? [])];
        if (!files.length) return false;
        event.preventDefault();
        const at = view.posAtCoords({ x: event.clientX, y: event.clientY });
        if (at != null) view.dispatch({ selection: { anchor: at } });
        void insertFiles(files); return true;
      },
      paste(event) {
        const files = [...(event.clipboardData?.files ?? [])];
        if (files.some(file => file.type.startsWith('image/'))) { event.preventDefault(); void insertFiles(files); return true; }
        return false;
      },
    }),
    EditorView.updateListener.of(update => {
      if (loading) return;
      if (update.docChanged) {
        const changes: { from: number; to: number; insert: string }[] = [];
        update.changes.iterChanges((from, to, _newFrom, _newTo, inserted) => changes.push({ from, to, insert: inserted.toString() }));
        const baseRevision = session.revision;
        session.revision++;
        post('changed', { baseRevision, changes, composing: update.view.composing || update.state.field(previewOptions).composing });
        if (!update.state.field(previewOptions).composing) emitMetadata();
      }
      if (update.selectionSet) {
        if (navigationAnchor !== update.state.selection.main.head) navigationAnchor = null;
        position();
      }
    }),
  ] });
}

async function insertFiles(files: File[]) {
  for (const file of files) {
    if (!/^image\/(png|jpeg|gif|webp|tiff|bmp|heic)$/.test(file.type)) continue;
    if (file.size > 20 * 1024 * 1024) { post('error', { message: '이미지는 20MB 이하만 삽입할 수 있습니다.' }); continue; }
    const reader = new FileReader();
    const currentSession = session.sessionID;
    const data = await new Promise<string>((resolve, reject) => { reader.onload = () => resolve(String(reader.result).split(',')[1]); reader.onerror = reject; reader.readAsDataURL(file); });
    if (currentSession === session.sessionID) post('insertImageData', { name: file.name, data });
  }
}

function applySettings(next: Partial<Settings>) {
  settings = { ...settings, ...next };
  document.documentElement.dataset.theme = settings.theme;
  const style = document.documentElement.style;
  style.setProperty('--font-size', `${Math.min(30, Math.max(12, settings.fontSize))}px`);
  style.setProperty('--line-height', String(Math.min(2.4, Math.max(1.3, settings.lineHeight))));
  style.setProperty('--content-width', `${Math.min(1200, Math.max(500, settings.contentWidth))}px`);
  const fonts: Record<string, string> = {
    system: '-apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif',
    serif: '"AppleMyungjo", "Georgia", serif', mono: '"SF Mono", Menlo, monospace',
  };
  style.setProperty('--font-family', fonts[settings.fontFamily] ?? fonts.system);
  view.dispatch({ effects: [updateSettings.of(settings), theme.reconfigure(EditorView.theme({}, { dark: settings.theme !== 'light' }))] });
}

function canEdit() {
  return !view.state.readOnly && !view.composing && !view.state.field(previewOptions).composing;
}

function command(name: string) {
  if (!canEdit() && !['find', 'copy', 'selectAll'].includes(name)) return;
  switch (name) {
    case 'undo': undo(view); break;
    case 'redo': redo(view); break;
    case 'find': openSearchPanel(view); break;
    case 'replace': openSearchPanel(view); (view.dom.querySelector('[name="replace"]') as HTMLInputElement | null)?.focus(); break;
    case 'bold': wrap('**'); break;
    case 'italic': wrap('*'); break;
    case 'link': wrap('[', '](https://)'); break;
    case 'code': wrap('`'); break;
    case 'codeBlock': wrap('\n```\n', '\n```\n'); break;
    case 'heading': prefix('## '); break;
    case 'quote': prefix('> '); break;
    case 'list': prefix('- '); break;
    case 'task': prefix('- [ ] '); break;
    case 'source': sourceMode = !sourceMode; view.dispatch({ effects: setSourceMode.of(sourceMode) }); post('sourceMode', { enabled: sourceMode }); break;
    case 'selectAll': view.dispatch({ selection: EditorSelection.range(0, view.state.doc.length) }); break;
  }
}

const host = {
  receive(message: any) {
    if (message.type === 'open') {
      loading = true;
      navigationAnchor = null;
      setSession({ documentID: message.documentID, sessionID: message.sessionID, revision: message.revision ?? 0, baseURL: message.baseURL ?? '' });
      sourceMode = message.sourceMode ?? false;
      settings = { ...settings, ...message.settings };
      view.setState(makeState(message.text, message.anchor ?? 0, message.head ?? message.anchor ?? 0));
      applySettings(settings); view.dispatch({ effects: setSourceMode.of(sourceMode) });
      const openedSession = session.sessionID, startingSelection = view.state.selection;
      requestAnimationFrame(() => {
        if (session.sessionID === openedSession && view.state.selection.eq(startingSelection)) view.scrollDOM.scrollTop = message.scrollTop ?? 0;
      });
      loading = false; emitMetadata(); post('opened'); return;
    }
    if (message.type === 'settings') { applySettings(message.settings); return; }
    if (!accepts(message)) return;
    if (message.type === 'command') command(message.command);
    if (message.type === 'jump') {
      navigationAnchor = Math.min(view.state.doc.length, message.from);
      view.dispatch({ selection: { anchor: navigationAnchor }, effects: EditorView.scrollIntoView(navigationAnchor, { y: 'start', yMargin: 32 }) }); view.focus();
    }
    if (message.type === 'insert') {
      if (!canEdit()) return;
      view.dispatch(view.state.replaceSelection(String(message.text))); view.focus();
    }
    if (message.type === 'lock') view.dispatch({ effects: readOnly.reconfigure(EditorState.readOnly.of(message.locked)) });
  },
  snapshot() { return { ...session, text: view.state.doc.toString(), anchor: view.state.selection.main.anchor, head: view.state.selection.main.head, scrollTop: view.scrollDOM.scrollTop, visibleFrom: visibleFrom(), composing: view.composing || view.state.field(previewOptions).composing }; },
  prepareSaveAs(newBase: string) { return { ...host.snapshot(), text: rebaseMarkdown(view.state.doc.toString(), session.baseURL, newBase) }; },
  focus() { view.focus(); },
};
Object.defineProperty(window, 'MarkdownHost', { value: host, writable: false });
if (!window.webkit) window.__editorTest = {
  load: (text: string) => host.receive({ type: 'open', documentID: 'test', sessionID: crypto.randomUUID(), revision: 0, text, settings }),
  snapshot: host.snapshot,
  insert: (text: string) => view.dispatch(view.state.replaceSelection(text)),
  select: (anchor: number, head = anchor) => view.dispatch({ selection: EditorSelection.range(anchor, head) }),
  command,
  settings: applySettings,
  usesDarkTheme: () => view.state.facet(EditorView.darkTheme),
  compose: (active: boolean) => view.dispatch({ effects: setComposition.of(active) }),
};
let scrollTimer: ReturnType<typeof setTimeout>;
view.scrollDOM.addEventListener('wheel', () => { navigationAnchor = null; }, { passive: true });
view.scrollDOM.addEventListener('pointerdown', () => { navigationAnchor = null; }, { passive: true });
view.scrollDOM.addEventListener('scroll', () => { clearTimeout(scrollTimer); scrollTimer = setTimeout(position, 100); });
applySettings(settings);
post('ready');
emitMetadata();
