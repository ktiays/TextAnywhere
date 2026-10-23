/*
 * Created by ktiays on 2026/10/23.
 * Copyright (c) 2026 ktiays. All rights reserved.
 *
 * Bundles the editor into a single self-contained HTML file for the app bundle.
 * `--check` fails when the committed bundle is out of date instead of writing it.
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const output = join(root, '..', 'TextAnywhere', 'Resources', 'MarkdownEditor.html');
const read = (path) => readFileSync(join(root, path), 'utf8');

const styles = read('src/editor.css');
const scripts = ['src/model.js', 'src/editor.js'].map(read).join('\n;\n').replace(/<\/script/gi, '<\\/script');
const html = read('src/editor.html')
  .replace('/*__STYLES__*/', () => styles)
  .replace('/*__SCRIPTS__*/', () => scripts);

if (process.argv.includes('--check')) {
  let current = '';
  try {
    current = readFileSync(output, 'utf8');
  } catch {}
  if (current !== html) {
    console.error('MarkdownEditor.html is out of date. Run `npm run build` in MarkdownEditor.');
    process.exit(1);
  }
} else {
  mkdirSync(dirname(output), { recursive: true });
  writeFileSync(output, html);
  console.log(`Wrote ${output} (${Buffer.byteLength(html)} bytes)`);
}
