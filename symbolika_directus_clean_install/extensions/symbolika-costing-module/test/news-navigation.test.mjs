import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const costingUrl = new URL('../index.js', import.meta.url);
const newsApiUrl = new URL('../../symbolika-news/index.js', import.meta.url);
const newsModuleUrl = new URL('../../symbolika-news-module/index.js', import.meta.url);
const adminUiUrl = new URL('../../../setup/symbolika-admin-ui.js', import.meta.url);

test('news is exposed as a standalone employee module and not repeated in section menus', async () => {
  const [costing, newsModule, adminUi] = await Promise.all([
    readFile(costingUrl, 'utf8'),
    readFile(newsModuleUrl, 'utf8'),
    readFile(adminUiUrl, 'utf8'),
  ]);

  assert.match(newsModule, /id:\s*'symbolika-news-module'/);
  assert.match(newsModule, /name:\s*'Новости'/);
  assert.match(adminUi, /'\/admin\/symbolika-news-module'/);

  const moduleSections = costing.slice(
    costing.indexOf('const moduleSections ='),
    costing.indexOf('const statusNames ='),
  );
  assert.doesNotMatch(moduleSections, /tabs:\s*\[[^\]]*'news'/s);

  const navigationGroups = costing.slice(
    costing.indexOf('navigationGroups()'),
    costing.indexOf('navigationSections()'),
  );
  assert.doesNotMatch(navigationGroups, /tabs:\s*\[[^\]]*'news'/s);
});

test('only an administrator can create and edit company news', async () => {
  const [newsApi, newsModule] = await Promise.all([
    readFile(newsApiUrl, 'utf8'),
    readFile(newsModuleUrl, 'utf8'),
  ]);

  assert.match(newsApi, /const CONTROL_ROLES = new Set\(\['Administrator'\]\)/);
  assert.match(newsModule, /v-if="canManage"[^>]*>\+ Добавить новость<\/button>/);
});
