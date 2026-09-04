const MANAGER_OVERRIDE_ROLES = new Set([
  'Administrator',
  '\u0423\u043f\u0440\u0430\u0432\u043b\u044f\u044e\u0449\u0438\u0439',
]);
const MANAGER_WORKFLOW_ROLES = new Set([
  ...MANAGER_OVERRIDE_ROLES,
  '\u041c\u0435\u043d\u0435\u0434\u0436\u0435\u0440',
]);
const EMPLOYEE_ORDER_CREATOR_ROLES = new Set([
  '\u041c\u0435\u043d\u0435\u0434\u0436\u0435\u0440',
  '\u041f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u043e',
  '\u0428\u0435\u043b\u043a\u043e\u0433\u0440\u0430\u0444\u0438\u044f',
  '\u0414\u0438\u0437\u0430\u0439\u043d\u0435\u0440',
]);
const PRODUCTION_WORKER_ROLES = new Set([
  '\u041f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u043e',
  '\u0428\u0435\u043b\u043a\u043e\u0433\u0440\u0430\u0444\u0438\u044f',
]);
const PRODUCTION_ARCHIVE_ROLES = new Set([
  ...MANAGER_OVERRIDE_ROLES,
  ...PRODUCTION_WORKER_ROLES,
]);

export function hasManagerOverrideAccess(roleName) {
  return MANAGER_OVERRIDE_ROLES.has(roleName);
}

export function hasManagerWorkflowAccess(roleName) {
  return MANAGER_WORKFLOW_ROLES.has(roleName);
}

export function isEmployeeOrderCreatorRole(roleName) {
  return EMPLOYEE_ORDER_CREATOR_ROLES.has(roleName);
}

export function isProductionWorkerRole(roleName) {
  return PRODUCTION_WORKER_ROLES.has(roleName);
}

export function canManageProductionArchive(roleName) {
  return PRODUCTION_ARCHIVE_ROLES.has(roleName);
}
