import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const extensionsDirectory = fileURLToPath(new URL('../../', import.meta.url));

function javascriptFiles(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    if (entry.name === 'node_modules') return [];

    const path = `${directory}/${entry.name}`;
    if (entry.isDirectory()) return javascriptFiles(path);
    return /\.(?:mjs|js)$/.test(entry.name) ? [path] : [];
  });
}

test('все JavaScript-файлы расширений проходят синтаксическую проверку', () => {
  const files = javascriptFiles(extensionsDirectory).sort();
  const failures = files.flatMap((file) => {
    const result = spawnSync(process.execPath, ['--check', file], {
      encoding: 'utf8',
      windowsHide: true,
    });

    return result.status === 0
      ? []
      : [{ file, error: (result.stderr || result.stdout || '').trim() }];
  });

  assert.ok(files.length >= 40, 'ожидался полный набор собственных расширений');
  assert.deepEqual(failures, [], 'обнаружены синтаксически некорректные расширения');
});
