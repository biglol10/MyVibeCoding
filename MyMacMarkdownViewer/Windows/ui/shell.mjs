import { buildOutline, normalizeOutlineQuery, outlineSignature, visibleOutline } from "./outline.mjs";
import {
  findFileEntry,
  isPathWithinRoot,
  knownAncestorDirectories,
  sameTreePath,
} from "./file-reveal.mjs";

const $ = (s) => document.querySelector(s);
const frame = $("#editor-frame");
const api = window.desktop;
let state = {
  doc: {
    path: null,
    sessionID: "",
    revision: 0,
    dirty: false,
    conflict: null,
    composing: false,
  },
  root: null,
  entries: [],
    settings: {
    theme: "dark",
    fontSize: 17,
    lineHeight: 1.7,
    contentWidth: 800,
    fontFamily: "system",
    remoteImages: false,
    autosave: true,
    },
  resolvedTheme: "dark",
  recoveryCount: 0,
  status: "",
};
let selectedPath = null,
  expanded = new Set(),
  metadata = { headings: [], characters: 0, words: 0, lines: 0 },
  currentHeading = -1,
  contextMenuPath = null;
let outlineState = {
  query: "",
  collapsed: new Set(),
  headingSignature: "",
};
let outlineNodes = [];
let searchState = null,
  searchScope = null,
  searchRequest = 0,
  reviewState = null,
  reviewApplied = false,
  pendingActions = 0,
  mainBusy = false,
  revealInProgress = false,
  revealGeneration = 0,
  frameReady = false;

function text(node, value) {
  node.textContent = value == null ? "" : String(value);
  return node;
}
function el(tag, options = {}, children = []) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(options)) {
    if (key === "class") node.className = value;
    else if (key === "text") text(node, value);
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else if (value != null) node.setAttribute(key, value);
  }
  for (const child of children) node.append(child);
  return node;
}
function basename(path) {
  return (
    String(path || "")
      .split(/[\\/]/)
      .pop() || "새 문서"
  );
}
function outcomeLabel(status) {
  return ({ saved: "저장됨", skipped: "건너뜀", failed: "실패", conflict: "충돌", unchanged: "변경 없음", notAttempted: "미적용", unavailable: "읽기 불가" })[status] || "처리 결과";
}
let noticeTimer;
function showNotice(message, error = true) {
  clearTimeout(noticeTimer);
  const n = $("#notice");
  const display = error && message && !/[가-힣]/.test(String(message))
    ? "요청을 완료하지 못했습니다. 다시 시도하세요."
    : message;
  text(n, display);
  n.hidden = !display;
  n.dataset.kind = error ? "error" : "success";
  if (display && !error) noticeTimer = setTimeout(() => { n.hidden = true; }, 5000);
}
function invoke(action, payload = {}) {
  if (!api?.invoke) {
    showNotice("데스크톱 연결을 불러오지 못했습니다.");
    return Promise.resolve({ ok: false, error: "bridge unavailable" });
  }
  return api
    .invoke(action, payload)
    .catch((error) => ({ ok: false, error: error?.message || String(error) }));
}
async function perform(action, payload = {}, { quiet = false } = {}) {
  if (!quiet) {
    pendingActions += 1;
    setBusy();
  }
  const result = await invoke(action, payload);
  if (!quiet) {
    pendingActions = Math.max(0, pendingActions - 1);
    setBusy();
  }
  if (!result?.ok && !quiet)
    showNotice(result?.error || "작업을 완료하지 못했습니다.");
  return result;
}
function setBusy() {
  const blocked = pendingActions > 0 || mainBusy;
  document
    .querySelectorAll("[data-action],[data-file-action],[data-theme],#apply-replace,#reset-search-scope")
    .forEach((b) => {
      if (b.dataset.action !== "settings") b.disabled = blocked;
    });
  updateRevealCurrentButton();
}
function sendEditor(message) {
  const isOpen = message?.type === "open";
  const withSession = isOpen
    ? message
    : {
        ...message,
        documentID: message.documentID ?? (state.doc.path || "untitled"),
        sessionID: message.sessionID ?? state.doc.sessionID,
      };
  if (frame.contentWindow)
    frame.contentWindow.postMessage(
      { kind: "host-receive", message: withSession },
      "app://editor",
    );
}
function renderHeader() {
  for (const key of ["focusMode", "typewriterMode"]) {
    document.querySelectorAll(`[data-action="${key}"]`).forEach(button => button.setAttribute("aria-checked", String(!!state.settings[key])));
  }
  document.documentElement.dataset.theme = state.resolvedTheme || state.settings.theme;
  for (const button of document.querySelectorAll("[data-theme]"))
    button.setAttribute("aria-checked", String(button.dataset.theme === state.settings.theme));
  $("#doc-title").title = state.doc.path || "새 문서";
  text($("#doc-title"), basename(state.doc.path));
  text(
    $("#root-label"),
    state.root ? basename(state.root) : "폴더를 열어 시작",
  );
  text(
    $("#save-state"),
    state.doc.conflict
      ? "충돌 감지"
      : state.doc.dirty
        ? "저장 안 됨"
        : "저장됨",
  );
  $("#save-state").style.color = state.doc.conflict
    ? "var(--warning)"
    : state.doc.dirty
      ? "var(--warning)"
      : "var(--muted)";
  text($("#mode"), state.sourceMode ? "원문 모드" : "읽기/편집");
  updateRevealCurrentButton();
}
function revealUnavailableReason() {
  const docPath = state.doc?.path;
  if (!state.root) return "먼저 폴더를 열어 주세요.";
  if (!docPath) return "저장된 문서가 없습니다.";
  if (!isPathWithinRoot(docPath, state.root))
    return "열린 문서가 현재 폴더 안에 없습니다.";
  if (!findFileEntry(docPath, state.entries))
    return "현재 문서가 파일 목록에 없습니다. 새로 고침 후 다시 시도해 주세요.";
  return "";
}
function updateRevealCurrentButton() {
  const button = $("#reveal-current");
  if (!button) return;
  const reason = revealInProgress
    ? "현재 문서를 확인하고 있습니다."
    : pendingActions > 0 || mainBusy
      ? "진행 중인 작업이 끝난 뒤 다시 시도해 주세요."
      : revealUnavailableReason();
  button.disabled = !!reason;
  button.title = reason ? "현재 문서 찾기: " + reason : "현재 문서 찾기";
  if (reason) button.setAttribute("aria-description", reason);
  else button.removeAttribute("aria-description");
}
function pathDepth(entry) {
  return Number.isFinite(entry.depth)
    ? entry.depth
    : Math.max(0, String(entry.path).split(/[\\/]/).length - 1);
}
function renderTree() {
  const tree = $("#tree"),
    previous = document.activeElement?.dataset?.path;
  tree.replaceChildren();
  const entries = state.entries || [];
  const dirs = new Set(entries.filter((x) => x.directory).map((x) => x.path));
  for (const entry of entries) {
    let visible = true;
    let parent = String(entry.path).replace(/[\\/][^\\/]+$/, "");
    while (parent && parent !== entry.path) {
      if (dirs.has(parent) && !expanded.has(parent)) {
        visible = false;
        break;
      }
      const next = parent.replace(/[\\/][^\\/]+$/, "");
      if (next === parent) break;
      parent = next;
    }
    if (!visible) continue;
    const item = el("button", {
      class: `tree-item ${entry.directory ? "directory" : ""}`,
      role: "treeitem",
      "aria-selected": String(selectedPath === entry.path),
      "aria-expanded": entry.directory
        ? String(expanded.has(entry.path))
        : null,
      "data-path": entry.path,
      style: `padding-left:${8 + pathDepth(entry) * 14}px`,
      title: entry.path,
    });
    const caret = el("span", {
      class: "caret",
      text: entry.directory ? (expanded.has(entry.path) ? "⌄" : "›") : "",
    });
    item.append(
      caret,
      el("span", { class: "name", text: entry.name || basename(entry.path) }),
    );
    item.addEventListener("click", () => { selectEntry(entry); if (!entry.directory) openPath(entry.path); });
    item.addEventListener("contextmenu", (event) => {
      event.preventDefault();
      selectContextEntry(entry, event.clientX, event.clientY);
    });

    tree.append(item);
  }
  if (!entries.length) {
    tree.append(el("p", { text: state.root ? "아직 문서가 없습니다. 폴더 메뉴에서 새 문서를 만들어 보세요." : "문서가 있는 폴더를 열면 파일을 여기서 탐색할 수 있습니다.", class: "empty" }));
    if (!state.root) tree.append(el("button", { text: "폴더 열기…", class: "empty-open", "data-action": "chooseFolder" }));
  }
  if (previous)
    tree.querySelector(`[data-path="${CSS.escape(previous)}"]`)?.focus();
}
function selectEntry(entry) {
  selectedPath = entry.path;
  if (entry.directory) {
    if (expanded.has(entry.path)) expanded.delete(entry.path);
    else expanded.add(entry.path);
  }
  renderTree();
}
function contextMenu() { return $("#item-context-menu"); }
function closeContextMenu({ restoreFocus = false } = {}) {
  const menu = contextMenu();
  if (menu.hidden) return;
  const path = contextMenuPath;
  menu.hidden = true;
  menu.replaceChildren();
  contextMenuPath = null;
  if (restoreFocus && path)
    document.querySelector(`.tree-item[data-path="${CSS.escape(path)}"]`)?.focus();
}
function addContextAction(menu, label, action, { destructive = false } = {}) {
  const button = el("button", { text: label, type: "button", "data-file-action": action, role: "menuitem" });
  if (destructive) button.classList.add("destructive");
  menu.append(button);
}
function addContextDivider(menu) { menu.append(el("hr", { role: "separator" })); }
function showContextMenu(entry, clientX, clientY) {
  const menu = contextMenu();
  for (const dropdown of document.querySelectorAll("details.dropdown[open]")) dropdown.open = false;
  menu.replaceChildren();
  contextMenuPath = entry.path;
  if (entry.directory) {
    addContextAction(menu, "폴더 열기", "openFolder");
    addContextAction(menu, "여기에 새 문서…", "createFile");
    addContextAction(menu, "여기에 새 폴더…", "createFolder");
    addContextDivider(menu);
  } else {
    addContextAction(menu, "열기", "open");
    addContextAction(menu, "여기에 새 문서…", "createFile");
    addContextAction(menu, "여기에 새 폴더…", "createFolder");
  }
  addContextAction(menu, "복제", "duplicate");
  addContextAction(menu, "이름 변경…", "rename");
  addContextAction(menu, "이동…", "move");
  addContextAction(menu, "이 폴더에서 검색", "searchScope");
  addContextAction(menu, "탐색기에서 보기", "reveal");
  addContextAction(menu, "경로 복사", "copyPath");
  addContextAction(menu, "정보", "info");
  addContextDivider(menu);
  addContextAction(menu, "휴지통으로 보내기…", "trash", { destructive: true });
  menu.hidden = false;
  const padding = 8;
  const { width, height } = menu.getBoundingClientRect();
  menu.style.left = `${Math.max(padding, Math.min(clientX, innerWidth - width - padding))}px`;
  menu.style.top = `${Math.max(padding, Math.min(clientY, innerHeight - height - padding))}px`;
  setBusy();
  menu.querySelector("button:not(:disabled)")?.focus();
}
function selectContextEntry(entry, clientX, clientY) {
  selectedPath = entry.path;
  renderTree();
  showContextMenu(entry, clientX, clientY);
}
async function openPath(path) {
  const r = await perform("open", { path });
  if (r.ok && r.value) applyState(r.value);
}
function resetOutlineState() {
  outlineState = { query: "", collapsed: new Set(), headingSignature: "" };
  outlineNodes = [];
  const input = $("#outline-query");
  if (input) input.value = "";
}
function jumpToHeading(heading) {
  sendEditor({
    type: "jump",
    documentID: state.doc.path || "untitled",
    sessionID: state.doc.sessionID,
    from: heading.from,
    to: heading.from,
  });
}
function updateOutlineCurrent(previousHeading = -1) {
  if (previousHeading === currentHeading) return;
  for (const index of [previousHeading, currentHeading]) {
    if (index < 0) continue;
    const button = document.querySelector(`#outline [data-outline-index="${index}"]`);
    if (!button) continue;
    const active = index === currentHeading;
    button.classList.toggle("current", active);
    if (active) button.setAttribute("aria-current", "location");
    else button.removeAttribute("aria-current");
  }
}
function renderOutline({ restoreToggleID = null } = {}) {
  const target = $("#outline");
  target.replaceChildren();
  const query = normalizeOutlineQuery(outlineState.query);
  const canCollapse = !query && outlineNodes.some(node => node.children.length);
  $("#clear-outline-search").hidden = !query;
  $("#collapse-outline").disabled = !canCollapse;
  $("#expand-outline").disabled = !canCollapse;
  if (!metadata.headings?.length) {
    target.append(
      el("p", { text: "문서의 제목이 여기에 표시됩니다.", class: "empty" }),
    );
    return;
  }
  const visible = visibleOutline(outlineNodes, outlineState);
  if (!visible.length) {
    target.append(el("p", { text: "일치하는 제목이 없습니다.", class: "empty" }));
    return;
  }
  for (const heading of visible) {
    const row = el("div", { class: "outline-row", style: `--indent:${heading.depth}` });
    if (heading.children.length) {
      const expanded = !!query || !outlineState.collapsed.has(heading.id);
      const control = el("button", {
        class: "outline-toggle",
        type: "button",
        "data-outline-toggle-id": heading.id,
        "aria-label": `${heading.title || "제목 없음"} ${expanded ? "접기" : "펼치기"}`,
        "aria-expanded": String(expanded),
        text: expanded ? "⌄" : "›",
      });
      control.disabled = !!query;
      control.addEventListener("click", () => {
        if (outlineState.collapsed.has(heading.id)) outlineState.collapsed.delete(heading.id);
        else outlineState.collapsed.add(heading.id);
        renderOutline({ restoreToggleID: heading.id });
      });
      row.append(control);
    } else row.append(el("span", { class: "outline-toggle-spacer", "aria-hidden": "true" }));
    const button = el("button", {
      class: `outline-link ${heading.index === currentHeading ? "current" : ""}`,
      type: "button",
      "data-outline-index": heading.index,
      "data-outline-from": heading.from,
      "aria-current": heading.index === currentHeading ? "location" : null,
      title: heading.title || "제목 없음",
      text: heading.title || "제목 없음",
    });
    button.addEventListener("click", () => jumpToHeading(heading));
    row.append(button);
    target.append(row);
  }
  if (restoreToggleID)
    queueMicrotask(() => [...target.querySelectorAll("[data-outline-toggle-id]")]
      .find(node => node.dataset.outlineToggleId === restoreToggleID)?.focus());
}
function renderStatus() {
  text(
    $("#position"),
    `${metadata.lines || 0}줄 · ${metadata.characters || 0}자 · ${metadata.words || 0}단어`,
  );
}
function isState(value) {
  return (
    !!value &&
    typeof value === "object" &&
    ("doc" in value ||
      "entries" in value ||
      "root" in value ||
      "settings" in value)
  );
}
function sameTree(left = [], right = []) {
  return (
    left.length === right.length &&
    left.every(
      (entry, index) =>
        entry.path === right[index]?.path &&
        entry.name === right[index]?.name &&
        entry.directory === right[index]?.directory &&
        entry.depth === right[index]?.depth,
    )
  );
}
function applyState(next) {
  if (!isState(next)) return;
  if (typeof next.busy === "boolean") mainBusy = next.busy;
  const previousPath = state.doc.path, previousSessionID = state.doc.sessionID, previousRoot = state.root;
  const entriesChanged = Array.isArray(next.entries) && !sameTree(state.entries, next.entries);
  state = {
    ...state,
    ...next,
    doc: { ...state.doc, ...(next.doc || {}) },
    settings: { ...state.settings, ...(next.settings || {}) },
  };
  if (next.root !== undefined && next.root !== previousRoot) resetSearchScope({ silent: true });
  if (contextMenuPath && !(state.entries || []).some((entry) => entry.path === contextMenuPath))
    closeContextMenu();
  if (next.doc?.path && next.doc.path !== previousPath) {
    selectedPath = next.doc.path;
    revealPath(next.doc.path);
  }
  if (state.doc.path !== previousPath || state.doc.sessionID !== previousSessionID) {
    metadata = { headings: [], characters: 0, words: 0, lines: 0 };
    currentHeading = -1;
    resetOutlineState();
    renderOutline();
    renderStatus();
  }
  setBusy();
  renderHeader();
  // Main-state updates also arrive for keystrokes, metadata, and notices.
  // Keep the focused tree and its nodes intact unless its contents or selection changed.
  if (entriesChanged || state.doc.path !== previousPath) renderTree();
  renderSearchScope();
  if ($("#quick-open-dialog")?.open) $("#quick-open-dialog")._quickDraw?.();
}
function revealPath(path) {
  const directories = new Set((state.entries || []).filter((entry) => entry.directory).map((entry) => entry.path));
  let parent = String(path).replace(/[\\/][^\\/]+$/, "");
  while (parent) {
    if (directories.has(parent)) expanded.add(parent);
    const next = parent.replace(/[\\/][^\\/]+$/, "");
    if (next === parent) break;
    parent = next;
  }
}
function scrollTreeRowIntoView(row) {
  const tree = $("#tree");
  const treeRect = tree.getBoundingClientRect();
  const top = treeRect.top + tree.clientTop;
  const bottom = top + tree.clientHeight;
  const rowRect = row.getBoundingClientRect();
  if (rowRect.top < top) tree.scrollTop -= top - rowRect.top;
  else if (rowRect.bottom > bottom) tree.scrollTop += rowRect.bottom - bottom;
}
function revealRequestMatches(request) {
  return (
    sameTreePath(state.root, request.root) &&
    state.doc?.sessionID === request.sessionID &&
    sameTreePath(state.doc?.path, request.path)
  );
}
async function revealCurrentDocument() {
  if (revealInProgress) return;
  const reason = revealUnavailableReason();
  if (reason) {
    showNotice(reason);
    return;
  }
  const request = {
    generation: ++revealGeneration,
    root: state.root,
    path: state.doc.path,
    sessionID: state.doc.sessionID,
  };
  revealInProgress = true;
  updateRevealCurrentButton();
  try {
    // This targeted check validates the current path without rescanning the root.
    const checked = await invoke("info", { path: request.path });
    if (request.generation !== revealGeneration || !revealRequestMatches(request))
      return;
    if (!checked?.ok || !checked.value || checked.value.directory) {
      showNotice("현재 문서를 확인할 수 없습니다. 파일이 이동되었거나 삭제되었는지 확인해 주세요.");
      return;
    }
    const entry = findFileEntry(request.path, state.entries);
    const ancestors = entry
      ? knownAncestorDirectories(entry.path, state.root, state.entries)
      : null;
    if (!entry || !ancestors) {
      showNotice("현재 문서의 파일 목록이 바뀌었습니다. 새로 고침한 뒤 다시 시도해 주세요.");
      return;
    }

    const previousSelection = selectedPath;
    const addedAncestors = ancestors.filter((path) => !expanded.has(path));
    for (const path of ancestors) expanded.add(path);
    selectedPath = entry.path;
    renderTree();
    const row = [...$("#tree").querySelectorAll(".tree-item")]
      .find((item) => sameTreePath(item.dataset.path, entry.path));
    if (!row) {
      for (const path of addedAncestors) expanded.delete(path);
      selectedPath = previousSelection;
      renderTree();
      showNotice("현재 문서를 파일 목록에서 표시할 수 없습니다. 새로 고침한 뒤 다시 시도해 주세요.");
      return;
    }
    scrollTreeRowIntoView(row);
    showNotice("현재 문서를 파일 목록에서 찾았습니다.", false);
  } catch {
    if (request.generation === revealGeneration && revealRequestMatches(request))
      showNotice("현재 문서를 확인할 수 없습니다. 파일이 이동되었거나 삭제되었는지 확인해 주세요.");
  } finally {
    if (request.generation === revealGeneration) {
      revealInProgress = false;
      updateRevealCurrentButton();
    }
  }
}
function toggleSidebar(force) {
  const hidden = force === undefined ? !$(".shell").classList.contains("sidebar-hidden") : !force;
  $(".shell").classList.toggle("sidebar-hidden", hidden);
  for (const b of document.querySelectorAll("[data-action=toggleSidebar]")) b.setAttribute("aria-expanded", String(!hidden));
}
function switchTab(name) {
  toggleSidebar(true);
  document
    .querySelectorAll("[data-tab]")
    .forEach((b) =>
      b.setAttribute("aria-selected", String(b.dataset.tab === name)),
    );
  document
    .querySelectorAll(".tab-panel")
    .forEach((p) => (p.hidden = p.id !== `${name}-panel`));
  if (name === "search") $("#search-query").focus();
}
function requestItem({ title, label, initial = "", placeholder = "", validate, options, onSubmit }) {
  const dialog = $("#item-dialog"), form = $("#item-form"), input = $("#item-input"), select = $("#item-select"), selectLabel = $("#item-select-label"), help = $("#item-help"), error = $("#item-error");
  text($("#item-dialog-title"), title);
  text($("#item-label").childNodes[0], label);
  input.value = initial;
  input.placeholder = placeholder;
  const usingOptions = Array.isArray(options);
  $("#item-label").hidden = usingOptions;
  selectLabel.hidden = !usingOptions;
  select.replaceChildren();
  if (usingOptions) {
    for (const option of options) select.append(el("option", { value: option.value, text: option.label }));
    select.value = initial || options[0]?.value || "";
    text(help, select.value);
    help.hidden = false;
  } else help.hidden = true;
  error.hidden = true;
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      form.removeEventListener("submit", submit);
      $("#item-cancel").removeEventListener("click", cancel);
      dialog.removeEventListener("cancel", cancelEvent);
      dialog.removeEventListener("close", close);
      resolve(value);
    };
    const cancel = () => { finish(null); dialog.close(); };
    const cancelEvent = (event) => { event.preventDefault(); cancel(); };
    const close = () => finish(null);
    const submit = async (event) => {
      event.preventDefault();
      const value = (usingOptions ? select.value : input.value).trim();
      const message = !value ? "값을 입력하세요." : validate?.(value);
      if (message) { text(error, message); error.hidden = false; (usingOptions ? select : input).focus(); return; }
      const result = await onSubmit?.(value);
      if (result !== true) {
        text(error, typeof result === "string" && /[가-힣]/.test(result) ? result : "작업을 완료하지 못했습니다. 값을 확인해 다시 시도하세요.");
        error.hidden = false;
        (usingOptions ? select : input).focus();
        return;
      }
      showNotice("", false);
      finish(value);
      dialog.close();
    };
    form.addEventListener("submit", submit);
    $("#item-cancel").addEventListener("click", cancel);
    dialog.addEventListener("cancel", cancelEvent);
    dialog.addEventListener("close", close);
    dialog.showModal();
    select.onchange = () => text(help, select.value);
    requestAnimationFrame(() => { const control = usingOptions ? select : input; control.focus(); if (!usingOptions) input.select(); });
  });
}
function nameError(value) {
  return /[\\/]/.test(value) ? "이름에는 슬래시를 사용할 수 없습니다." : null;
}
function quickOpen() {
  let dialog = $("#quick-open-dialog");
  if (!dialog) {
    dialog = el("dialog", { id: "quick-open-dialog" });
    const form = el("form"),
      input = el("input", {
        type: "search",
        role: "combobox",
        "aria-controls": "quick-open-results",
        "aria-expanded": "false",
        placeholder: "파일 이름 또는 경로 검색",
        "aria-label": "빠른 열기 검색",
        autocomplete: "off",
      }),
      list = el("div", { id: "quick-open-results", class: "quick-list", role: "listbox", "aria-label": "빠른 열기 결과" }),
      close = el("button", { type: "button", text: "닫기" });
    form.append(
      el("h2", { text: "빠른 열기" }),
      input,
      list,
      el("menu", {}, [close]),
    );
    dialog.append(form);
    document.body.append(dialog);
    let matches = [], selected = 0, quickSelectedPath = null;
    const relativePath = (item) => {
      const root = state.root;
      if (!root || !item.path.startsWith(root)) return item.path;
      return item.path.slice(root.length).replace(/^[\\/]+/, "") || item.name;
    };
    const openSelected = () => {
      const item = matches[selected];
      if (!item) return;
      dialog.close();
      void openPath(item.path);
    };
    const draw = ({ reveal = false, resetScroll = false } = {}) => {
      const scrollTop = resetScroll ? 0 : list.scrollTop;
      list.replaceChildren();
      const q = input.value.toLocaleLowerCase();
      matches = (state.entries || [])
        .filter(
          (x) =>
            !x.directory &&
            `${x.name} ${relativePath(x)}`.toLocaleLowerCase().includes(q),
        )
        .slice(0, 30);
      const selectedIndex = matches.findIndex(item => item.path === quickSelectedPath);
      selected = selectedIndex >= 0 ? selectedIndex : 0;
      quickSelectedPath = matches[selected]?.path || null;
      for (const [index, item] of matches.entries()) {
        const b = el("button", {
          id: `quick-open-option-${index}`,
          type: "button",
          class: "quick-result",
          role: "option",
          "aria-selected": String(index === selected),
        }, [el("strong", { text: item.name }), el("span", { text: relativePath(item) })]);
        b.addEventListener("click", () => {
          selected = index;
          quickSelectedPath = item.path;
          openSelected();
        });
        list.append(b);
      }
      if (!list.childElementCount)
        list.append(el("p", { text: "일치하는 파일이 없습니다." }));
      list.scrollTop = scrollTop;
      const activeID = matches[selected] ? `quick-open-option-${selected}` : null;
      if (activeID) input.setAttribute("aria-activedescendant", activeID);
      else input.removeAttribute("aria-activedescendant");
      if (reveal && activeID) document.getElementById(activeID)?.scrollIntoView({ block: "nearest" });
    };
    input.addEventListener("input", () => { selected = 0; quickSelectedPath = null; draw({ resetScroll: true }); });
    let composing = false, lastCompositionKey = false;
    input.addEventListener("compositionstart", () => { composing = true; });
    input.addEventListener("compositionend", () => { composing = false; });
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      if (composing || lastCompositionKey) return;
      openSelected();
    });
    close.addEventListener("click", () => dialog.close());
    input.addEventListener("keydown", (event) => {
      if (composing || event.isComposing || event.keyCode === 229) {
        lastCompositionKey = true;
        return;
      }
      lastCompositionKey = false;
      if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
      event.preventDefault();
      if (!matches.length) return;
      selected = (selected + (event.key === "ArrowDown" ? 1 : matches.length - 1)) % matches.length;
      quickSelectedPath = matches[selected]?.path || null;
      draw({ reveal: true });
    });
    dialog.addEventListener("close", () => {
      input.value = "";
      selected = 0;
      quickSelectedPath = null;
      composing = false;
      lastCompositionKey = false;
      draw();
      input.setAttribute("aria-expanded", "false");
    });
    dialog._quickReset = () => { input.value = ""; selected = 0; quickSelectedPath = null; composing = false; lastCompositionKey = false; draw({ resetScroll: true }); };
    dialog._quickDraw = draw;
  }
  dialog._quickReset();
  dialog.showModal();
  dialog.querySelector("input").setAttribute("aria-expanded", "true");
  dialog.querySelector("input").focus();
}
async function fileAction(action, targetPath = selectedPath) {
  const entry = (state.entries || []).find((x) => x.path === targetPath);
  if (action === "open") {
    if (entry && !entry.directory) await openPath(entry.path);
    return;
  }
  if (action === "reveal") {
    await perform("reveal", { path: targetPath });
    return;
  }
  if (action === "openFolder") {
    await perform("openFolder", { path: targetPath });
    return;
  }
  if (action === "copyPath") {
    await perform("copyPath", { path: targetPath });
    return;
  }
  if (action === "info") {
    const r = await perform("info", { path: targetPath });
    if (!r.ok) return;
    const item = r.value;
    const lines = [
      ["이름", item.name], ["위치", item.path], ["종류", item.directory ? "폴더" : "Markdown 문서"],
      ...(item.size == null ? [] : [["크기", new Intl.NumberFormat("ko-KR").format(item.size) + " 바이트"]]),
      ["수정", new Date(item.modified).toLocaleString("ko-KR")], ["생성", new Date(item.created).toLocaleString("ko-KR")],
    ];
    $("#item-info").replaceChildren(...lines.map(([label, value]) => el("p", { text: `${label}: ${value}` })));
    $("#item-info-dialog").showModal();
    return;
  }
  if (action === "searchScope") {
    const nextScope = entry?.directory ? entry.path : targetPath ? String(targetPath).replace(/[\\/][^\\/]+$/, "") : state.root;
    if (nextScope !== searchScope) {
      searchScope = nextScope;
      invalidateSearch();
    }
    switchTab("search");
    $("#search-query").focus();
    renderSearchScope();
    showNotice(`검색 범위: ${searchScope}`, false);
    return;
  }
  if (action === "duplicate") {
    const r = await perform("duplicate", { path: targetPath });
    if (r.ok) {
      selectedPath = r.value;
      await perform("refresh", {}, { quiet: true });
    }
    return;
  }
  if (action === "createFile" || action === "createFolder") {
    const parent = entry?.directory
      ? entry.path
      : targetPath
        ? String(targetPath).replace(/[\\/][^\\/]+$/, "")
        : state.root;
    await requestItem({
      title: action === "createFile" ? "새 Markdown 문서" : "새 폴더",
      label: action === "createFile" ? "파일 이름" : "폴더 이름",
      initial: action === "createFile" ? "새 문서.md" : "새 폴더",
      validate: nameError,
      onSubmit: async (name) => {
        const r = await perform("create", { parent, name, directory: action === "createFolder" }, { quiet: true });
        if (r.ok) { applyState(r.value); return true; }
        return r.error;
      },
    });
    return;
  }
  if (!entry) {
    showNotice("먼저 파일이나 폴더를 선택하세요.");
    return;
  }
  if (action === "rename") {
    await requestItem({ title: "이름 변경", label: "새 이름", initial: entry.name || basename(entry.path), validate: nameError,
      onSubmit: async (name) => { const r = await perform("move", { source: entry.path, parent: String(entry.path).replace(/[\\/][^\\/]+$/, ""), name }, { quiet: true }); if (r.ok) { applyState(r.value); return true; } return r.error; } });
    return;
  }
  if (action === "move") {
    const directories = [state.root, ...(state.entries || []).filter((item) => item.directory).map((item) => item.path)].filter(Boolean);
    const options = [...new Set(directories)].map((path) => ({ value: path, label: path === state.root ? "폴더 루트" : path.startsWith(`${state.root}/`) || path.startsWith(`${state.root}\\`) ? path.slice(state.root.length + 1) : path }));
    await requestItem({ title: "항목 이동", label: "이동할 폴더", initial: state.root || "", options,
      onSubmit: async (parent) => { const r = await perform("move", { source: entry.path, parent, name: entry.name || basename(entry.path) }, { quiet: true }); if (r.ok) { applyState(r.value); return true; } return r.error; } });
    return;
  }
  if (action === "trash") {
    const r = await perform("trash", { path: entry.path });
    if (r.ok && r.value) {
      selectedPath = null;
      applyState(r.value);
    }
  }
}
async function runSearch(event) {
  event?.preventDefault();
  const query = $("#search-query").value;
  if (!query) return;
  invalidateSearch();
  const request = ++searchRequest;
  const scope = searchScope || state.root;
  const caseSensitive = $("#case-sensitive").checked;
  const r = await perform("search", {
    query,
    caseSensitive,
    root: scope,
  });
  if (r.ok && r.value && request === searchRequest && scope === (searchScope || state.root) && query === $("#search-query").value && caseSensitive === $("#case-sensitive").checked) {
    searchState = r.value;
    renderSearch();
  }
}
function invalidateSearch() {
  searchRequest++;
  searchState = reviewState = null;
  if ($("#replace-dialog")?.open) $("#replace-dialog").close();
  renderSearch();
}
function resetSearchScope({ silent = false } = {}) {
  searchScope = null;
  invalidateSearch();
  renderSearchScope();
  if (!silent) showNotice("검색 범위를 전체 작업 폴더로 바꿨습니다.", false);
}
function renderSearchScope() {
  const label = $("#search-scope"), reset = $("#reset-search-scope");
  if (!label || !reset) return;
  const scope = searchScope || state.root;
  text(label, scope ? (searchScope ? `검색 범위: ${scope}` : "검색 범위: 전체 작업 폴더") : "폴더를 열어 검색할 수 있습니다.");
  reset.hidden = !searchScope;
}
function renderSearch() {
  const target = $("#search-results");
  target.replaceChildren();
  const data = searchState;
  if (!data) return;
  if (data.issues?.length)
    target.append(
      el("p", { class: "notice-inline", text: data.issues.join("\n") }),
    );
  if (!data.files?.length) {
    target.append(
      el("p", {
        text: data.cancelled
          ? "찾기를 중단했습니다."
          : "일치하는 내용이 없습니다.",
      }),
    );
    return;
  }
  const controls = el("div", { class: "replace-controls" });
  const replace = el("input", {
    placeholder: "바꿀 내용",
    "aria-label": "바꿀 내용",
  });
  const review = el("button", { text: "바꾸기 검토" });
  review.addEventListener("click", () => beginReview(replace.value));
  controls.append(replace, review);
  target.append(controls);
  data.files.forEach((file) => {
    const d = el("details", { class: "search-file", open: "open" });
    d.append(
      el("summary", {
        text: `${basename(file.path)} · ${file.matches.length}곳`,
      }),
    );
    file.matches.forEach((match) => {
      const b = el("button", {
        class: "match",
        text: `${match.line}:${match.column}  ${match.snippet}`,
      });
      b.addEventListener("click", () =>
        openPath(file.path).then(() =>
          sendEditor({
            type: "jump",
            documentID: state.doc.path,
            sessionID: state.doc.sessionID,
            from: match.from,
            to: match.to,
          }),
        ),
      );
      d.append(b);
    });
    target.append(d);
  });
  if (data.truncated)
    target.append(el("p", { text: "결과가 많아 일부만 표시했습니다." }));
}
async function beginReview(replacement) {
  if (!searchState) return;
  const r = await perform("reviewReplace", {
    searchID: searchState.id,
    replacement,
  });
  if (!r.ok) return;
  reviewState = r.value;
  renderReview();
  $("#replace-dialog").showModal();
}
function renderReview() {
  reviewApplied = false;
  text($("#replace-dialog h2"), "바꾸기 검토");
  $("#replace-dialog button[value=cancel]").hidden = false;
  $("#apply-replace").textContent = "선택한 파일 바꾸기";
  const target = $("#replace-files"),
    summary = $("#replace-summary");
  target.replaceChildren();
  text(
    summary,
    `“${reviewState.query}” → “${reviewState.replacement}” 변경 내용을 확인하세요.`,
  );
  for (const file of reviewState.files || []) {
    const wrap = el("section", { class: "replace-file" });
    const check = el("input", {
      type: "checkbox",
      checked: "checked",
      "data-path": file.path,
      "aria-label": `${basename(file.path)} 적용`,
    });
    const identity = el("div", { class: "review-identity" }, [
      el("strong", { text: basename(file.path) }),
      el("span", { class: "review-path", text: file.path }),
    ]);
    const header = el("header", {}, [
      check,
      identity,
      el("span", { text: `${file.matches?.length || 0}곳` }),
    ]);
    const diff = el("div", { class: "diff" }, [
      el("section", { class: "diff-side" }, [el("h3", { text: "변경 전" }), el("pre", { text: file.before || "" })]),
      el("section", { class: "diff-side" }, [el("h3", { text: "변경 후" }), el("pre", { text: file.after || "" })]),
    ]);
    wrap.append(header, diff);
    target.append(wrap);
  }
  $("#replace-outcomes").replaceChildren();
}
async function applyReview() {
  if (reviewApplied) {
    $("#replace-dialog").close();
    return;
  }
  const selected = [
    ...$("#replace-files").querySelectorAll("input:checked"),
  ].map((x) => x.dataset.path);
  if (!selected.length) {
    const out = $("#replace-outcomes");
    out.replaceChildren(el("p", { class: "dialog-alert", role: "alert", text: "적용할 파일을 선택하세요." }));
    return;
  }
  const r = await perform("applyReplace", {
    reviewID: reviewState.id,
    selected,
  });
  if (!r.ok) {
    const message = r.error && /[가-힣]/.test(String(r.error)) ? r.error : "파일 바꾸기를 완료하지 못했습니다. 내용을 확인한 뒤 다시 시도하세요.";
    $("#replace-outcomes").replaceChildren(el("p", { class: "dialog-alert", role: "alert", text: message }));
    return;
  }
  const out = $("#replace-outcomes");
  $("#replace-files").replaceChildren();
  out.replaceChildren();
  for (const item of r.value?.outcomes || [])
    out.append(
      el("div", {
        class: `outcome ${["saved", "unchanged"].includes(item.status) ? "" : "outcome-warning"}`,
        text: `${item.path}: ${outcomeLabel(item.status)}${item.message ? ` · ${item.message}` : ""}`,
      }),
    );
  const apply = $("#apply-replace");
  reviewApplied = true;
  text($("#replace-dialog h2"), "바꾸기 결과");
  text($("#replace-summary"), `${r.value?.savedCount || 0}개 파일을 저장했습니다. 아래 파일별 결과를 확인하세요.`);
  $("#replace-dialog button[value=cancel]").hidden = true;
  apply.textContent = "닫기";
  if (r.value?.savedCount) {
    showNotice(`${r.value.savedCount}개 파일에 적용했습니다.`, false);
  } else {
    out.append(el("p", { text: "저장된 파일이 없습니다. 결과를 확인한 뒤 다시 찾기에서 검토하세요." }));
  }
}
async function showRecoveries() {
  const r = await perform("recoveries");
  if (!r.ok) return;
  const list = $("#recovery-list");
  list.replaceChildren();
  if (!r.value?.length)
    list.append(el("p", { text: "복구할 임시본이 없습니다." }));
  for (const recovery of r.value || []) {
    const row = el("div", { class: "recovery-row" }),
      info = el("div", {}, [
        el("strong", { text: basename(recovery.path) }),
        el("span", { text: recovery.date || "" }),
      ]),
      buttons = el("div");
    const restore = el("button", { text: "복원", type: "button" }),
      discard = el("button", { text: "삭제", type: "button" });
    restore.addEventListener("click", async () => {
      const x = await perform("restoreRecovery", { id: recovery.id });
      if (x.ok) {
        $("#recovery-dialog").close();
        if (x.value) applyState(x.value);
      }
    });
    discard.addEventListener("click", async () => {
      const x = await perform("discardRecovery", { id: recovery.id });
      if (x.ok) showRecoveries();
    });
    buttons.append(restore, discard);
    row.append(info, buttons);
    list.append(row);
  }
  $("#recovery-dialog").showModal();
}
function settingsDialog() {
  const s = state.settings;
  $("#set-theme").value = s.theme;
  $("#set-font-size").value = s.fontSize;
  $("#set-line-height").value = s.lineHeight;
  $("#set-content-width").value = s.contentWidth;
  $("#set-font-family").value = s.fontFamily;
  $("#set-remote-images").checked = !!s.remoteImages;
  $("#set-autosave").checked = !!s.autosave;
  $("#set-focus-mode").checked = !!s.focusMode;
  $("#set-typewriter-mode").checked = !!s.typewriterMode;
  $("#settings-dialog").showModal();
}
async function saveSettings() {
  const patch = {
    theme: $("#set-theme").value,
    fontSize: Number($("#set-font-size").value),
    lineHeight: Number($("#set-line-height").value),
    contentWidth: Number($("#set-content-width").value),
    fontFamily: $("#set-font-family").value,
    remoteImages: $("#set-remote-images").checked,
    autosave: $("#set-autosave").checked,
    focusMode: $("#set-focus-mode").checked,
    typewriterMode: $("#set-typewriter-mode").checked,
  };
  const r = await perform("settings", { patch });
  if (r.ok) {
    state.settings = { ...state.settings, ...patch };
    renderHeader();
    $("#settings-dialog").close();
  }
}
window.addEventListener("message", async (event) => {
  if (event.source !== frame.contentWindow || event.origin !== "app://editor")
    return;
  const data = event.data;
  if (!data || typeof data !== "object") return;
  if (data.kind === "editor-ready") {
    frameReady = true;
    const r = await perform("editorEvent", { type: "ready" }, { quiet: true });
    if (!r.ok) showNotice(r.error || "편집기를 준비하지 못했습니다.");
    return;
  }
  if (data.kind === "editor-event") {
    const message = data.message || {};
    if (message.type === "ready") frameReady = true;
    if (message.type === "metadata") {
      const nextSignature = outlineSignature(message.headings || []);
      const headingsChanged = nextSignature !== outlineState.headingSignature;
      if (headingsChanged) {
        outlineState.collapsed.clear();
        outlineState.headingSignature = nextSignature;
        outlineNodes = buildOutline(message.headings || []);
      }
      metadata = { ...metadata, ...message };
      if (headingsChanged) renderOutline();
      renderStatus();
    } else if (message.type === "position") {
      const from = message.visibleFrom ?? 0;
      const previousHeading = currentHeading;
      currentHeading = (metadata.headings || []).reduce(
        (found, h, index) => (h.from <= from ? index : found),
        -1,
      );
      updateOutlineCurrent(previousHeading);
    } else if (message.type === "sourceMode") {
      state.sourceMode = !!message.enabled;
      renderHeader();
    }
    const r = await perform("editorEvent", message, { quiet: true });
    if (!r.ok) showNotice(r.error || "편집 내용을 저장하지 못했습니다.");
    return;
  }
  if (data.kind === "host-result") {
    const r = await perform(
      "editorResult",
      { requestID: data.requestID, result: data.result, error: data.error },
      { quiet: true },
    );
    if (!r.ok) showNotice(r.error || "편집기 요청을 처리하지 못했습니다.");
  }
});
api?.onEvent?.(({ type, payload }) => {
  if (type === "state") applyState(payload);
  else if (type === "editor" || type === "editorMessage") sendEditor(payload);
  else if (type === "editorRequest") {
    if (frame.contentWindow)
      frame.contentWindow.postMessage(
        { kind: "host-request", ...payload },
        "app://editor",
      );
  } else if (type?.startsWith("command:"))
    perform("command", { command: type.slice(8) }, { quiet: true });
  else if (type === "menu") action(payload);
  else if (type === "notice")
    showNotice(typeof payload === "string" ? payload : payload?.message || "");
  else if (
    [
      "new",
      "openDialog",
      "chooseFolder",
      "save",
      "saveAs",
      "refresh",
      "reveal",
      "insertImage",
      "source",
      "settings",
      "recovery",
    ].includes(type)
  )
    action(type);
  else if (type === "error") showNotice(payload?.message || String(payload));
});
async function action(name) {
  if (["focusMode", "typewriterMode"].includes(name)) {
    const patch = { [name]: !state.settings[name] };
    const r = await perform("settings", { patch });
    if (r.ok) { state.settings = { ...state.settings, ...patch }; renderHeader(); }
    return;
  }
  if (typeof name === 'string' && name.startsWith('command:'))
    return perform('command', { command: name.slice(8) === 'search' ? 'find' : name.slice(8) }, { quiet: true });
  if (name === "toggleSidebar") return toggleSidebar();
  if (name === "showOutline") return switchTab("outline");
  if (name === "showFiles") return switchTab("files");
  if (name === "settings") return settingsDialog();
  if (name === "recovery" || name === "recoveries") return showRecoveries();
  if (name === "folderSearch") {
    switchTab("search");
    $("#search-query").focus();
    return;
  }
  if (name === "quickOpen") return quickOpen();
  if (name === "source")
    return perform("command", { command: "source" }, { quiet: true });
  if (
    name === "new" ||
    name === "openDialog" ||
    name === "chooseFolder" ||
    name === "save" ||
    name === "saveAs" ||
    name === "refresh" ||
    name === "reveal" ||
    name === "insertImage" ||
    name === "exportHTML" || name === "exportPDF" || name === "print"
  ) {
    const r = await perform(name);
    if (r.ok && isState(r.value)) applyState(r.value);
  }
}
document.addEventListener("click", (event) => {
  const button = event.target.closest("button");
  if (!button) return;
  const menu = button.closest("details.dropdown");
  if (menu) menu.open = false;
  if (button.dataset.action) action(button.dataset.action);
  if (button.dataset.fileAction) {
    const targetPath = button.closest("#item-context-menu") ? contextMenuPath : selectedPath;
    closeContextMenu();
    fileAction(button.dataset.fileAction, targetPath);
  }
  if (button.dataset.theme) setTheme(button.dataset.theme);
  if (button.dataset.tab) switchTab(button.dataset.tab);
});
$("#reveal-current").addEventListener("click", () => {
  void revealCurrentDocument();
});
$("#search-form").addEventListener("submit", runSearch);
$("#outline-query").addEventListener("input", (event) => {
  outlineState.query = event.target.value;
  renderOutline();
});
$("#clear-outline-search").addEventListener("click", () => {
  outlineState.query = "";
  $("#outline-query").value = "";
  renderOutline();
  $("#outline-query").focus();
});
$("#collapse-outline").addEventListener("click", () => {
  outlineState.collapsed = new Set(outlineNodes.filter(node => node.children.length).map(node => node.id));
  renderOutline();
});
$("#expand-outline").addEventListener("click", () => {
  outlineState.collapsed.clear();
  renderOutline();
});
$("#search-query").addEventListener("input", invalidateSearch);
$("#case-sensitive").addEventListener("change", invalidateSearch);
$("#reset-search-scope").addEventListener("click", () => resetSearchScope());
$("#cancel-search").addEventListener("click", () => {
  invalidateSearch();
  void perform("cancelSearch", {}, { quiet: true });
});
$("#apply-replace").addEventListener("click", (event) => {
  event.preventDefault();
  applyReview();
});
$("#save-settings").addEventListener("click", (event) => {
  event.preventDefault();
  saveSettings();
});
$("#resize").addEventListener("pointerdown", (event) => {
  const start = event.clientX,
    width = $("#sidebar").getBoundingClientRect().width;
  const move = (e) =>
    ($("#sidebar").style.width =
      `${Math.max(220, Math.min(440, width + e.clientX - start))}px`);
  const end = () => {
    window.removeEventListener("pointermove", move);
    window.removeEventListener("pointerup", end);
  };
  window.addEventListener("pointermove", move);
  window.addEventListener("pointerup", end);
});
$("#resize").addEventListener("keydown", (e) => {
  if (!["ArrowLeft", "ArrowRight"].includes(e.key)) return;
  e.preventDefault();
  const now = $("#sidebar").getBoundingClientRect().width;
  $("#sidebar").style.width =
    `${Math.max(220, Math.min(440, now + (e.key === "ArrowLeft" ? -15 : 15)))}px`;
});
for (const dialog of document.querySelectorAll("dialog"))
  dialog.addEventListener("cancel", (event) => {
    if (pendingActions > 0 || mainBusy) event.preventDefault();
  });
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    if (!contextMenu().hidden) {
      e.preventDefault();
      closeContextMenu({ restoreFocus: true });
    } else if ($("#quick-open-dialog")?.open) {
      e.preventDefault();
      $("#quick-open-dialog").close();
    }
    return;
  }
  if (e.key === "ContextMenu" || (e.shiftKey && e.key === "F10")) {
    const item = document.activeElement?.closest?.(".tree-item");
    const entry = (state.entries || []).find((x) => x.path === item?.dataset.path);
    if (entry) {
      e.preventDefault();
      const bounds = item.getBoundingClientRect();
      selectContextEntry(entry, bounds.left + Math.min(24, bounds.width / 2), bounds.bottom);
      return;
    }
  }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") {
    e.preventDefault();
    action("save");
  }
  if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key.toLowerCase() === "f") {
    e.preventDefault();
    action("folderSearch");
  } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "f") {
    e.preventDefault();
    perform("command", { command: "find" }, { quiet: true });
  }
  if ((e.ctrlKey || e.metaKey) && !e.altKey && !e.shiftKey && e.key.toLowerCase() === "p") {
    e.preventDefault();
    quickOpen();
  }
  if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key.toLowerCase() === "m") {
    e.preventDefault();
    action("source");
  }
});
async function setTheme(theme) {
  if (!['dark', 'night', 'light', 'system'].includes(theme) || theme === state.settings.theme) return;
  const r = await perform("settings", { patch: { theme } });
  if (!r.ok) return;
  state.settings = { ...state.settings, theme };
  renderHeader();
}
(async () => {
  const r = await perform("bootstrap", {}, { quiet: true });
  if (r.ok && r.value) applyState(r.value);
  else if (!r.ok) showNotice(r.error || "시작 정보를 불러오지 못했습니다.");
})();

// Native details keep the menus usable by mouse and keyboard without a UI runtime.
document.addEventListener("pointerdown", event => {
  if (!contextMenu().hidden && !contextMenu().contains(event.target)) closeContextMenu();
  for (const menu of document.querySelectorAll("details.dropdown[open]"))
    if (!menu.contains(event.target)) menu.open = false;
});
contextMenu().addEventListener("keydown", event => {
  const buttons = [...contextMenu().querySelectorAll("button:not(:disabled)")];
  const index = buttons.indexOf(document.activeElement);
  if (event.key === "ArrowDown" || event.key === "ArrowUp") {
    event.preventDefault();
    buttons[(index + (event.key === "ArrowDown" ? 1 : buttons.length - 1)) % buttons.length]?.focus();
  }
  if (event.key === "Home" || event.key === "End") {
    event.preventDefault();
    buttons[event.key === "Home" ? 0 : buttons.length - 1]?.focus();
  }
  if (event.key === "Tab") closeContextMenu();
});
window.addEventListener("resize", () => closeContextMenu());
window.addEventListener("scroll", () => closeContextMenu(), true);
for (const menu of document.querySelectorAll("details.dropdown")) {
  menu.addEventListener("toggle", () => {
    if (menu.open) for (const other of document.querySelectorAll("details.dropdown[open]")) if (other !== menu) other.open = false;
  });
  menu.addEventListener("keydown", event => {
    if (event.key === "Escape") { menu.open = false; menu.querySelector("summary").focus(); event.preventDefault(); }
    if (["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) {
      event.preventDefault(); menu.open = true;
      const buttons = [...menu.querySelectorAll("button:not(:disabled)")];
      const index = buttons.indexOf(document.activeElement);
      const next = event.key === "Home" ? 0 : event.key === "End" ? buttons.length-1 : (index + (event.key === "ArrowUp" ? -1 : 1) + buttons.length) % buttons.length;
      buttons[next]?.focus();
    }
  });
}

function updateSettingValues() {
  for (const [id, suffix] of [["font-size", "px"], ["line-height", ""], ["content-width", "px"]]) {
    const input = $("#set-" + id);
    let output = input.parentElement.querySelector("output");
    if (!output) { output = document.createElement("output"); output.htmlFor = input.id; input.parentElement.append(output); }
    output.value = input.value + suffix;
  }
}
for (const input of document.querySelectorAll("#settings-dialog input[type=range]")) input.addEventListener("input", updateSettingValues);
$("#settings-dialog").addEventListener("beforetoggle", updateSettingValues);

window.addEventListener("blur", () => {
  if (document.activeElement === frame) {
    closeContextMenu();
    for (const menu of document.querySelectorAll("details.dropdown[open]")) menu.open = false;
  }
});
frame.addEventListener("focus", () => closeContextMenu());

// Register both bridge directions before the child can emit its one-time ready event.
frame.src = "app://editor/index.html";
