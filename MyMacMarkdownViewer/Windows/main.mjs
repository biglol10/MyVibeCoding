import {
  app,
  BrowserWindow,
  ipcMain,
  protocol,
  net,
  dialog,
  shell,
  Menu,
  nativeTheme,
} from "electron";
import fs from "node:fs/promises";
import { watch as watchFS } from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";
import { randomUUID } from "node:crypto";
import {
  Store,
  decode,
  applyChanges,
  validateWithin,
  validateName,
  scan,
  preview,
  applyPlan,
  listTree,
  create,
  move,
} from "./core.mjs";
import { rebaseMarkdown } from "./editor/rebase.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
protocol.registerSchemesAsPrivileged([
  {
    scheme: "app",
    privileges: {
      standard: true,
      secure: true,
      supportFetchAPI: true,
      corsEnabled: true,
    },
  },
]);
const qaIndex = process.argv.indexOf("--qa-data");
const qaMode = qaIndex >= 0;
if (qaMode) {
  const dir = path.resolve(process.argv[qaIndex + 1] || "");
  if (!dir.startsWith(path.resolve(os.tmpdir()) + path.sep))
    throw Error("QA data must be under the temporary directory.");
  app.setPath("userData", dir);
}
app.setName("MyMarkdownViewer");
if (!app.requestSingleInstanceLock()) app.quit();
let win,
  store,
  doc,
  root = null,
  entries = [],
  recoveryCount = 0,
  busy = false,
  closing = false,
  editorReady = false;
let status = "",
  autoTimer,
  recoveryTimer,
  watchTimer,
  rootWatcher,
  documentWatcher,
  refreshTimer,
  searchController,
  searchReport,
  review;
let recoveryChain = Promise.resolve();
let externalCheckInFlight = false,
  externalCheckPending = false,
  externalCheckForce = false,
  treeVersion = 0,
  publishedTreeVersion = -1;
let fileGrants = new Set(),
  folderGrants = new Set();
let settings = {
  theme: "dark",
  fontSize: 17,
  lineHeight: 1.7,
  contentWidth: 800,
  fontFamily: "system",
  remoteImages: false,
  autosave: true,
};
const requests = new Map();
const welcome =
  "# 조용한 문서 공간\n\n문서나 폴더를 열어 시작하세요. 내용은 원래 위치의 Markdown 파일로 보관됩니다.\n\n## 읽기와 편집\n\n- **Ctrl+O** 문서 열기 · **Ctrl+Shift+O** 폴더 열기\n- **Ctrl+P** 빠른 파일 열기 · **Ctrl+F** 문서 검색\n- **Ctrl+Shift+F** 폴더 본문 검색\n- **Ctrl+Shift+M** 원문 모드 전환\n\n> 파일 관리와 복구는 왼쪽 사이드바와 도구 모음에서 사용할 수 있습니다.\n";
const normalized = (p) => path.resolve(p);
const same = (a, b) =>
  process.platform === "win32"
    ? normalized(a).toLowerCase() === normalized(b).toLowerCase()
    : normalized(a) === normalized(b);
const inside = (p, dir) => {
  const rel = path.relative(normalized(dir), normalized(p));
  return (
    !rel ||
    (!rel.startsWith(".." + path.sep) && rel !== ".." && !path.isAbsolute(rel))
  );
};
const base = (p) => pathToFileURL(path.dirname(p) + path.sep).href;
function send(type, payload) {
  if (win && !win.isDestroyed())
    win.webContents.send("desktop-event", { type, payload });
}
function editor(message) {
  send("editor", {
    documentID: doc?.path || "untitled",
    sessionID: doc?.sessionID,
    ...message,
  });
}
function state({ includeEntries = true } = {}) {
  return {
    doc: doc
      ? {
          path: doc.path,
          sessionID: doc.sessionID,
          revision: doc.revision,
          dirty: doc.dirty,
          conflict: doc.conflict,
          composing: doc.composing,
        }
      : null,
    root,
    ...(includeEntries ? { entries } : {}),
    settings,
    recoveryCount,
    status,
    busy,
  };
}
function publish() {
  const includesEntries = treeVersion !== publishedTreeVersion;
  send("state", state({ includeEntries: includesEntries }));
  if (includesEntries) publishedTreeVersion = treeVersion;
  if (win && !win.isDestroyed())
    win.setTitle(
      `${doc?.path ? path.basename(doc.path) : "새 문서"}${doc?.dirty ? " · 미저장" : ""} — MyMarkdownViewer`,
    );
}
function announce(message) {
  status = String(message);
  send("notice", status);
  publish();
}
function newDoc(text = "", loaded = null) {
  return {
    path: loaded?.path || null,
    text,
    codec: loaded?.codec || decode(Buffer.from(text)),
    hash: loaded?.hash ?? null,
    signature: loaded?.signature ?? null,
    sessionID: randomUUID(),
    recoveryID: randomUUID(),
    recoveryWritten: false,
    revision: 0,
    dirty: false,
    conflict: null,
    composing: false,
  };
}
function openEditor() {
  if (doc && editorReady)
    editor({
      type: "open",
      text: doc.text,
      revision: doc.revision,
      baseURL: doc.path ? base(doc.path) : "",
      settings,
      sourceMode: false,
    });
}
function askEditor(method, ...args) {
  if (!editorReady)
    return Promise.reject(Error("편집기가 아직 준비되지 않았습니다."));
  return new Promise((resolve, reject) => {
    const requestID = randomUUID();
    const timer = setTimeout(() => {
      requests.delete(requestID);
      reject(Error("편집기 응답을 받지 못했습니다. 복구본을 유지합니다."));
    }, 10000);
    requests.set(requestID, { resolve, reject, timer });
    send("editorRequest", { requestID, method, args });
  });
}
async function persistRecovery(target = doc) {
  const record = target?.dirty
    ? {
        id: target.recoveryID,
        path: target.path,
        text: target.text,
        codec: target.codec,
        revision: target.revision,
        date: new Date().toISOString(),
      }
    : null;
  if (
    !record ||
    target.recoveryRevision === record.revision
  )
    return;
  if (target.recoveryQueuedRevision === record.revision) {
    await recoveryChain;
    return;
  }
  target.recoveryQueuedRevision = record.revision;
  const job = recoveryChain
    .catch(() => {})
    .then(() => store.writeRecovery(record));
  recoveryChain = job;
  try {
    await job;
  } catch (error) {
    if (target.recoveryQueuedRevision === record.revision)
      target.recoveryQueuedRevision = undefined;
    throw error;
  }
  target.recoveryRevision = record.revision;
  if (target.recoveryQueuedRevision === record.revision)
    target.recoveryQueuedRevision = undefined;
  if (!target.recoveryWritten) {
    target.recoveryWritten = true;
    recoveryCount++;
  }
}
async function removeCheckpoint(target) {
  await recoveryChain.catch(() => {});
  await store.removeRecovery(target.recoveryID);
  if (target.recoveryWritten) {
    target.recoveryWritten = false;
    target.recoveryRevision = undefined;
    target.recoveryQueuedRevision = undefined;
    recoveryCount = Math.max(0, recoveryCount - 1);
  }
}
function schedule() {
  clearTimeout(autoTimer);
  clearTimeout(recoveryTimer);
  recoveryTimer = setTimeout(
    () => persistRecovery().catch((e) => announce(e.message)),
    750,
  );
  if (settings.autosave && doc.path && !doc.composing && !doc.conflict)
    autoTimer = setTimeout(() => run("save").catch(() => {}), 1000);
}
async function synchronize() {
  const snap = await askEditor("snapshot");
  if (
    snap.sessionID !== doc.sessionID ||
    snap.documentID !== (doc.path || "untitled")
  )
    throw Error("문서가 바뀌었습니다. 다시 시도해 주세요.");
  if (snap.composing) throw Error("한글 조합을 마친 뒤 다시 시도해 주세요.");
  if (snap.text !== doc.text) {
    doc.text = String(snap.text);
    doc.revision = snap.revision;
    doc.dirty = true;
    await persistRecovery();
  }
  doc.composing = false;
}
async function allowedFile(file, allowMissing = false) {
  file = normalized(file);
  if (fileGrants.has(file)) {
    await validateWithin(path.dirname(file), file, { allowMissing });
    return file;
  }
  for (const dir of folderGrants)
    if (inside(file, dir)) {
      await validateWithin(dir, file, { allowMissing });
      return file;
    }
  throw Error("먼저 파일 또는 폴더 열기로 접근할 위치를 선택해 주세요.");
}
async function saveCurrent(saveAs = false) {
  await synchronize();
  const target = doc;
  const oldIdentity = {
    documentID: target.path || "untitled",
    sessionID: target.sessionID,
  };
  if (!saveAs && target.conflict)
    throw Error(
      target.conflict + " 다른 이름으로 저장하거나 디스크 내용을 다시 여세요.",
    );
  if (!saveAs && target.path && !target.dirty) return true;
  let dest = target.path,
    codec = target.codec,
    expected = target.hash,
    text = target.text;
  if (saveAs || !dest) {
    const chosen = await dialog.showSaveDialog(win, {
      title: "Markdown 저장",
      defaultPath: dest || "새 문서.md",
      filters: [{ name: "Markdown", extensions: ["md"] }],
    });
    if (chosen.canceled || !chosen.filePath) return false;
    dest = chosen.filePath;
    fileGrants.add(normalized(dest));
    if (target.path && !same(dest, target.path))
      text = rebaseMarkdown(text, base(target.path), base(dest));
    try {
      const existing = await store.read(dest);
      codec = existing.codec;
      expected = existing.hash;
    } catch (e) {
      if (!["ENOENT", "deleted", "notFound"].includes(e.code)) throw e;
      codec = target.codec;
      expected = null;
    }
  }
  await allowedFile(dest, expected === null);
  const savedRevision = target.revision;
  try {
    const saved = await store.save(dest, text, codec, expected);
    const moved = !target.path || !same(dest, target.path);
    target.path = saved.path;
    target.codec = saved.codec;
    target.hash = saved.hash;
    target.conflict = null;
    target.dirty = target.revision !== savedRevision;
    if (moved) {
      target.sessionID = randomUUID();
      target.text = text;
      target.revision = 0;
      send("editor", {
        type: "relocate",
        ...oldIdentity,
        text,
        nextDocumentID: saved.path,
        nextSessionID: target.sessionID,
        baseURL: base(saved.path),
      });
      resetWatchers();
    }
    if (!target.dirty) await removeCheckpoint(target);
    else await persistRecovery(target);
    status = "저장됨";
    publish();
    return true;
  } catch (e) {
    target.conflict = e.message;
    await persistRecovery(target);
    publish();
    throw e;
  }
}
async function beforeLeave() {
  await synchronize();
  if (!doc.dirty) return true;
  const result = await dialog.showMessageBox(win, {
    type: "question",
    message: "변경 내용을 저장할까요?",
    detail: doc.path || "새 문서",
    buttons: ["저장", "취소", "복구본을 남기고 계속"],
    defaultId: 0,
    cancelId: 1,
  });
  if (result.response === 1) return false;
  if (result.response === 0) return saveCurrent();
  await persistRecovery();
  return true;
}
async function openFile(file, position) {
  file = await allowedFile(file);
  if (doc.path && same(doc.path, file)) {
    if (position?.from !== undefined)
      editor({ type: "jump", from: position.from, to: position.to });
    return;
  }
  const loaded = await store.read(file);
  if (!(await beforeLeave())) return;
  doc = newDoc(loaded.text, loaded);
  resetWatchers();
  status = "저장됨";
  openEditor();
  if (position?.from !== undefined)
    setTimeout(
      () => editor({ type: "jump", from: position.from, to: position.to }),
      30,
    );
  publish();
}
let refreshGeneration = 0;
async function refresh() {
  const folder = root, generation = ++refreshGeneration;
  if (folder) {
    const next = await listTree(folder);
    if (folder !== root || generation !== refreshGeneration) return;
    if (JSON.stringify(next) !== JSON.stringify(entries)) {
      entries = next;
      treeVersion++;
      publish();
    }
  }
}
function queueRefresh() {
  clearTimeout(refreshTimer);
  refreshTimer = setTimeout(() => {
    refresh().catch((error) => announce(error.message));
  }, 150);
}
async function checkExternalDocument(forceRead = false) {
  if (busy || !doc?.path || doc.composing) return false;
  const target = doc;
  try {
    const signature = await store.signature(await allowedFile(target.path));
    if (!forceRead && signature === target.signature) return;
    const loaded = await store.read(await allowedFile(target.path));
    if (busy || target.composing || doc !== target) return false;
    if (loaded.hash === target.hash) {
      target.signature = loaded.signature;
      return true;
    }
    if (target.dirty) {
      target.conflict = "다른 프로그램에서 파일을 변경했습니다.";
      await persistRecovery();
      publish();
    } else {
      doc = newDoc(loaded.text, loaded);
      openEditor();
      publish();
    }
    return true;
  } catch (error) {
    if (!busy && doc === target && !target.conflict) {
      target.conflict = error.message;
      publish();
    }
    return false;
  }
}
function requestExternalDocumentCheck(forceRead = false) {
  externalCheckPending = true;
  externalCheckForce ||= forceRead;
  if (externalCheckInFlight) return;
  externalCheckInFlight = true;
  void (async () => {
    try {
      while (externalCheckPending) {
        externalCheckPending = false;
        const force = externalCheckForce;
        externalCheckForce = false;
        const applied = await checkExternalDocument(force);
        if (!applied && (busy || doc?.composing)) {
          externalCheckPending = true;
          externalCheckForce ||= force;
          break;
        }
      }
    } finally {
      externalCheckInFlight = false;
    }
  })();
}
function closeWatchers() {
  rootWatcher?.close();
  documentWatcher?.close();
  rootWatcher = documentWatcher = undefined;
}
function resetWatchers() {
  closeWatchers();
  const watchRoot = (folder, recursive, onChange) => {
    if (!folder) return;
    try {
      const watcher = watchFS(folder, { recursive }, onChange);
      // A removed/renamed root can emit an asynchronous error. Keep the
      // process alive; the periodic guard and explicit refresh remain safe.
      watcher.on("error", () => {
        watcher.close();
        if (watcher === rootWatcher) rootWatcher = undefined;
        if (watcher === documentWatcher) documentWatcher = undefined;
      });
      return watcher;
    } catch {
      return undefined;
    }
  };
  rootWatcher = watchRoot(root, true, (event, filename) => {
    // A metadata probe is cheap when another file changed; it turns into a
    // content read only when the open document's own signature differs.
    requestExternalDocumentCheck(Boolean(filename && doc?.path && same(path.join(root, String(filename)), doc.path)));
    if (event !== "rename") return;
    if (!filename) return queueRefresh();
    const relative = String(filename);
    if (/^\.mymarkdown-[^/\\]+\.tmp$/i.test(path.basename(relative))) return;
    const full = path.join(root, relative);
    const known = entries.find((entry) => same(entry.path, full));
    void fs
      .lstat(full)
      .then((stat) => {
        // Atomic saves replace a known Markdown file and report `rename`, but
        // do not change the visible tree. New/deleted files and folders do.
        if (known && !known.directory && stat.isFile() && /\.md$/i.test(full))
          return;
        queueRefresh();
      })
      .catch(() => queueRefresh());
  });
  if (doc?.path && (!root || !inside(doc.path, root)))
    documentWatcher = watchRoot(path.dirname(doc.path), false, () =>
      requestExternalDocumentCheck(true),
    );
}
function sessionMatches(message) {
  return (
    message.sessionID === doc?.sessionID &&
    message.documentID === (doc.path || "untitled")
  );
}
async function editorEvent(message) {
  if (message.type === "ready") {
    editorReady = true;
    openEditor();
    publish();
    return;
  }
  if (!sessionMatches(message)) return;
  if (message.type === "changed") {
    if (message.baseRevision !== doc.revision) {
      doc.conflict = "편집 순서가 일치하지 않아 저장을 중지했습니다.";
      await persistRecovery();
      publish();
      return;
    }
    try {
      doc.text = applyChanges(doc.text, message.changes);
      doc.revision = message.revision;
      doc.dirty = true;
      doc.composing = Boolean(message.composing);
      schedule();
      publish();
    } catch (e) {
      doc.conflict = e.message;
      await persistRecovery();
      publish();
    }
  } else if (message.type === "composition") {
    doc.composing = Boolean(message.active);
    if (!doc.composing) {
      schedule();
      if (externalCheckPending) requestExternalDocumentCheck();
    }
  } else if (message.type === "save") {
    void run("save").catch(() => {});
  } else if (message.type === "openLink") {
    void run("openLink", { href: message.href }).catch(() => {});
  } else if (message.type === "insertImageData") {
    void run("insertImageData", message).catch(() => {});
  } else if (message.type === "remoteImages") {
    void run("remoteImages").catch(() => {});
  } else if (message.type === "grantFolder") {
    void run("grantFolder").catch(() => {});
  } else if (message.type === "error") announce(message.message);
}
async function doAction(action, p = {}) {
  switch (action) {
    case "new":
      if (await beforeLeave()) {
        doc = newDoc();
        resetWatchers();
        openEditor();
        publish();
      }
      break;
    case "openDialog": {
      const result = await dialog.showOpenDialog(win, {
        properties: ["openFile"],
        filters: [{ name: "Markdown", extensions: ["md"] }],
      });
      if (!result.canceled) {
        const f = normalized(result.filePaths[0]);
        fileGrants.add(f);
        await openFile(f);
      }
      break;
    }
    case "open":
      await openFile(p.path, p);
      break;
    case "chooseFolder": {
      const result = await dialog.showOpenDialog(win, {
        properties: ["openDirectory"],
      });
      if (!result.canceled) {
        const f = normalized(result.filePaths[0]);
        await validateWithin(f, f);
        root = f;
        folderGrants.add(f);
        resetWatchers();
        searchReport = review = null;
        await refresh();
        await persistSettings();
        publish();
      }
      break;
    }
    case "save":
      return saveCurrent();
    case "saveAs":
      return saveCurrent(true);
    case "refresh":
      return refresh();
    case "reload": {
      if (!doc.path) break;
      const result = await dialog.showMessageBox(win, {
        message: "디스크의 내용으로 다시 열까요?",
        detail: "현재 편집본은 복구 목록에 남깁니다.",
        buttons: ["다시 열기", "취소"],
        cancelId: 1,
      });
      if (result.response === 0) {
        await persistRecovery();
        const loaded = await store.read(await allowedFile(doc.path));
        doc = newDoc(loaded.text, loaded);
        resetWatchers();
        openEditor();
        publish();
      }
      break;
    }
    case "create": {
      if (!root) throw Error("먼저 폴더를 열어 주세요.");
      const f = await create(
        root,
        p.parent || root,
        p.name,
        Boolean(p.directory),
      );
      await refresh();
      if (!p.directory) await openFile(f);
      return f;
    }
    case "move": {
      if (!root) throw Error("먼저 폴더를 열어 주세요.");
      await validateWithin(root, p.source);
      await validateWithin(root, p.parent);
      validateName(p.name);
      if (same(root, p.source))
        throw Error("작업 폴더 자체는 이동할 수 없습니다.");
      if (
        doc.dirty &&
        doc.path &&
        inside(doc.path, p.source) &&
        !(await saveCurrent())
      )
        return;
      const dest = path.join(p.parent, p.name),
        source = normalized(p.source);
      const isDirectory = (await fs.lstat(source)).isDirectory();
      const affected = isDirectory
        ? await markdownFilesIncludingHidden(source)
        : /\.md$/i.test(source)
          ? [source]
          : [];
      const originals = await Promise.all(affected.map((f) => store.read(f)));
      const moved = await move(root, source, dest);
      const errors = [];
      for (const old of originals) {
        const nextPath = isDirectory
          ? path.join(moved, path.relative(source, old.path))
          : moved;
        const nextText = rebaseMarkdown(
          old.text,
          base(old.path),
          base(nextPath),
          {
            source: pathToFileURL(source).href,
            destination: pathToFileURL(moved).href,
            directory: isDirectory,
          },
        );
        let updated = { ...old, path: nextPath };
        try {
          if (nextText !== old.text)
            updated = await store.save(nextPath, nextText, old.codec, old.hash);
        } catch (e) {
          errors.push(path.basename(nextPath) + ": " + e.message);
          await store.writeRecovery({
            id: randomUUID(),
            path: nextPath,
            text: nextText,
            codec: old.codec,
            revision: 0,
            date: new Date().toISOString(),
          });
        }
        if (doc.path && same(doc.path, old.path)) {
          const identity = { documentID: doc.path, sessionID: doc.sessionID };
          fileGrants.delete(normalized(doc.path));
          fileGrants.add(normalized(nextPath));
          doc.path = nextPath;
          doc.text = updated.text;
          doc.hash = updated.hash;
          doc.codec = updated.codec;
          doc.sessionID = randomUUID();
          doc.revision = 0;
          send("editor", {
            type: "relocate",
            ...identity,
            text: doc.text,
            nextDocumentID: nextPath,
            nextSessionID: doc.sessionID,
            baseURL: base(nextPath),
          });
        }
      }
      searchReport = review = null;
      await refresh();
      if (errors.length)
        announce(
          "이동은 완료됐지만 일부 링크 보정이 실패했습니다. 복구 목록을 확인하세요.\n" +
            errors.join("\n"),
        );
      publish();
      return moved;
    }
    case "trash": {
      if (!root) throw Error("먼저 폴더를 열어 주세요.");
      await validateWithin(root, p.path);
      if (same(root, p.path))
        throw Error("작업 폴더 자체는 삭제할 수 없습니다.");
      const isOpen = doc.path && inside(doc.path, p.path);
      if (isOpen && !(await beforeLeave())) return;
      const result = await dialog.showMessageBox(win, {
        type: "warning",
        message: `${path.basename(p.path)}을(를) 휴지통으로 보낼까요?`,
        detail: "휴지통에서 복원할 수 있습니다.",
        buttons: ["취소", "휴지통으로 보내기"],
        defaultId: 0,
        cancelId: 0,
      });
      if (result.response === 1) {
        await validateWithin(root, p.path);
        await shell.trashItem(p.path);
        if (isOpen) {
          doc = newDoc();
          resetWatchers();
          openEditor();
        }
        searchReport = review = null;
        await refresh();
        publish();
      }
      break;
    }
    case "search": {
      if (!root || !p.query) throw Error("폴더와 검색어를 선택해 주세요.");
      if (
        doc.dirty &&
        doc.path &&
        inside(doc.path, root) &&
        !(await saveCurrent())
      )
        return;
      searchController?.abort();
      searchController = new AbortController();
      const result = await scan(root, {
        query: String(p.query),
        caseSensitive: Boolean(p.caseSensitive),
        signal: searchController.signal,
      });
      searchReport = { ...result, id: randomUUID(), query: p.query, root };
      review = null;
      return {
        ...searchReport,
        files: result.files.map(({ path, matches }) => ({ path, matches })),
      };
    }
    case "reviewReplace": {
      if (!searchReport?.complete || p.searchID !== searchReport.id)
        throw Error("검색을 다시 실행한 뒤 검토해 주세요.");
      review = {
        id: randomUUID(),
        searchID: searchReport.id,
        query: searchReport.query,
        replacement: String(p.replacement ?? ""),
        files: searchReport.files,
        root: searchReport.root,
      };
      return {
        ...review,
        files: review.files.map((f) => ({
          path: f.path,
          before: f.text,
          after: preview(f, review.replacement),
          matches: f.matches,
        })),
      };
    }
    case "applyReplace": {
      if (!review || p.reviewID !== review.id || !same(root, review.root))
        throw Error("변경 미리보기를 다시 만들어 주세요.");
      const frozen = review;
      const selected = Array.isArray(p.selected) ? p.selected : [];
      await synchronize();
      if (doc.dirty && selected.some((f) => doc.path && same(f, doc.path)))
        throw Error(
          "열린 문서가 편집되었습니다. 저장하고 검색부터 다시 실행하세요.",
        );
      const result = await applyPlan(
        frozen.files,
        frozen.replacement,
        selected,
        frozen.root,
        store,
      );
      if (
        doc.path &&
        result.outcomes.some(
          (o) => same(o.path, doc.path) && o.status === "saved",
        )
      ) {
        const loaded = await store.read(doc.path);
        doc = newDoc(loaded.text, loaded);
        openEditor();
      }
      searchReport = review = null;
      publish();
      return result;
    }
    case "recoveries":
      return store.recoveries();
    case "restoreRecovery": {
      const records = await store.recoveries(),
        record = records.find((r) => r.id === p.id);
      if (!record) throw Error("복구본을 찾을 수 없습니다.");
      if (!(await beforeLeave())) return;
      doc = newDoc(record.text);
      doc.codec = record.codec;
      doc.dirty = true;
      doc.recoveryID = record.id;
      doc.recoveryWritten = true;
      doc.recoveryRevision = doc.revision;
      resetWatchers();
      // Restore as an unsaved copy: no stale checkpoint can authorize overwriting its former path.
      status = `${record.path ? path.basename(record.path) : "새 문서"} 복구본 · 다른 이름으로 저장하세요.`;
      openEditor();
      publish();
      break;
    }
    case "discardRecovery": {
      const records = await store.recoveries();
      if (!records.some((r) => r.id === p.id)) break;
      const answer = await dialog.showMessageBox(win, {
        message: "이 복구본을 삭제할까요?",
        buttons: ["취소", "삭제"],
        defaultId: 0,
        cancelId: 0,
      });
      if (answer.response === 1) {
        await store.removeRecovery(p.id);
        if (doc?.recoveryID === p.id) {
          doc.recoveryWritten = false;
          doc.recoveryRevision = undefined;
          doc.recoveryQueuedRevision = undefined;
        }
        recoveryCount = (await store.recoveries()).length;
        publish();
      }
      break;
    }
    case "settings": {
      const patch = p.patch || {};
      if (["dark", "night", "light"].includes(patch.theme))
        settings.theme = patch.theme;
      for (const [key, min, max] of [
        ["fontSize", 12, 30],
        ["lineHeight", 1.3, 2.4],
        ["contentWidth", 500, 1200],
      ])
        if (Number.isFinite(Number(patch[key])))
          settings[key] = Math.max(min, Math.min(max, Number(patch[key])));
      if (["system", "serif", "mono"].includes(patch.fontFamily))
        settings.fontFamily = patch.fontFamily;
      for (const k of ["autosave", "remoteImages"])
        if (typeof patch[k] === "boolean") settings[k] = patch[k];
      nativeTheme.themeSource = settings.theme === "light" ? "light" : "dark";
      editor({ type: "settings", settings });
      await persistSettings();
      if (doc.dirty) schedule();
      publish();
      return settings;
    }
    case "remoteImages": {
      const answer = await dialog.showMessageBox(win, {
        message: "이 문서의 외부 이미지를 불러올까요?",
        detail: "이미지 서버에 네트워크 요청이 전송됩니다.",
        buttons: ["취소", "불러오기"],
        cancelId: 0,
      });
      if (answer.response === 1) {
        settings.remoteImages = true;
        editor({ type: "settings", settings });
        publish();
      }
      break;
    }
    case "grantFolder": {
      const selected = await dialog.showOpenDialog(win, {
        title: "이미지가 있는 폴더 허용",
        properties: ["openDirectory"],
      });
      if (!selected.canceled) {
        folderGrants.add(normalized(selected.filePaths[0]));
        editor({ type: "settings", settings });
      }
      break;
    }
    case "openLink": {
      if (typeof p.href !== "string") break;
      if (/^https?:\/\//i.test(p.href)) {
        await shell.openExternal(p.href);
        break;
      }
      if (p.href.startsWith("#")) {
        const headings = await askEditor("snapshot");
        const needle = p.href.slice(1).replaceAll("-", " ");
        const at = headings.text.toLowerCase().indexOf(needle.toLowerCase());
        if (at >= 0) editor({ type: "jump", from: at });
        break;
      }
      if (!doc.path)
        throw Error("이 링크 형식은 열 수 없습니다.");
      const url = new URL(p.href, base(doc.path));
      if (url.protocol !== "file:") throw Error("지원하지 않는 링크입니다.");
      const target = fileURLToPath(url);
      if (!/\.md$/i.test(target))
        throw Error("Markdown 문서 링크만 앱 안에서 열 수 있습니다.");
      // Explicitly opened folders may contain sibling links. Other locations
      // remain unavailable until the user selects them through a file dialog.
      if (inside(target, path.dirname(doc.path))) {
        await validateWithin(path.dirname(doc.path), target);
        fileGrants.add(normalized(target));
      } else {
        await allowedFile(target);
      }
      await openFile(target);
      break;
    }
    case "insertImageData": {
      if (!doc.path && !(await saveCurrent())) return;
      const ext = path.extname(String(p.name)).toLowerCase();
      if (
        ![
          ".png",
          ".jpg",
          ".jpeg",
          ".gif",
          ".webp",
          ".bmp",
          ".tiff",
          ".heic",
        ].includes(ext)
      )
        throw Error("지원하지 않는 이미지입니다.");
      if (typeof p.data !== "string" || p.data.length > 28 * 1024 * 1024)
        throw Error("이미지는 20MB 이하만 삽입할 수 있습니다.");
      const bytes = Buffer.from(p.data, "base64");
      if (bytes.length > 20 * 1024 * 1024) throw Error("이미지가 너무 큽니다.");
      const assets = path.join(path.dirname(doc.path), "assets");
      await validateWithin(path.dirname(doc.path), assets, {
        allowMissing: true,
      });
      await fs.mkdir(assets, { recursive: true });
      await validateWithin(path.dirname(doc.path), assets);
      const name = `image-${randomUUID()}${ext}`;
      await fs.writeFile(path.join(assets, name), bytes, { flag: "wx" });
      editor({ type: "lock", locked: false });
      editor({ type: "insert", text: `![이미지](assets/${name})` });
      break;
    }
    case "command":
      editor({ type: "command", command: p.command });
      break;
    default:
      throw Error("지원하지 않는 작업입니다.");
  }
}
async function run(action, payload = {}) {
  if (action === "command") {
    if (!busy) editor({ type: "command", command: payload.command });
    return;
  }
  if (busy)
    throw Error("다른 작업이 진행 중입니다. 잠시 후 다시 시도해 주세요.");
  busy = true;
  clearTimeout(autoTimer);
  editor({ type: "lock", locked: true });
  publish();
  try {
    return await doAction(action, payload);
  } catch (e) {
    announce(e.message || String(e));
    throw e;
  } finally {
    busy = false;
    if (externalCheckPending && !closing) requestExternalDocumentCheck();
    editor({ type: "lock", locked: false });
    publish();
  }
}
async function persistSettings() {
  await fs.writeFile(
    path.join(app.getPath("userData"), "settings.json"),
    JSON.stringify({ settings, root }),
    "utf8",
  );
}
async function markdownFilesIncludingHidden(dir) {
  const result = [];
  async function visit(folder, depth = 0) {
    if (depth > 50 || result.length > 10000)
      throw Error("폴더가 너무 큽니다. 더 작은 폴더를 선택해 주세요.");
    for (const entry of await fs.readdir(folder, { withFileTypes: true })) {
      const f = path.join(folder, entry.name);
      if (
        entry.isSymbolicLink() ||
        /\.(app|bundle|framework)$/i.test(entry.name)
      )
        continue;
      if (entry.isDirectory()) await visit(f, depth + 1);
      else if (entry.isFile() && /\.md$/i.test(f)) result.push(f);
    }
  }
  await visit(dir);
  return result;
}
const mime = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".mjs": "text/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".bmp": "image/bmp",
  ".svg": "image/svg+xml",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
};
async function serve(request) {
  try {
    const url = new URL(request.url);
    let f;
    if (url.host === "host" || url.host === "editor") {
      const dir = path.join(here, url.host === "host" ? "ui" : "editor");
      f = path.resolve(
        dir,
        "." +
          decodeURIComponent(
            url.pathname === "/" ? "/index.html" : url.pathname,
          ),
      );
      if (!inside(f, dir)) return new Response("Forbidden", { status: 403 });
    } else if (url.host === "assets" && doc?.path) {
      const parts = url.pathname.slice(1).split("/");
      if (decodeURIComponent(parts.shift()) !== doc.sessionID)
        return new Response("Stale session", { status: 403 });
      const relative = decodeURIComponent(parts.join("/"));
      const assetURL = new URL(relative, base(doc.path));
      if (assetURL.protocol !== "file:")
        return new Response("Forbidden", { status: 403 });
      f = fileURLToPath(assetURL);
      if (
        ![
          ".png",
          ".jpg",
          ".jpeg",
          ".gif",
          ".webp",
          ".bmp",
          ".svg",
          ".tiff",
          ".heic",
        ].includes(path.extname(f).toLowerCase())
      )
        return new Response("Forbidden", { status: 403 });
      let permitted = false;
      for (const folder of new Set([path.dirname(doc.path), ...folderGrants]))
        if (inside(f, folder)) {
          await validateWithin(folder, f);
          permitted = true;
          break;
        }
      if (!permitted) return new Response("Forbidden", { status: 403 });
    } else return new Response("Not found", { status: 404 });
    return new Response(await fs.readFile(f), {
      headers: {
        "Content-Type":
          mime[path.extname(f).toLowerCase()] || "application/octet-stream",
        "X-Content-Type-Options": "nosniff",
        "Cache-Control": "no-store",
      },
    });
  } catch {
    return new Response("Not found", { status: 404 });
  }
}
app.on("second-instance", () => {
  win?.show();
  win?.focus();
});
app
  .whenReady()
  .then(async () => {
    await fs.mkdir(app.getPath("userData"), { recursive: true });
    store = new Store(app.getPath("userData"));
    try {
      const saved = JSON.parse(
        await fs.readFile(
          path.join(app.getPath("userData"), "settings.json"),
          "utf8",
        ),
      );
      settings = { ...settings, ...saved.settings };
      if (saved.root) {
        await validateWithin(saved.root, saved.root);
        root = saved.root;
        folderGrants.add(root);
        entries = await listTree(root);
        treeVersion++;
      }
    } catch {}
    doc = newDoc(welcome);
    recoveryCount = (await store.recoveries()).length;
    resetWatchers();
    if (qaMode)
      globalThis.__qa = {
        state,
        document: () => structuredClone(doc),
        run,
        askEditor,
        grant: async (folder) => {
          await validateWithin(app.getPath("userData"), folder);
          root = folder;
          folderGrants.add(folder);
          resetWatchers();
          await refresh();
          publish();
        },
      };
    nativeTheme.themeSource = settings.theme === "light" ? "light" : "dark";
    protocol.handle("app", serve);
    win = new BrowserWindow({
      width: 1180,
      height: 820,
      minWidth: 800,
      minHeight: 560,
      show: false,
      backgroundColor: "#191b1e",
      icon: path.join(here, "icon.png"),
      webPreferences: {
        preload: path.join(here, "preload.cjs"),
        nodeIntegration: false,
        contextIsolation: true,
        sandbox: true,
        webSecurity: true,
        spellcheck: false,
      },
    });
    const outer = win.getBounds(), content = win.getContentBounds();
    win.setMinimumSize(800 + outer.width - content.width, 560 + outer.height - content.height);
    win.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
    win.webContents.on("will-navigate", (event) => event.preventDefault());
    win.webContents.on("will-frame-navigate", (event) => {
      if (event.url !== "app://editor/index.html") event.preventDefault();
    });
    win.webContents.session.setPermissionRequestHandler(
      (_wc, _permission, callback) => callback(false),
    );
    win.webContents.on("render-process-gone", () => {
      editorReady = false;
      void persistRecovery();
    });
    ipcMain.handle("desktop", async (event, action, payload) => {
      try {
        if (
          event.sender !== win.webContents ||
          event.senderFrame !== win.webContents.mainFrame ||
          event.senderFrame.url !== "app://host/index.html"
        )
          throw Error("허용되지 않은 요청입니다.");
        if (action === "bootstrap") return { ok: true, value: state() };
        if (action === "editorResult") {
          const r = requests.get(payload.requestID);
          if (r) {
            clearTimeout(r.timer);
            requests.delete(payload.requestID);
            payload.error
              ? r.reject(Error(payload.error))
              : r.resolve(payload.result);
          }
          return { ok: true };
        }
        if (action === "editorEvent") {
          await editorEvent(payload);
          return { ok: true };
        }
        if (action === "cancelSearch") {
          searchController?.abort();
          return { ok: true };
        }
        return { ok: true, value: await run(action, payload) };
      } catch (e) {
        return { ok: false, error: e.message || String(e) };
      }
    });
    const item = (label, accelerator, action) => ({
      label,
      accelerator,
      click: () => send("menu", action),
    });
    Menu.setApplicationMenu(
      Menu.buildFromTemplate([
        ...(process.platform === "darwin" ? [{ role: "appMenu" }] : []),
        {
          label: "파일",
          submenu: [
            item("새 문서", "CmdOrCtrl+N", "new"),
            item("문서 열기…", "CmdOrCtrl+O", "openDialog"),
            item("폴더 열기…", "CmdOrCtrl+Shift+O", "chooseFolder"),
            item("빠른 파일 열기…", "CmdOrCtrl+P", "quickOpen"),
            { type: "separator" },
            item("저장", "CmdOrCtrl+S", "save"),
            item("다른 이름으로 저장…", "CmdOrCtrl+Shift+S", "saveAs"),
            { type: "separator" },
            item("복구할 문서 보기", undefined, "recoveries"),
            { role: "quit", label: "종료" },
          ],
        },
        {
          label: "편집",
          submenu: [
            item("실행 취소", "CmdOrCtrl+Z", "command:undo"),
            item("다시 실행", "CmdOrCtrl+Shift+Z", "command:redo"),
            { type: "separator" },
            { role: "cut", label: "잘라내기" },
            { role: "copy", label: "복사" },
            { role: "paste", label: "붙여넣기" },
            { type: "separator" },
            item("문서 검색", "CmdOrCtrl+F", "command:search"),
            item("폴더 전체 검색", "CmdOrCtrl+Shift+F", "folderSearch"),
          ],
        },
        {
          label: "보기",
          submenu: [
            item("사이드바 표시 / 숨기기", "CmdOrCtrl+Shift+L", "toggleSidebar"),
            item("목차", "CmdOrCtrl+Shift+1", "showOutline"),
            item("파일", "CmdOrCtrl+Shift+3", "showFiles"),
            item("원문 모드", "CmdOrCtrl+/", "command:source"),
            item("설정", undefined, "settings"),
            { role: "togglefullscreen", label: "전체 화면" },
          ],
        },
        {
          label: "서식",
          submenu: [
            item("굵게", "CmdOrCtrl+B", "command:bold"),
            item("기울임", "CmdOrCtrl+I", "command:italic"),
            item("링크", "CmdOrCtrl+K", "command:link"),
            item("제목", undefined, "command:heading"),
            item("목록", undefined, "command:list"),
            item("할 일", undefined, "command:task"),
            item("인용문", undefined, "command:quote"),
            item("코드 블록", undefined, "command:codeBlock"),
          ],
        },
      ]),
    );
    win.setMenuBarVisibility(false);
    win.on("close", (event) => {
      if (closing) return;
      event.preventDefault();
      void run("saveOnClose").catch(() => {});
    });
    // Close uses the same save/cancel/recovery flow, without force-quitting a dirty editor.
    const originalAction = doAction;
    doAction = async (action, payload) => {
      if (action !== "saveOnClose") return originalAction(action, payload);
      if (await beforeLeave()) {
        await persistRecovery();
        closing = true;
        clearInterval(watchTimer);
        clearTimeout(refreshTimer);
        closeWatchers();
        win.close();
      }
    };
    await win.loadURL("app://host/index.html");
    win.show();
    let watching = false,
      ticks = 0;
    watchTimer = setInterval(async () => {
      if (busy || watching) return;
      watching = true;
      try {
        // File-system events provide the prompt path. This slower guard keeps
        // external-change detection reliable if an event is dropped.
        if ((root && !rootWatcher) || (doc?.path && !root && !documentWatcher)) resetWatchers();
        requestExternalDocumentCheck(false);
        if (++ticks % 4 === 0) await refresh();
      } catch (e) {
        if (!busy) {
          announce(e.message);
        }
      } finally {
        watching = false;
      }
    }, 15000);
  })
  .catch((e) => {
    console.error(e);
    app.exit(1);
  });
app.on("window-all-closed", () => app.quit());
