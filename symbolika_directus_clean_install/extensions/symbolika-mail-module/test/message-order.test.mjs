import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('mail reader displays the newest message first without changing storage order', () => {
  const computed = source.match(/displayMessages\(\) \{(?<body>[\s\S]*?)\n    \},/)?.groups?.body || '';

  assert.match(computed, /\[\.\.\.this\.messages\]\.sort/);
  assert.match(computed, /return rightTime - leftTime/);
  assert.match(computed, /Number\(right\?\.id \|\| 0\) - Number\(left\?\.id \|\| 0\)/);
  assert.match(source, /v-for="message in displayMessages"/);
});

test('forwarding still selects the chronologically last stored message', () => {
  assert.match(source, /const lastMessage = this\.messages\[this\.messages\.length - 1\] \|\| \{\}/);
});
