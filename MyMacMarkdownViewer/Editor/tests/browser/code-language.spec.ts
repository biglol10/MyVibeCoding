import { test, expect, type Page } from '@playwright/test';

const source = `앞 문단\n\n\`\`\`python title="keep"\ndef greet(name):\n    return name\n\`\`\`\n\n뒤 문단\n\n\`\`\`\nplain body\n\`\`\`\n\n\`\`\`custom-lang extra\ncustom body\n\`\`\`\n\n    indented body\n\n\`\`\`mermaid\ngraph LR\n A --> B\n\`\`\`\n`;

const text = (page: Page) => page.evaluate(() => window.__editorTest!.snapshot().text);

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await page.waitForFunction(() => !!window.__editorTest);
  await page.evaluate(source => window.__editorTest!.load(source), source);
});

test('language headers preserve fences and body through selection, undo, redo, locks, and Mermaid', async ({ page }) => {
  const language = page.getByRole('combobox', { name: '코드 언어', exact: true });
  await expect(language).toHaveCount(4);
  await expect(language.nth(0)).toHaveValue('python');
  await expect(language.nth(1)).toHaveValue('');
  await expect(language.nth(2)).toHaveValue('custom-lang');
  await expect(language.nth(3)).toHaveValue('mermaid');
  await expect(page.locator('.code-language-label', { hasText: '텍스트' })).toHaveCount(1);
  for (const theme of ['light', 'dark', 'night'] as const) {
    await page.evaluate(theme => window.__editorTest!.settings({ theme }), theme);
    await expect(language.nth(0)).toBeVisible();
    const colors = await language.nth(0).evaluate(select => {
      const style = getComputedStyle(select);
      return { color: style.color, background: style.backgroundColor, border: style.borderColor };
    });
    expect(colors.color).not.toBe(colors.background);
    expect(colors.border).not.toBe(colors.background);
  }
  await page.screenshot({ path: 'test-results/code-language-night.png', fullPage: true });

  await language.nth(0).selectOption('javascript');
  const javascript = source.replace('```python title="keep"', '```javascript title="keep"');
  expect(await text(page)).toBe(javascript);
  await expect(page.locator('pre code').filter({ hasText: 'def greet' })).toHaveClass(/language-javascript/);
  await page.evaluate(() => window.__editorTest!.command('undo'));
  expect(await text(page)).toBe(source);
  await page.evaluate(() => window.__editorTest!.command('redo'));
  expect(await text(page)).toBe(javascript);

  await language.nth(0).selectOption('');
  const plainWithMetadata = javascript.replace('```javascript title="keep"', '```text title="keep"');
  expect(await text(page)).toBe(plainWithMetadata);
  await page.evaluate(() => window.__editorTest!.command('undo'));
  expect(await text(page)).toBe(javascript);

  // Selecting Mermaid keeps the control outside the rendered diagram, and a
  // later source edit never changes a neighbouring fenced block.
  await language.nth(0).selectOption('mermaid');
  const mermaid = javascript.replace('```javascript title="keep"', '```mermaid title="keep"');
  expect(await text(page)).toBe(mermaid);
  await expect(page.locator('.diagram-block').first()).toBeVisible();
  await page.getByRole('button', { name: '다이어그램 편집', exact: true }).first().click();
  await expect(page.getByRole('combobox', { name: '코드 언어', exact: true }).first()).toHaveValue('mermaid');
  expect(await text(page)).toBe(mermaid);

  await page.evaluate(() => {
    const snapshot = window.__editorTest!.snapshot();
    window.MarkdownHost.receive({ type: 'lock', sessionID: snapshot.sessionID, documentID: snapshot.documentID, locked: true });
  });
  await expect(page.getByRole('combobox', { name: '코드 언어', exact: true }).first()).toBeDisabled();
  expect(await text(page)).toBe(mermaid);
});

test('code surface and following prose retain their viewport positions on entering and leaving edit', async ({ page }) => {
  const positioned = Array.from({ length: 20 }, (_, index) => `앞 줄 ${index}`).join('\n')
    + `\n\nBEFORE_MARKER\n\n\`\`\`python\ndef greet(name):\n    return name\n\`\`\`\n\nAFTER_MARKER\n\n`
    + Array.from({ length: 30 }, (_, index) => `뒤 줄 ${index}`).join('\n');
  await page.evaluate(async source => {
    window.__editorTest!.load(source);
    // Loading restores a document's initial scroll in animation frames. Start
    // measuring after it settles, then position the already-open document.
    await new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
    document.querySelector<HTMLElement>('.cm-scroller')!.scrollTop = 240;
    await new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
  }, positioned);
  const reading = await page.locator('pre').filter({ hasText: 'def greet' }).evaluate(pre => {
    const after = [...document.querySelectorAll<HTMLElement>('.cm-line.md-prose')].find(line => line.textContent === 'AFTER_MARKER')!;
    const scroller = document.querySelector<HTMLElement>('.cm-scroller')!;
    return { code: pre.getBoundingClientRect().toJSON(), after: after.getBoundingClientRect().toJSON(), scrollTop: scroller.scrollTop };
  });
  await page.locator('pre code').filter({ hasText: 'def greet' }).click();
  const editing = await page.locator('.code-source-line').filter({ hasText: 'def greet' }).first().evaluate(line => {
    const after = [...document.querySelectorAll<HTMLElement>('.cm-line.md-prose')].find(item => item.textContent === 'AFTER_MARKER')!;
    const scroller = document.querySelector<HTMLElement>('.cm-scroller')!;
    return { code: line.getBoundingClientRect().toJSON(), after: after.getBoundingClientRect().toJSON(), scrollTop: scroller.scrollTop };
  });
  expect(Math.abs(editing.code.top - reading.code.top)).toBeLessThan(1);
  expect(Math.abs(editing.after.top - reading.after.top)).toBeLessThan(1);
  expect(Math.abs(editing.scrollTop - reading.scrollTop)).toBeLessThan(1);

  await page.evaluate(() => window.__editorTest!.select(0));
  const exited = await page.locator('pre').filter({ hasText: 'def greet' }).evaluate(pre => {
    const after = [...document.querySelectorAll<HTMLElement>('.cm-line.md-prose')].find(line => line.textContent === 'AFTER_MARKER')!;
    return { code: pre.getBoundingClientRect().toJSON(), after: after.getBoundingClientRect().toJSON() };
  });
  expect(Math.abs(exited.code.top - reading.code.top)).toBeLessThan(1);
  expect(Math.abs(exited.after.top - reading.after.top)).toBeLessThan(1);
});

test('a spaced fence changes between Mermaid and code without losing its info spacing', async ({ page }) => {
  const spaced = `\`\`\`  python\ngraph LR\n A --> B\n\`\`\`\n\n끝\n`;
  await page.evaluate(source => { window.__editorTest!.load(source); window.__editorTest!.select(source.indexOf('끝')); }, spaced);
  const language = page.getByRole('combobox', { name: '코드 언어', exact: true });
  await language.selectOption('mermaid');
  const mermaid = spaced.replace('```  python', '```  mermaid');
  expect(await text(page)).toBe(mermaid);
  await expect(page.locator('.diagram-block svg')).toBeVisible();
  await language.selectOption('javascript');
  const javascript = spaced.replace('```  python', '```  javascript');
  expect(await text(page)).toBe(javascript);
  await expect(page.locator('pre code')).toHaveClass(/language-javascript/);
});

test('picker focus cannot type into source and Mod+Z undoes a language change', async ({ page }) => {
  const keyboard = `\`\`\`python\nconst keyboardValue = 1;\n\`\`\`\n\n끝\n`;
  await page.evaluate(source => { window.__editorTest!.load(source); window.__editorTest!.select(source.indexOf('끝')); }, keyboard);
  const language = page.getByRole('combobox', { name: '코드 언어', exact: true });
  await language.focus();
  await page.keyboard.insertText('x');
  expect(await text(page)).toBe(keyboard);
  await language.selectOption('javascript');
  const javascript = keyboard.replace('```python', '```javascript');
  expect(await text(page)).toBe(javascript);
  expect(await page.evaluate(() => document.activeElement?.tagName)).toBe('SELECT');
  await page.keyboard.press('Meta+z');
  expect(await text(page)).toBe(keyboard);
  expect(await page.evaluate(() => document.activeElement?.tagName)).toBe('SELECT');
  await page.keyboard.press('Meta+Shift+z');
  expect(await text(page)).toBe(javascript);
});

test('a nested fenced block has its own picker and changes only its language token', async ({ page }) => {
  const nested = `- 목록 바깥\n\n  \`\`\`py title="nested"\n  print("nested")\n  \`\`\`\n\n\`\`\`python\nprint("sibling")\n\`\`\`\n`;
  await page.evaluate(source => { window.__editorTest!.load(source); window.__editorTest!.select(source.indexOf('sibling')); }, nested);
  const nestedPicker = page.locator('li .code-language-select');
  await expect(nestedPicker).toHaveCount(1);
  await expect(nestedPicker).toHaveValue('python');
  await nestedPicker.selectOption('javascript');
  const changed = nested.replace('  ```py title="nested"', '  ```javascript title="nested"');
  expect(await text(page)).toBe(changed);
  await expect(page.locator('.code-source-line').filter({ hasText: 'print("sibling")' })).toBeVisible();

  await page.locator('pre code').filter({ hasText: 'nested' }).click();
  const editingPicker = page.locator('.code-language-line .code-language-select');
  await expect(editingPicker).toHaveValue('javascript');
  await editingPicker.selectOption('json');
  expect(await text(page)).toBe(changed.replace('  ```javascript title="nested"', '  ```json title="nested"'));
  await expect(page.locator('.code-source-line').filter({ hasText: 'print("nested")' })).toBeVisible();
});

test('blockquote and deep-list fences preserve their container prefixes', async ({ page }) => {
  const nested = `> 인용문\n>\n> \`\`\`py title="quote"\n> print("quote")\n> \`\`\`\n\n- 바깥\n  - 안쪽\n\n    \`\`\`py title="deep"\n    print("deep")\n    \`\`\`\n\n끝\n`;
  await page.evaluate(source => { window.__editorTest!.load(source); window.__editorTest!.select(source.indexOf('끝')); }, nested);
  const language = page.getByRole('combobox', { name: '코드 언어', exact: true });
  await expect(language).toHaveCount(2);
  await language.nth(0).selectOption('javascript');
  await language.nth(1).selectOption('json');
  expect(await text(page)).toBe(nested
    .replace('> ```py title="quote"', '> ```javascript title="quote"')
    .replace('    ```py title="deep"', '    ```json title="deep"'));
});

test('the second nested header follows preceding document edits and changes only its fence', async ({ page }) => {
  const nested = `- 모음\n\n  \`\`\`python title="first"\n  print("first")\n  \`\`\`\n\n  \`\`\`py title="second"\n  print("second")\n  \`\`\`\n\n끝\n`;
  await page.evaluate(source => {
    window.__editorTest!.load(source); window.__editorTest!.select(source.indexOf('끝'));
    window.__editorTest!.select(0); window.__editorTest!.insert('앞 문단\n\n');
    window.__editorTest!.select(window.__editorTest!.snapshot().text.indexOf('끝'));
  }, nested);
  const changed = `앞 문단\n\n${nested}`;
  const language = page.locator('li .code-language-select');
  await expect(language).toHaveCount(2);
  await language.nth(1).selectOption('json');
  expect(await text(page)).toBe(changed.replace('  ```py title="second"', '  ```json title="second"'));
  expect((await text(page)).match(/```python title="first"/g)).toHaveLength(1);
});

test('code headers keep their coordinates at every font size at document start, middle, and end', async ({ page }) => {
  const cases = [
    { name: 'start', source: `\`\`\`python\nconst positionValue = 1;\n\`\`\`\n\nAFTER_MARKER\n`, exit: 'AFTER_MARKER', scroll: 0 },
    { name: 'middle', source: `${Array.from({ length: 18 }, (_, index) => `앞 줄 ${index}`).join('\n')}\n\n\`\`\`python\nconst positionValue = 1;\n\`\`\`\n\nAFTER_MARKER\n\n${Array.from({ length: 18 }, (_, index) => `뒤 줄 ${index}`).join('\n')}`, exit: 'AFTER_MARKER', scroll: 240 },
    { name: 'end', source: `BEFORE_MARKER\n\n\`\`\`python\nconst positionValue = 1;\n\`\`\`\n\n\n`, exit: 'BEFORE_MARKER', scroll: Number.MAX_SAFE_INTEGER },
    { name: 'indented', source: `    const positionValue = 1;\n\nAFTER_MARKER\n`, exit: 'AFTER_MARKER', scroll: 0 },
  ];
  for (const fontSize of [12, 17, 30]) {
    for (const entry of cases) {
      await page.evaluate(([source, fontSize, scroll]) => {
        window.__editorTest!.settings({ fontSize }); window.__editorTest!.load(source);
        window.__editorTest!.select(source.indexOf('AFTER_MARKER') >= 0 ? source.indexOf('AFTER_MARKER') : source.indexOf('BEFORE_MARKER'));
        const scroller = document.querySelector<HTMLElement>('.cm-scroller')!; scroller.scrollTop = scroll;
      }, [entry.source, fontSize, entry.scroll]);
      const preview = page.locator('pre').filter({ hasText: 'positionValue' });
      await preview.scrollIntoViewIfNeeded();
      const reading = await preview.evaluate(pre => {
        const scroller = document.querySelector<HTMLElement>('.cm-scroller')!;
        const marker = [...document.querySelectorAll<HTMLElement>('.cm-line.md-prose')].find(line => line.textContent === 'AFTER_MARKER');
        return { top: pre.getBoundingClientRect().top, scrollTop: scroller.scrollTop, after: marker?.getBoundingClientRect().top };
      });
      await page.locator('pre code').filter({ hasText: 'positionValue' }).click();
      const editing = await page.locator('.cm-line').filter({ hasText: 'positionValue' }).evaluate(line => {
        const scroller = document.querySelector<HTMLElement>('.cm-scroller')!;
        const marker = [...document.querySelectorAll<HTMLElement>('.cm-line.md-prose')].find(item => item.textContent === 'AFTER_MARKER');
        return { top: line.getBoundingClientRect().top, scrollTop: scroller.scrollTop, after: marker?.getBoundingClientRect().top };
      });
      expect(Math.abs(editing.top - reading.top), `${entry.name} ${fontSize}px code top`).toBeLessThan(1);
      expect(Math.abs(editing.scrollTop - reading.scrollTop), `${entry.name} ${fontSize}px scroll`).toBeLessThan(1);
      if (reading.after !== undefined) expect(Math.abs(editing.after! - reading.after), `${entry.name} ${fontSize}px following prose`).toBeLessThan(1);
      await page.evaluate(exit => window.__editorTest!.select(window.__editorTest!.snapshot().text.indexOf(exit)), entry.exit);
      const exited = await page.locator('pre').filter({ hasText: 'positionValue' }).evaluate(pre => pre.getBoundingClientRect().top);
      expect(Math.abs(exited - reading.top), `${entry.name} ${fontSize}px exit`).toBeLessThan(1);
    }
  }
});
