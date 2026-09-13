import { describe, expect, it } from 'vitest';
import { codeFenceInfo, codeLanguageLabel, codeLanguageOptions } from '../src/codeLanguage';

describe('fence language metadata', () => {
  it('changes only the language word and preserves fence, indentation, metadata and CRLF', () => {
    const source = '  ~~~~  py  title="Example"\r\nprint("body")\r\n  ~~~~';
    const info = codeFenceInfo(source)!;
    expect(info.language).toBe('py');
    expect(source.slice(0, info.from) + 'javascript' + source.slice(info.to))
      .toBe('  ~~~~  javascript  title="Example"\r\nprint("body")\r\n  ~~~~');
  });

  it('can add an absent language without consuming the newline or code body', () => {
    const source = '```  \nbody\n```';
    const info = codeFenceInfo(source)!;
    expect(info).toEqual({ language: '', from: 5, to: 5 });
    expect(source.slice(0, info.from) + 'python' + source.slice(info.to))
      .toBe('```  python\nbody\n```');
  });

  it('does not treat indented code or a malformed fence as a language declaration', () => {
    for (const source of ['    ```python\nbody', 'ordinary text', '``python', '```py`thon\nbody']) {
      expect(codeFenceInfo(source)).toBeNull();
    }
  });

  it('keeps unknown tokens unchanged and labels aliases without rewriting source', () => {
    expect(codeLanguageLabel('')).toBe('텍스트');
    expect(codeLanguageLabel('PY')).toBe('python');
    expect(codeLanguageLabel('plaintext')).toBe('텍스트');
    expect(codeLanguageLabel('my-language')).toBe('my-language');
    expect(codeFenceInfo('```custom<&>\nbody\n```')?.language).toBe('custom<&>');
    expect(new Set(codeLanguageOptions.map(option => option.value)).size).toBe(codeLanguageOptions.length);
  });
});
