/** Deliberately small GFM table model. Structural operations only run after the
 * parser identified a Table block; cell edits retain the original source. */
export interface TableCell { from: number; to: number; text: string; row: number; column: number }
export interface MarkdownTable { from: number; to: number; rows: string[][]; cells: TableCell[][]; alignments: Array<'left' | 'center' | 'right' | 'none'> }

function rowCells(line: string, offset: number, row: number): TableCell[] {
  const delimiters: number[] = [];
  let escaped = false;
  for (let index = 0; index < line.length; index++) {
    const char = line[index];
    if (char === "\\") { escaped = !escaped; continue; }
    if (char === '|' && !escaped) delimiters.push(index);
    escaped = false;
  }
  let start = 0, end = line.length;
  if (delimiters.length && !line.slice(0, delimiters[0]).trim()) start = delimiters.shift()! + 1;
  if (delimiters.length && !line.slice(delimiters.at(-1)! + 1).trim()) end = delimiters.pop()!;
  const result: TableCell[] = [];
  for (const stop of [...delimiters, end]) {
    const raw = line.slice(start, stop);
    const leading = /^\s*/.exec(raw)![0].length;
    const trailing = /\s*$/.exec(raw)![0].length;
    const from = start + leading, to = Math.max(from, stop - trailing);
    result.push({ from: offset + from, to: offset + to, text: line.slice(from, to), row, column: result.length });
    start = stop + 1;
  }
  return result;
}

function alignment(value: string): 'left' | 'center' | 'right' | 'none' {
  const trimmed = value.trim();
  if (!/^:?-+:?$/.test(trimmed)) return 'none';
  if (trimmed.startsWith(':') && trimmed.endsWith(':')) return 'center';
  if (trimmed.startsWith(':')) return 'left';
  if (trimmed.endsWith(':')) return 'right';
  return 'none';
}

export function parseTable(source: string, from: number): MarkdownTable | undefined {
  const rawLines = source.split('\n');
  if (rawLines.at(-1) === '') rawLines.pop();
  if (rawLines.length < 2 || rawLines.some(line => !line.trim())) return undefined;
  const cells: TableCell[][] = [];
  let offset = from;
  for (let row = 0; row < rawLines.length; row++) {
    cells.push(rowCells(rawLines[row].replace(/\r$/, ''), offset, row));
    offset += rawLines[row].length + 1;
  }
  const rows = cells.map(row => row.map(cell => cell.text)), columns = rows[0].length;
  if (columns < 1 || rows[1].length !== columns || rows[1].some(cell => !/^:?-+:?$/.test(cell))) return undefined;
  return { from, to: from + source.length, rows, cells, alignments: rows[1].map(alignment) };
}

function separator(alignment: MarkdownTable['alignments'][number]) {
  return alignment === 'left' ? ':---' : alignment === 'center' ? ':---:' : alignment === 'right' ? '---:' : '---';
}

export function serializeTable(table: MarkdownTable) {
  const width = Math.max(...table.rows.map(row => row.length));
  return table.rows.map((row, index) => `| ${Array.from({ length: width }, (_, column) => index === 1 ? separator(table.alignments[column] ?? 'none') : row[column] ?? '').join(' | ')} |`).join('\n');
}

export function withTableRow(table: MarkdownTable, action: 'add' | 'delete', row: number) {
  const rows = table.rows.map(values => [...values]);
  if (action === 'add') rows.splice(Math.max(2, Math.min(rows.length, row + 1)), 0, Array(rows[0].length).fill(''));
  else if (row >= 2 && row < rows.length) rows.splice(row, 1);
  return { ...table, rows };
}

export function withTableColumn(table: MarkdownTable, action: 'add' | 'delete', column: number) {
  const width = table.rows[0].length;
  if (action === 'delete' && width <= 1) return table;
  const at = Math.max(0, Math.min(width - 1, column));
  const rows = table.rows.map(values => Array.from({ length: Math.max(width, values.length) }, (_, index) => values[index] ?? ''));
  const alignments = [...table.alignments];
  if (action === 'add') {
    rows.forEach(row => row.splice(at + 1, 0, ''));
    alignments.splice(at + 1, 0, 'none');
  } else {
    rows.forEach(row => row.splice(at, 1));
    alignments.splice(at, 1);
  }
  return { ...table, rows, alignments };
}

export function escapeCellPipes(text: string) {
  let result = '', backslashes = 0;
  for (const char of text.replace(/[\r\n]+/g, ' ')) {
    if (char === '|' && backslashes % 2 === 0) result += "\\";
    result += char;
    backslashes = char === "\\" ? backslashes + 1 : 0;
  }
  return result;
}

export function withTableAlignment(table: MarkdownTable, column: number, value: MarkdownTable['alignments'][number]) {
  const alignments = [...table.alignments]; alignments[column] = value;
  return { ...table, alignments };
}
