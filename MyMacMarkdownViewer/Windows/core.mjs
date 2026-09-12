import { createHash, randomUUID } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";
import { diffArrays } from "diff";

const RESERVED = /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$/i;
const PACKAGES = new Set([".app", ".bundle", ".framework", ".pkg"]);
const locks = new Map();

export function isMarkdownPath(file) {
  return [".md", ".markdown"].includes(path.extname(String(file)).toLowerCase());
}

export class CoreError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "CoreError";
    this.code = code;
  }
}
const fail = (code, message) => {
  throw new CoreError(code, message);
};
const korean = {
  conflict: "다른 프로그램에서 파일을 변경했습니다. 자동 저장을 멈췄습니다.",
  deleted:
    "파일이 이동되거나 삭제되었습니다. 편집본을 다른 이름으로 저장할 수 있습니다.",
  unsafePath: "작업 폴더 밖이거나 링크를 지나는 경로에는 접근할 수 없습니다.",
  invalidChange:
    "편집 상태를 동기화하지 못했습니다. 복구본을 보존하고 저장을 멈췄습니다.",
  invalidName: "파일 또는 폴더 이름을 확인해 주세요.",
  unsupportedEncoding:
    "UTF-8 문서만 편집할 수 있습니다. 원본 파일은 변경하지 않았습니다.",
  alreadyExists: "같은 이름의 파일 또는 폴더가 이미 있습니다.",
  rootProtected: "작업 폴더 자체는 이동할 수 없습니다.",
  invalidMove: "폴더를 자기 자신 또는 그 안으로 옮길 수 없습니다.",
  duplicateIncomplete: "복제본을 완성하지 못했습니다. 원본 편집본은 변경하지 않았습니다.",
  unavailable:
    "파일 작업을 완료할 수 없습니다. 접근 권한과 동기화 상태를 확인해 주세요.",
};
function err(code) {
  return fail(code, korean[code] ?? korean.unavailable);
}
function bom(bytes) {
  return (
    bytes.length >= 3 &&
    bytes[0] === 0xef &&
    bytes[1] === 0xbb &&
    bytes[2] === 0xbf
  );
}
function rawLines(text) {
  const out = [];
  let start = 0;
  for (const m of text.matchAll(/\r\n|\r|\n/g)) {
    out.push([text.slice(start, m.index), m[0]]);
    start = m.index + m[0].length;
  }
  out.push([text.slice(start), ""]);
  return out;
}
function normalize(text) {
  return text.replace(/\r\n|\r/g, "\n");
}
export function decode(bytes) {
  const data = Buffer.from(bytes);
  const hasBom = bom(data);
  const body = data.subarray(hasBom ? 3 : 0);
  let originalTextRaw;
  try {
    originalTextRaw = new TextDecoder("utf-8", { fatal: true }).decode(body);
  } catch {
    err("unsupportedEncoding");
  }
  if (originalTextRaw.includes("\0")) err("unsupportedEncoding");
  return {
    originalBase64: data.toString("base64"),
    originalText: normalize(originalTextRaw),
    bom: hasBom,
    lineEnding: originalTextRaw.includes("\r\n")
      ? "\r\n"
      : originalTextRaw.includes("\r")
        ? "\r"
        : "\n",
  };
}
export function encode(text, codec) {
  if (text === codec.originalText)
    return Buffer.from(codec.originalBase64, "base64");
  const original = Buffer.from(codec.originalBase64, "base64")
    .subarray(codec.bom ? 3 : 0)
    .toString("utf8");
  const old = rawLines(original),
    next = String(text).split("\n");
  // `diff` uses edit-distance storage rather than an n*m table. Bound difficult diffs;
  // the prefix/suffix fallback still preserves all unquestionably unchanged line endings.
  const endings = Array(next.length).fill(codec.lineEnding);
  let i = 0,
    j = 0;
  const oldBodies = old.map((line) => line[0]);
  const changes = diffArrays(oldBodies, next, {
    maxEditLength: 4096,
    timeout: 100,
  });
  if (changes) {
    for (const change of changes) {
      const length = change.value.length;
      if (!change.added && !change.removed) {
        for (let offset = 0; offset < length; offset++)
          endings[j + offset] = old[i + offset][1] || codec.lineEnding;
        i += length;
        j += length;
      } else if (change.removed) i += length;
      else j += length;
    }
  } else {
    while (
      i < oldBodies.length &&
      j < next.length &&
      oldBodies[i] === next[j]
    ) {
      endings[j] = old[i][1] || codec.lineEnding;
      i++;
      j++;
    }
    let oldEnd = oldBodies.length - 1,
      newEnd = next.length - 1;
    while (oldEnd >= i && newEnd >= j && oldBodies[oldEnd] === next[newEnd]) {
      endings[newEnd] = old[oldEnd][1] || codec.lineEnding;
      oldEnd--;
      newEnd--;
    }
  }
  const output = next
    .map(
      (line, index) => line + (index + 1 === next.length ? "" : endings[index]),
    )
    .join("");
  return Buffer.concat([
    codec.bom ? Buffer.from([0xef, 0xbb, 0xbf]) : Buffer.alloc(0),
    Buffer.from(output, "utf8"),
  ]);
}
export function hash(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}
export function applyChanges(text, changes) {
  if (typeof text !== "string" || !Array.isArray(changes)) err("invalidChange");
  let end = 0;
  for (const c of changes) {
    if (
      !c ||
      typeof c.insert !== "string" ||
      !Number.isInteger(c.from) ||
      !Number.isInteger(c.to) ||
      c.from < end ||
      c.to < c.from ||
      c.to > text.length ||
      (c.from > 0 && isLow(text.charCodeAt(c.from))) ||
      (c.to > 0 && c.to < text.length && isLow(text.charCodeAt(c.to)))
    )
      err("invalidChange");
    end = c.to;
  }
  let output = text;
  for (let i = changes.length - 1; i >= 0; i--)
    output =
      output.slice(0, changes[i].from) +
      changes[i].insert +
      output.slice(changes[i].to);
  return output;
}
function isLow(unit) {
  return unit >= 0xdc00 && unit <= 0xdfff;
}
export function validateName(name) {
  if (
    typeof name !== "string" ||
    !name ||
    name === "." ||
    name === ".." ||
    /[<>:"/\\|?*\0-\x1f]/.test(name) ||
    /[. ]$/.test(name) ||
    RESERVED.test(name)
  )
    err("invalidName");
  return name;
}
function inside(root, target) {
  const rel = path.relative(root, target);
  return (
    rel === "" ||
    (!rel.startsWith(".." + path.sep) && rel !== ".." && !path.isAbsolute(rel))
  );
}
async function lstatSafe(item) {
  try {
    return await fs.lstat(item);
  } catch (e) {
    if (e.code === "ENOENT") return null;
    throw e;
  }
}
export async function validateWithin(
  root,
  target,
  { allowMissing = false } = {},
) {
  const safeRoot = path.resolve(root),
    safeTarget = path.resolve(target);
  if (!inside(safeRoot, safeTarget)) err("unsafePath");
  const rootStat = await lstatSafe(safeRoot);
  if (!rootStat || !rootStat.isDirectory() || rootStat.isSymbolicLink())
    err("unsafePath");
  const parts = path
    .relative(safeRoot, safeTarget)
    .split(path.sep)
    .filter(Boolean);
  let current = safeRoot;
  for (let index = 0; index < parts.length; index++) {
    current = path.join(current, parts[index]);
    const stat = await lstatSafe(current);
    if (!stat) {
      if (allowMissing) break;
      err("unsafePath");
    }
    if (stat.isSymbolicLink()) err("unsafePath");
  }
  return safeTarget;
}
async function regular(file) {
  const st = await lstatSafe(file);
  if (!st) err("deleted");
  if (!st.isFile() || st.isSymbolicLink()) err("unsafePath");
}
async function withLock(key, operation) {
  const previous = locks.get(key) ?? Promise.resolve();
  let release;
  const current = new Promise((resolve) => {
    release = resolve;
  });
  const queued = previous.then(() => current);
  locks.set(key, queued);
  await previous;
  try {
    return await operation();
  } finally {
    release();
    if (locks.get(key) === queued) locks.delete(key);
  }
}
async function atomicWrite(target, data) {
  const temp = path.join(
    path.dirname(target),
    `.mymarkdown-${randomUUID()}.tmp`,
  );
  try {
    await fs.writeFile(temp, data, { flag: "wx" });
    await fs.rename(temp, target);
  } finally {
    await fs.unlink(temp).catch(() => {});
  }
}
export class Store {
  constructor(dataDir) {
    this.dataDir = dataDir;
  }
  async read(file) {
    const before = await this.signature(file);
    const bytes = await fs.readFile(file);
    const codec = decode(bytes);
    const after = await this.signature(file);
    return {
      path: file,
      text: codec.originalText,
      hash: hash(bytes),
      codec,
      // Do not associate bytes from one version with metadata from another.
      // A null signature forces the caller to probe again before treating it clean.
      signature: before === after ? after : null,
    };
  }
  async signature(file) {
    await regular(file);
    const stat = await fs.stat(file);
    // This is deliberately metadata only: callers use it to avoid reading an
    // unchanged large document, then still compare a content hash before acting.
    return `${stat.size}:${stat.mtimeMs}:${stat.ctimeMs}`;
  }
  async save(file, text, codec, expectedHash) {
    return withLock(path.resolve(file), async () => {
      const before = await lstatSafe(file);
      if (before) {
        if (!before.isFile() || before.isSymbolicLink()) err("unsafePath");
        if (expectedHash == null) err("conflict");
        const original = await fs.readFile(file);
        if (hash(original) !== expectedHash) err("conflict");
        await this.#backup(file, original);
      } else if (expectedHash != null) err("deleted");
      const bytes = encode(text, codec),
        temp = path.join(path.dirname(file), `.mymarkdown-${randomUUID()}.tmp`);
      try {
        await fs.writeFile(temp, bytes, { flag: "wx" });
        const recheck = await lstatSafe(file);
        if (before) {
          if (!recheck) err("deleted");
          if (
            !recheck.isFile() ||
            recheck.isSymbolicLink() ||
            hash(await fs.readFile(file)) !== expectedHash
          )
            err("conflict");
        } else {
          if (recheck) err("conflict");
          await fs.link(temp, file).catch((error) => {
            if (error.code === "EEXIST") err("conflict");
            throw error;
          });
          await fs.unlink(temp);
        }
        if (before) await fs.rename(temp, file);
      } finally {
        await fs.unlink(temp).catch(() => {});
      }
      return {
        path: file,
        text,
        hash: hash(bytes),
        codec: decode(bytes),
        // Another process may replace the file immediately after our atomic write.
        // Force the watcher path to verify rather than pairing our bytes with its stat.
        signature: null,
      };
    });
  }
  async #backup(file, bytes) {
    const dir = path.join(
      this.dataDir,
      "Backups",
      hash(Buffer.from(path.resolve(file))),
    );
    await fs.mkdir(dir, { recursive: true });
    await atomicWrite(
      path.join(dir, `${Date.now()}-${randomUUID()}.md`),
      bytes,
    );
    const files = (await fs.readdir(dir)).sort().reverse();
    await Promise.all(
      files.slice(5).map((f) => fs.unlink(path.join(dir, f)).catch(() => {})),
    );
  }
  async writeRecovery(record) {
    if (!/^[A-Za-z0-9_-]+$/.test(record.id)) err("invalidName");
    const dir = path.join(this.dataDir, "Recovery");
    await fs.mkdir(dir, { recursive: true });
    await atomicWrite(
      path.join(dir, `${record.id}.json`),
      Buffer.from(JSON.stringify(record)),
    );
  }
  async recoveries() {
    const dir = path.join(this.dataDir, "Recovery");
    const names = await fs
      .readdir(dir)
      .catch((e) => (e.code === "ENOENT" ? [] : Promise.reject(e)));
    const records = await Promise.all(
      names
        .filter((n) => n.endsWith(".json"))
        .map(async (n) => {
          try {
            return JSON.parse(await fs.readFile(path.join(dir, n), "utf8"));
          } catch {
            return null;
          }
        }),
    );
    return records
      .filter(Boolean)
      .sort((a, b) => new Date(b.date) - new Date(a.date));
  }
  async removeRecovery(id) {
    if (!/^[A-Za-z0-9_-]+$/.test(id)) err("invalidName");
    await fs
      .unlink(path.join(this.dataDir, "Recovery", `${id}.json`))
      .catch((e) => {
        if (e.code !== "ENOENT") throw e;
      });
  }
}
function matches(text, query, sensitive, limit) {
  const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const expression = new RegExp(escaped, sensitive ? "gu" : "giu");
  const out = [];
  let match;
  while ((match = expression.exec(text)) && out.length < limit) {
    const from = match.index,
      value = match[0],
      line = text.slice(0, from).split("\n").length,
      start = text.lastIndexOf("\n", from - 1) + 1,
      finish = text.indexOf("\n", from);
    out.push({
      from,
      to: from + value.length,
      line,
      column: from - start + 1,
      snippet: text.slice(start, finish < 0 ? text.length : finish),
    });
    if (!value.length) expression.lastIndex++;
  }
  return out;
}
async function directoryEntries(
  root,
  onEntry,
  signal,
  { maxDepth = 64, maxCount = 10000 } = {},
) {
  let count = 0;
  async function visit(dir, depth) {
    if (signal?.aborted) return false;
    if (depth > maxDepth)
      fail("tooManyItems", "폴더 깊이가 제한을 초과했습니다.");
    const entries = (await fs.readdir(dir, { withFileTypes: true })).sort(
      (left, right) =>
        Number(right.isDirectory()) - Number(left.isDirectory()) ||
        left.name.localeCompare(right.name, undefined, { numeric: true }),
    );
    for (const entry of entries) {
      if (signal?.aborted) return false;
      if (++count > maxCount)
        fail("tooManyItems", "파일 수가 제한을 초과했습니다.");
      const full = path.join(dir, entry.name);
      if (
        entry.name.startsWith(".") ||
        entry.isSymbolicLink() ||
        PACKAGES.has(path.extname(entry.name).toLowerCase())
      )
        continue;
      if (entry.isDirectory()) {
        if ((await onEntry(full, entry, depth)) === false) return false;
        if ((await visit(full, depth + 1)) === false) return false;
      } else if ((await onEntry(full, entry, depth)) === false) return false;
    }
    return true;
  }
  return visit(root, 0);
}
export async function scan(
  root,
  {
    query,
    caseSensitive = false,
    limit = 1000,
    signal,
    maxFileBytes = 32 * 1024 * 1024,
    maxRetainedBytes = 64 * 1024 * 1024,
  } = {},
) {
  const safeRoot = await validateWithin(root, root),
    files = [],
    issues = [];
  maxFileBytes = Number.isSafeInteger(maxFileBytes) && maxFileBytes >= 0 ? maxFileBytes : 32 * 1024 * 1024;
  maxRetainedBytes = Number.isSafeInteger(maxRetainedBytes) && maxRetainedBytes >= 0 ? maxRetainedBytes : 64 * 1024 * 1024;
  let truncated = false,
    total = 0,
    cancelled = false,
    retainedBytes = 0;
  if (!query)
    return {
      files,
      issues: [{ path: root, message: "검색할 텍스트가 비어 있습니다." }],
      truncated,
      cancelled,
      complete: false,
    };
  try {
    const result = await directoryEntries(
      safeRoot,
      async (file, entry) => {
        if (entry.isDirectory()) return;
        if (!isMarkdownPath(file)) return;
        try {
          await regular(file);
          const stat = await fs.stat(file);
          if (stat.size > maxFileBytes) {
            issues.push({ path: file, message: "파일이 너무 커서 폴더 검색에서 제외했습니다." });
            return;
          }
          const handle = await fs.open(file, "r");
          let bytes;
          try {
            const buffer = Buffer.allocUnsafe(Math.min(maxFileBytes + 1, stat.size + 1));
            const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
            const afterStat = await handle.stat();
            if (bytesRead > maxFileBytes || afterStat.size !== bytesRead) {
              issues.push({ path: file, message: "파일이 너무 커서 폴더 검색에서 제외했습니다." });
              return;
            }
            bytes = buffer.subarray(0, bytesRead);
          } finally {
            await handle.close();
          }
          const codec = decode(bytes),
            item = { path: file, text: codec.originalText, hash: hash(bytes), codec },
            found = matches(
              item.text,
              query,
              caseSensitive,
              Math.max(0, limit - total) + 1,
            );
          if (found.length) {
            const accepted = found.slice(0, Math.max(0, limit - total));
            total += accepted.length;
            if (found.length > accepted.length) truncated = true;
            if (accepted.length) {
              const cost =
                Buffer.byteLength(item.text, "utf8") +
                Buffer.byteLength(item.codec.originalBase64, "ascii");
              if (retainedBytes + cost > maxRetainedBytes) {
                truncated = true;
                issues.push({ path: file, message: "검색 결과 보관 한도에 도달했습니다. 더 작은 폴더나 검색어를 사용해 주세요." });
                return false;
              }
              retainedBytes += cost;
              files.push({ ...item, matches: accepted });
            }
            if (truncated) return false;
          }
        } catch (e) {
          issues.push({ path: file, message: e.message ?? korean.unavailable });
        }
      },
      signal,
    );
    // `false` also means a deliberate result/retention bound was reached.
    cancelled = !!signal?.aborted;
  } catch (e) {
    if (e.code === "tooManyItems")
      issues.push({ path: safeRoot, message: e.message });
    else throw e;
  }
  return {
    files,
    issues,
    truncated,
    cancelled,
    complete: !truncated && !cancelled && issues.length === 0,
  };
}
export function preview(file, replacement) {
  return applyChanges(
    file.text ?? file.codec.originalText,
    file.matches.map((m) => ({ from: m.from, to: m.to, insert: replacement })),
  );
}
export async function applyPlan(
  planFiles,
  replacement,
  selectedPaths,
  root,
  store,
) {
  const chosen = new Set(selectedPaths ?? planFiles.map((f) => f.path));
  const activeStore = store ?? new Store(path.join(root, ".mymarkdown"));
  const outcomes = [];
  const pending = [];
  for (const file of planFiles) {
    if (!chosen.has(file.path)) {
      outcomes.push({ path: file.path, status: "excluded", message: null });
      continue;
    }
    try {
      await validateWithin(root, file.path);
      const now = await activeStore.read(file.path);
      if (now.hash !== file.hash) err("conflict");
      pending.push([file, preview(file, replacement)]);
    } catch (e) {
      outcomes.push({
        path: file.path,
        status: ["conflict", "deleted"].includes(e.code) ? "stale" : "failed",
        message: e.message,
      });
    }
  }
  if (outcomes.some((o) => o.status !== "excluded")) {
    for (const [file] of pending)
      outcomes.push({
        path: file.path,
        status: "notAttempted",
        message: "다른 선택 파일의 사전 확인이 실패해 적용하지 않았습니다.",
      });
    return {
      outcomes: planFiles.map((f) => outcomes.find((o) => o.path === f.path)),
      savedCount: 0,
    };
  }
  for (const [file, text] of pending) {
    try {
      await validateWithin(root, file.path);
      await activeStore.save(file.path, text, file.codec, file.hash);
      outcomes.push({ path: file.path, status: "saved", message: null });
    } catch (e) {
      outcomes.push({
        path: file.path,
        status: ["conflict", "deleted"].includes(e.code) ? "stale" : "failed",
        message: e.message,
      });
    }
  }
  return {
    outcomes: planFiles.map((f) => outcomes.find((o) => o.path === f.path)),
    savedCount: outcomes.filter((o) => o.status === "saved").length,
  };
}
export async function listTree(root) {
  const safeRoot = await validateWithin(root, root),
    tree = [];
  await directoryEntries(safeRoot, async (full, entry, depth) => {
    if (entry.isDirectory() || isMarkdownPath(entry.name))
      tree.push({
        path: full,
        name: entry.name,
        directory: entry.isDirectory(),
        depth,
      });
  });
  return tree;
}
async function collision(parent, name, source = null) {
  const names = await fs.readdir(parent);
  if (
    names.some(
      (n) =>
        n.toLocaleLowerCase() === name.toLocaleLowerCase() &&
        path.join(parent, n) !== source,
    )
  )
    err("alreadyExists");
}
export async function create(root, parent, name, directory) {
  validateName(name);
  if (!directory && !isMarkdownPath(name)) name += ".md";
  validateName(name);
  const safeParent = await validateWithin(root, parent);
  if (!(await fs.lstat(safeParent)).isDirectory()) err("unsafePath");
  const target = await validateWithin(root, path.join(safeParent, name), {
    allowMissing: true,
  });
  await collision(safeParent, name);
  if (directory) await fs.mkdir(target);
  else await fs.writeFile(target, "", { flag: "wx" });
  return target;
}
export async function duplicate(root, source) {
  const safeRoot = await validateWithin(root, root);
  const from = await validateWithin(safeRoot, source);
  if (from === safeRoot) err("rootProtected");
  const stat = await fs.lstat(from);
  if (stat.isSymbolicLink() || (!stat.isFile() && !stat.isDirectory())) err("unsafePath");
  const parent = await validateWithin(safeRoot, path.dirname(from));
  const ext = stat.isDirectory() ? "" : path.extname(from);
  const stem = stat.isDirectory() ? path.basename(from) : path.basename(from, ext);
  for (let index = 0; index < 100; index += 1) {
    const suffix = index ? ` 복사본 (${index + 1})` : " 복사본";
    const name = `${stem}${suffix}${ext}`;
    const target = await validateWithin(safeRoot, path.join(parent, name), { allowMissing: true });
    try { await collision(parent, name); }
    catch (error) { if (error.code === "alreadyExists") continue; throw error; }
    let ownsTarget = false;
    try {
      if (stat.isDirectory()) {
        // mkdir is exclusive: we only ever copy children into a directory this
        // operation created, so an existing directory can never be merged.
        await fs.mkdir(target);
        ownsTarget = true;
        for (const child of await fs.readdir(from))
          await fs.cp(path.join(from, child), path.join(target, child), { recursive: true, force: false, errorOnExist: true, verbatimSymlinks: true });
      } else {
        await fs.copyFile(from, target, fs.constants.COPYFILE_EXCL);
      }
      return target;
    } catch (error) {
      if (ownsTarget) {
        try { await fs.rm(target, { recursive: true, force: true }); }
        catch { fail("duplicateIncomplete", `${korean.duplicateIncomplete} 새 복제본 위치: ${target}`); }
        throw error;
      }
      if (["EEXIST", "ENOTEMPTY", "ERR_FS_CP_EEXIST"].includes(error.code)) continue;
      throw error;
    }
  }
  err("alreadyExists");
}
export async function move(root, source, destination) {
  const safeRoot = await validateWithin(root, root),
    from = await validateWithin(safeRoot, source),
    to = await validateWithin(safeRoot, destination, { allowMissing: true });
  if (from === safeRoot) err("rootProtected");
  validateName(path.basename(to));
  const stat = await fs.lstat(from),
    parent = await validateWithin(safeRoot, path.dirname(to));
  if (!(await fs.lstat(parent)).isDirectory()) err("unsafePath");
  if (stat.isDirectory() && inside(from, to)) err("invalidMove");
  await collision(parent, path.basename(to), from);
  const caseOnly =
    path.dirname(from) === path.dirname(to) &&
    path.basename(from).toLocaleLowerCase() ===
      path.basename(to).toLocaleLowerCase() &&
    path.basename(from) !== path.basename(to);
  if (!caseOnly) {
    await fs.rename(from, to);
    return to;
  }
  const temp = path.join(
    path.dirname(from),
    `.mymarkdown-rename-${randomUUID()}`,
  );
  await fs.rename(from, temp);
  try {
    await fs.rename(temp, to);
  } catch (e) {
    try {
      await fs.rename(temp, from);
    } catch {
      fail(
        "renameRecoveryRequired",
        `이름 변경을 되돌리지 못했습니다. 파일은 ${temp}에 남아 있습니다.`,
      );
    }
    fail(
      "renameFailed",
      "대소문자만 바꾸는 이름 변경을 완료하지 못했습니다. 원래 이름으로 되돌렸습니다.",
    );
  }
  return to;
}
