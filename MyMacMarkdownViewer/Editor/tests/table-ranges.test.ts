import { describe, expect, it } from 'vitest';
import { parseTable, withTableColumn, withTableRow, escapeCellPipes } from '../src/table';
const edit = (source: string, row: number, column: number, text: string) => {
 const cell = parseTable(source, 0)!.cells[row][column];
 return source.slice(0, cell.from) + text + source.slice(cell.to);
};
describe('table edits keep adjacent cell bytes', () => {
 it('places text inside empty cells instead of before the table edge', () => {
  const source = '| A | B |\n| - | - |\n|  |  |';
  expect(edit(source, 2, 0, '한글')).toBe('| A | B |\n| - | - |\n|  한글|  |');
  expect(edit(source, 2, 1, '둘째')).toBe('| A | B |\n| - | - |\n|  |  둘째|');
 });
 it('distinguishes repeated values, zero-width cells and CRLF offsets', () => {
  const source = '| A | A |\r\n| :- | -: |\r\n||A|';
  expect(edit(source, 0, 1, 'B')).toBe(source.replace('| A | A |', '| A | B |'));
  expect(edit(source, 2, 0, 'X')).toBe(source.replace('||A|', '|X|A|'));
 });
 it('splits only pipes preceded by an even number of backslashes', () => {
  const source = String.raw`| A | B |
| --- | --- |
| a\|b | c\\|`;
  const table = parseTable(source, 0)!;
  expect(table.rows[2]).toEqual([String.raw`a\|b`, String.raw`c\\`]);
  expect(edit(source, 2, 0, 'X')).toBe(source.replace(String.raw`a\|b`, 'X'));
 });
 it('preserves a trailing escaped pipe when outer pipes are omitted', () => {
  const source = String.raw`A | B
-- | --
a | b\|`;
  expect(parseTable(source, 0)!.rows[2]).toEqual(['a', String.raw`b\|`]);
 });
});

it('pads missing cells before column operations and can remove the last body row', () => {
 const table = parseTable('A | B | C\n- | - | -\none', 0)!;
 expect(withTableColumn(table, 'delete', 1).rows[2]).toEqual(['one', '']);
 expect(withTableColumn(table, 'add', 1).rows[2]).toEqual(['one', '', '', '']);
 expect(withTableRow(table, 'delete', 2).rows.length).toBe(2);
 expect(escapeCellPipes('a|b')).toBe(String.raw`a\|b`);
 expect(escapeCellPipes(String.raw`a\|b`)).toBe(String.raw`a\|b`);
});
