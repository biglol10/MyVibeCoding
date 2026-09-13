/** Offsets are relative to the supplied fenced block, never the whole document. */
export interface CodeFenceInfo { language: string; from: number; to: number }

/** Read only the first info word so changing it preserves fence and other metadata. */
export function codeFenceInfo(source: string): CodeFenceInfo | null {
  const opening = /^( {0,3})(`{3,}|~{3,})([^\r\n]*)/.exec(source);
  if (!opening) return null;
  const info = opening[3];
  // Backticks inside a backtick fence's info string make it an ordinary paragraph.
  if (opening[2][0] === '`' && info.includes('`')) return null;
  const whitespace = /^[\t ]*/.exec(info)![0].length;
  const from = opening[1].length + opening[2].length + whitespace;
  const language = /^[^\s]*/.exec(info.slice(whitespace))![0];
  return { language, from, to: from + language.length };
}

export const codeLanguageOptions: readonly { value: string; label: string }[] = [
  { value: '', label: '텍스트' },
  { value: 'python', label: 'python' },
  { value: 'javascript', label: 'javascript' },
  { value: 'typescript', label: 'typescript' },
  { value: 'json', label: 'json' },
  { value: 'bash', label: 'bash' },
  { value: 'html', label: 'html' },
  { value: 'css', label: 'css' },
  { value: 'sql', label: 'sql' },
  { value: 'yaml', label: 'yaml' },
  { value: 'swift', label: 'swift' },
  { value: 'mermaid', label: 'mermaid' },
];

const aliases: Readonly<Record<string, string>> = {
  py: 'python', js: 'javascript', ts: 'typescript',
  sh: 'bash', shell: 'bash', yml: 'yaml',
  text: '텍스트', txt: '텍스트', plaintext: '텍스트',
};

export function codeLanguageLabel(language: string): string {
  const name = language.trim();
  if (!name) return '텍스트';
  const lower = name.toLowerCase();
  return aliases[lower] ?? codeLanguageOptions.find(option => option.value === lower)?.label ?? name;
}
