import assert from 'node:assert/strict';
import { buildLayoutFileName, isManagedOldPath } from '../extensions/symbolika-yandex-disk/index.js';

assert.equal(
  buildLayoutFileName({
    orderDate: '2026-08-10',
    customerName: 'Анатолий',
    productName: 'Блокноты',
    quantity: '50.000',
    originalName: 'макет.PDF',
  }),
  '100826, Анатолий, Блокноты - 50шт.pdf',
);

assert.equal(
  buildLayoutFileName({
    orderDate: '2026-08-10',
    customerName: 'ООО «Тест/Печать»',
    productName: 'Футболки: красные',
    quantity: '1.5',
    originalName: 'print.cdr',
  }),
  '100826, ООО «Тест-Печать», Футболки- красные - 1,5шт.cdr',
);

const managed = { root: 'app:/Заказы', orderFolder: 'SO-00001', itemFolder: 'Позиция-42' };
assert.equal(isManagedOldPath('app:/Заказы/SO-00001/Позиция-42/old.pdf', managed), true);
assert.equal(isManagedOldPath('disk:/Приложения/Символика/Заказы/SO-00001/Позиция-42/old.pdf', managed), true);
assert.equal(isManagedOldPath('disk:/Личные файлы/old.pdf', managed), false);

console.log(JSON.stringify({ filenameFormat: true, managedReplacementCleanup: true }));
