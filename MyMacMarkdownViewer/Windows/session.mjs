import path from 'node:path';

export function readingPosition(value = {}, length = Number.MAX_SAFE_INTEGER) {
  const offset = value => Number.isFinite(value) ? Math.floor(Math.min(length, Math.max(0, value))) : 0;
  const anchor = offset(value?.anchor);
  return { anchor, head: offset(value?.head ?? anchor),
    scrollTop: Number.isFinite(value?.scrollTop) ? Math.min(100000000, Math.max(0, value.scrollTop)) : 0 };
}
export function lastSession(saved) {
  const session = saved?.session;
  return { documentPath: typeof session?.documentPath === 'string' && path.isAbsolute(session.documentPath) ? session.documentPath : null,
    position: readingPosition(session?.position), blank: session?.blank === true };
}
export function documentArgument(argv) {
  for (let index = 1; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === '--qa-data') { index++; continue; }
    if (arg === '--open') {
      const value = argv[++index];
      if (value && !value.startsWith('-') && /\.(md|markdown)$/i.test(value)) return path.resolve(value);
      continue;
    }
    if (!arg.startsWith('-') && path.isAbsolute(arg) && /\.(md|markdown)$/i.test(arg)) return path.resolve(arg);
  }
  return null;
}
