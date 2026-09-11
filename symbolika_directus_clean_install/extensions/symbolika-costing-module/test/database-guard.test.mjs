import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const projectRoot = new URL('../../../', import.meta.url);

async function source(path) {
  return readFile(new URL(path, projectRoot), 'utf8');
}

test('limits only Directus database sessions and labels them for recovery', async () => {
  const compose = await source('docker-compose.yml');
  assert.match(compose, /application_name=symbolika-directus/);
  assert.match(compose, /statement_timeout=60000/);
  assert.match(compose, /lock_timeout=10000/);
  assert.match(compose, /idle_in_transaction_session_timeout=60000/);
});

test('emergency recovery targets labelled Directus sessions only', async () => {
  const endpoint = await source('extensions/symbolika-support/index.js');
  assert.match(endpoint, /application_name: 'symbolika-emergency-control'/);
  assert.match(endpoint, /application_name = \$1/);
  assert.match(endpoint, /pg_cancel_backend\(pid\)/);
  assert.match(endpoint, /req\.accountability\.admin !== true/);
});

test('deploy installs recovery dependency and admin UI exposes the guard', async () => {
  const [deploy, ui] = await Promise.all([
    source('setup/update-server.sh'),
    source('extensions/symbolika-costing-module/index.js'),
  ]);
  assert.match(deploy, /extensions\/symbolika-support:\/app/);
  assert.match(ui, /Аварийно остановить вычисления/);
  assert.match(ui, /STOP_DIRECTUS_CALCULATIONS/);
  assert.match(ui, /currentRoleName === 'Administrator'/);
});
