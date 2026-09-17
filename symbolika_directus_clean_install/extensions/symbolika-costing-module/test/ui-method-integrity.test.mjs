import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const components = [
  ['основной рабочий модуль', new URL('../index.js', import.meta.url)],
  ['почта', new URL('../../symbolika-mail-module/index.js', import.meta.url)],
  ['новости', new URL('../../symbolika-news-module/index.js', import.meta.url)],
];

const vueRuntimeMethods = new Set(['$emit', '$forceUpdate', '$nextTick']);

function componentMethods(source, label) {
  const start = source.indexOf('  methods: {');
  const end = source.indexOf('  template: `', start);

  assert.notEqual(start, -1, `${label}: блок methods не найден`);
  assert.notEqual(end, -1, `${label}: граница template не найдена`);
  assert.ok(end > start, `${label}: некорректные границы Vue-компонента`);

  return source.slice(start, end);
}

test('вызовы this.method() ссылаются на существующие методы Vue-компонентов', () => {
  for (const [label, url] of components) {
    const methods = componentMethods(readFileSync(url, 'utf8'), label);
    const definitionList = [
      ...methods.matchAll(/^    (?:async\s+)?([A-Za-z_$][A-Za-z0-9_$]*)\s*\(/gm),
    ].map((match) => match[1]);
    const definitions = new Set(definitionList);
    const duplicates = [...definitions]
      .filter((method) => definitionList.indexOf(method) !== definitionList.lastIndexOf(method))
      .sort();
    const calls = new Set(
      [...methods.matchAll(/\bthis\.([A-Za-z_$][A-Za-z0-9_$]*)\s*\(/g)]
        .map((match) => match[1]),
    );
    const missing = [...calls]
      .filter((method) => !definitions.has(method) && !vueRuntimeMethods.has(method))
      .sort();

    assert.ok(definitions.size > 0, `${label}: не найдено ни одного метода`);
    assert.deepEqual(duplicates, [], `${label}: методы объявлены повторно`);
    assert.deepEqual(missing, [], `${label}: вызваны необъявленные методы`);
  }
});
