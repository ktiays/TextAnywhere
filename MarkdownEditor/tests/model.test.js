/*
 * Created by ktiays on 2026/10/23.
 * Copyright (c) 2026 ktiays. All rights reserved.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import '../src/model.js';

const { Model, parse } = globalThis.MarkdownModel;

test('rendering keeps the source and maps visible UTF-16 offsets back to it', () => {
  const source = '# 标题\n\n- [ ] 任务\n\n你好 **世界** 🌏\n';
  const model = new Model(source);
  assert.equal(model.markdown, source);
  assert.equal(model.document.lines[4].text, '你好 世界 🌏');
  model.handle({ action: 'type', line: 4, offset: 3, text: '美丽的', insideFormatting: true });
  assert.equal(model.markdown, '# 标题\n\n- [ ] 任务\n\n你好 **美丽的世界** 🌏\n');
});

test('enter continues lists, tab indents, and backspace removes the marker before joining', () => {
  const model = new Model('- first');
  model.handle({ action: 'enter', line: 0, offset: 5 });
  assert.equal(model.markdown, '- first\n- ');
  model.handle({ action: 'type', line: 1, offset: 0, text: 'second' });
  model.handle({ action: 'tab', line: 1, offset: 3 });
  assert.equal(model.markdown, '- first\n  - second');
  model.handle({ action: 'tab', line: 1, offset: 3, shift: true });
  assert.equal(model.markdown, '- first\n- second');
  model.handle({ action: 'backspace', line: 1, offset: 0 });
  assert.equal(model.markdown, '- first\nsecond');
  model.handle({ action: 'backspace', line: 1, offset: 0 });
  assert.equal(model.markdown, '- firstsecond');
});

test('enter on an empty list item ends the list, and ordered markers count up', () => {
  const model = new Model('- [x] task');
  model.handle({ action: 'enter', line: 0, offset: 4 });
  assert.equal(model.markdown, '- [x] task\n- [ ] ');
  model.handle({ action: 'enter', line: 1, offset: 0 });
  assert.equal(model.markdown, '- [x] task\n');
  model.setMarkdown('9. item');
  model.handle({ action: 'enter', line: 0, offset: 4 });
  assert.equal(model.markdown, '9. item\n10. ');
});

test('deleting formatted characters keeps the delimiters intact', () => {
  const model = new Model('a **bold** z');
  model.handle({ action: 'backspace', line: 0, offset: 6 });
  assert.equal(model.markdown, 'a **bol** z');
  model.handle({ action: 'delete', line: 0, offset: 2 });
  assert.equal(model.markdown, 'a **ol** z');
  model.handle({ action: 'paste', line: 0, offset: 2, text: 'new', selStartLine: 0, selStartOffset: 2, selEndLine: 0, selEndOffset: 4 });
  assert.equal(model.markdown, 'a new z');
});

test('backspace removes a whole surrogate pair', () => {
  const model = new Model('A🌏');
  model.handle({ action: 'backspace', line: 0, offset: 3 });
  assert.equal(model.markdown, 'A');
});

test('multiline paste is undoable and redoable', () => {
  const model = new Model('# Title\n\nHello **world**');
  model.handle({ action: 'paste', text: 'new\ntext', selStartLine: 0, selStartOffset: 2, selEndLine: 2, selEndOffset: 5 });
  assert.equal(model.markdown, '# Tinew\ntext **world**');
  model.handle({ action: 'undo' });
  assert.equal(model.markdown, '# Title\n\nHello **world**');
  model.handle({ action: 'redo' });
  assert.equal(model.markdown, '# Tinew\ntext **world**');
});

test('checkboxes toggle their source state', () => {
  const model = new Model('- [ ] task');
  model.handle({ action: 'checkbox', line: 0, checked: true });
  assert.equal(model.markdown, '- [x] task');
});

test('copying a whole span includes its delimiters', () => {
  const model = new Model('**bold** and _italic_');
  assert.equal(model.selectedMarkdown({ selStartLine: 0, selStartOffset: 0, selEndLine: 0, selEndOffset: 4 }), '**bold**');
});

test('the cursor reports which side of a formatting boundary it is on', () => {
  const model = new Model('');
  model.handle({ action: 'type', line: 0, offset: 0, text: '**abc*' });
  model.handle({ action: 'type', line: 0, offset: 6, text: '*' });
  assert.equal(model.markdown, '**abc**');
  assert.deepEqual(model.cursor, { line: 0, offset: 3, inside: false });
  model.handle({ action: 'type', line: 0, offset: 3, insideFormatting: false, text: ' plain' });
  assert.equal(model.markdown, '**abc** plain');

  model.setMarkdown('**abc**');
  model.handle({ action: 'type', line: 0, offset: 3, insideFormatting: true, text: 'd' });
  assert.equal(model.markdown, '**abcd**');
  assert.equal(model.cursor.inside, true);
});

test('toggling inline formatting wraps and unwraps the selection', () => {
  const model = new Model('hello world');
  const selection = { startLine: 0, startOffset: 0, endLine: 0, endOffset: 5 };
  model.toggleInline('bold', selection);
  assert.equal(model.markdown, '**hello** world');
  model.toggleInline('bold', selection);
  assert.equal(model.markdown, 'hello world');
});

test('tables and code fences keep their lines and escape markup', () => {
  const source = '| A | B |\n| --- | ---: |\n| **C** | D |\n\n```html\n<script>alert(1)</script>\n```';
  const document = parse(source);
  assert.equal(document.lines.length, 7);
  assert.ok(document.html.includes('class="md-table"'));
  assert.ok(document.html.includes('data-align="right"'));
  assert.ok(document.html.includes('&lt;script&gt;'));
  assert.ok(!document.html.includes('<script>'));
  assert.equal(document.lines[2].text, '| C | D |');
});

test('HTML, script links and images never become live markup', () => {
  const html = parse('<img src=x onerror=alert(1)>\n[link](javascript:alert(1))\n![image](https://example.com/a.png)').html;
  assert.ok(!html.includes('<img '));
  assert.ok(!html.includes('href="javascript:'));
  assert.ok(html.includes('&lt;img'));
});
