function normalizedPath(value) {
  if (typeof value !== "string" || !value) return "";
  let result = value.replace(/\\/g, "/");
  const windowsPath = /^[a-z]:\//i.test(result) || result.startsWith("//");
  if (windowsPath) result = result.toLocaleLowerCase("en-US");
  const driveRoot = /^[a-z]:\/$/i.test(result);
  while (result.length > 1 && result.endsWith("/") && !driveRoot)
    result = result.slice(0, -1);
  return result;
}

export function sameTreePath(left, right) {
  const a = normalizedPath(left);
  return !!a && a === normalizedPath(right);
}

export function isPathWithinRoot(filePath, rootPath) {
  const file = normalizedPath(filePath);
  const root = normalizedPath(rootPath);
  if (!file || !root) return false;
  return file === root || file.startsWith(root.endsWith("/") ? root : `${root}/`);
}

export function findFileEntry(filePath, entries = []) {
  const target = normalizedPath(filePath);
  if (!target) return null;
  return entries.find((entry) => !entry.directory && normalizedPath(entry.path) === target) || null;
}

function parentPath(value) {
  const path = normalizedPath(value);
  if (!path || /^[a-z]:\/$/i.test(path) || path === "/") return null;
  const separator = path.lastIndexOf("/");
  if (separator < 0) return null;
  if (separator === 0) return "/";
  if (separator === 2 && /^[a-z]:\//i.test(path)) return path.slice(0, 3);
  return path.slice(0, separator);
}

// Returns known directory rows from the opened root down to the file's parent.
// Missing ancestors are rejected so a stale tree can never be expanded halfway.
export function knownAncestorDirectories(filePath, rootPath, entries = []) {
  if (!isPathWithinRoot(filePath, rootPath) || sameTreePath(filePath, rootPath))
    return null;
  const root = normalizedPath(rootPath);
  const directories = new Map(
    entries
      .filter((entry) => entry.directory)
      .map((entry) => [normalizedPath(entry.path), entry]),
  );
  const ancestors = [];
  let parent = parentPath(filePath);
  while (parent && parent !== root) {
    const entry = directories.get(parent);
    if (!entry) return null;
    ancestors.push(entry.path);
    parent = parentPath(parent);
  }
  if (parent !== root) return null;
  return ancestors.reverse();
}
