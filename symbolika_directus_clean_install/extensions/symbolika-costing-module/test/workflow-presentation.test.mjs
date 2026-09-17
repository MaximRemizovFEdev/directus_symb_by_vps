import test from 'node:test';
import assert from 'node:assert/strict';

import {
  eventActionText,
  eventFieldLabels,
  eventIcon,
  eventToneClass,
  notificationKindIcon,
  notificationKindLabel,
  taskPriorityClass,
  taskPriorityName,
  taskStatusClass,
  taskStatusName,
} from '../lib/workflow-presentation.js';

test('task labels keep Russian names and fallbacks', () => {
  assert.equal(taskStatusName('in_work'), 'В работе');
  assert.equal(taskStatusName('unknown'), 'Не выбрано');
  assert.equal(taskPriorityName('urgent'), 'Срочно');
  assert.equal(taskPriorityName('unknown'), 'Обычный');
});

test('task visual classes preserve status and priority tones', () => {
  assert.equal(taskStatusClass('done'), 'symbolika-costing-pill-success');
  assert.equal(taskStatusClass('unknown'), 'symbolika-costing-pill-muted');
  assert.equal(taskPriorityClass('urgent'), 'symbolika-costing-pill-danger');
  assert.equal(taskPriorityClass('unknown'), 'symbolika-costing-pill-muted');
});

test('notification kinds keep labels, icons and system fallbacks', () => {
  assert.equal(notificationKindLabel('procurement'), 'Закупка');
  assert.equal(notificationKindIcon('birthday'), 'cake');
  assert.equal(notificationKindLabel('unknown'), 'Система');
  assert.equal(notificationKindIcon('unknown'), 'notifications');
});

test('event presentation keeps actions, icons, tones and field labels', () => {
  assert.equal(eventActionText({ action: 'create', entity_type: 'order' }), 'создал заказ');
  assert.equal(eventActionText({ action: 'delete', entity_type: 'item' }), 'удалил позицию');
  assert.equal(eventActionText({ action: 'update', entity_type: 'task' }), 'изменил задачу');
  assert.equal(eventIcon({ action: 'update', entity_type: 'item' }), 'inventory_2');
  assert.equal(eventToneClass({ action: 'delete' }), 'is-delete');
  assert.equal(eventFieldLabels.production_comment, 'Комментарий производства');
});
