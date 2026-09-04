import test from 'node:test';
import assert from 'node:assert/strict';

import {
  canManageProductionArchive,
  hasManagerOverrideAccess,
  hasManagerWorkflowAccess,
  isEmployeeOrderCreatorRole,
  isProductionWorkerRole,
} from '../lib/role-access.js';

const MANAGER = '\u041c\u0435\u043d\u0435\u0434\u0436\u0435\u0440';
const MANAGING = '\u0423\u043f\u0440\u0430\u0432\u043b\u044f\u044e\u0449\u0438\u0439';
const PRODUCTION = '\u041f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u043e';
const SCREEN_PRINTING = '\u0428\u0435\u043b\u043a\u043e\u0433\u0440\u0430\u0444\u0438\u044f';
const DESIGNER = '\u0414\u0438\u0437\u0430\u0439\u043d\u0435\u0440';

test('manager workflow access includes supervisors and managers only', () => {
  assert.equal(hasManagerWorkflowAccess('Administrator'), true);
  assert.equal(hasManagerWorkflowAccess(MANAGING), true);
  assert.equal(hasManagerWorkflowAccess(MANAGER), true);
  assert.equal(hasManagerWorkflowAccess(PRODUCTION), false);
});

test('manager override access is restricted to control roles', () => {
  assert.equal(hasManagerOverrideAccess('Administrator'), true);
  assert.equal(hasManagerOverrideAccess(MANAGING), true);
  assert.equal(hasManagerOverrideAccess(MANAGER), false);
});

test('employees who may create own orders keep the established role list', () => {
  for (const role of [MANAGER, PRODUCTION, SCREEN_PRINTING, DESIGNER]) {
    assert.equal(isEmployeeOrderCreatorRole(role), true);
  }
  assert.equal(isEmployeeOrderCreatorRole('\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442'), false);
});

test('production permissions distinguish workers and archive controllers', () => {
  assert.equal(isProductionWorkerRole(PRODUCTION), true);
  assert.equal(isProductionWorkerRole(SCREEN_PRINTING), true);
  assert.equal(isProductionWorkerRole(MANAGING), false);
  assert.equal(canManageProductionArchive('Administrator'), true);
  assert.equal(canManageProductionArchive(MANAGING), true);
  assert.equal(canManageProductionArchive(PRODUCTION), true);
  assert.equal(canManageProductionArchive(SCREEN_PRINTING), true);
  assert.equal(canManageProductionArchive(MANAGER), false);
});
