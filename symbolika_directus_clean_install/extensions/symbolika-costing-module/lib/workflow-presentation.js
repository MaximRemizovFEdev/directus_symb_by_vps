export const taskStatusChoices = [
  { text: 'Новая', value: 'new' },
  { text: 'В работе', value: 'in_work' },
  { text: 'Нужны правки', value: 'needs_revision' },
  { text: 'Ожидает', value: 'waiting' },
  { text: 'Готово', value: 'done' },
  { text: 'Отменена', value: 'cancelled' },
];

export const taskPriorityChoices = [
  { text: 'Низкий', value: 'low' },
  { text: 'Обычный', value: 'normal' },
  { text: 'Важный', value: 'high' },
  { text: 'Срочно', value: 'urgent' },
];

export const eventFieldLabels = {
  title: 'Название',
  description: 'Описание',
  status: 'Статус задачи',
  priority: 'Приоритет',
  due_date: 'Срок задачи',
  completed_at: 'Завершена',
  assigned_to: 'Исполнитель',
  related_order: 'Заказ',
  related_order_item: 'Позиция',
  result_url: 'Результат',
  source_url: 'Исходный файл',
  order_number: 'Номер заказа',
  date: 'Дата заказа',
  deadline: 'Срок',
  manager_employee: 'Менеджер',
  order_status: 'Статус заказа',
  office_status: 'Статус офиса',
  shipping_method: 'Получение',
  payment_on_receipt: 'Оплата при получении',
  product_name: 'Позиция',
  quantity: 'Количество',
  price_per_unit: 'Цена',
  item_status: 'Статус позиции',
  production_status: 'Статус производства',
  production_comment: 'Комментарий производства',
  technical_task_text: 'ТЗ',
  url: 'Макет',
  needs_designer_help: 'Помощь дизайнера',
  blank_source: 'Источник заготовки',
  blank_ordered: 'Заготовка заказана',
  internal_route_production: 'Передача в производство',
  internal_route_screen: 'Передача в шелкографию',
  contractor_1: 'Поставщик / подрядчик',
  contractor_1_cost: 'Стоимость заготовки',
  contractor_2: 'Исполнитель работ',
};

export const eventEntityChoices = [
  { value: 'all', text: 'Все объекты' },
  { value: 'order', text: 'Заказы' },
  { value: 'item', text: 'Позиции' },
  { value: 'task', text: 'Задачи' },
];

export const eventActionChoices = [
  { value: 'all', text: 'Все действия' },
  { value: 'create', text: 'Создание' },
  { value: 'update', text: 'Изменения' },
  { value: 'delete', text: 'Удаление' },
];

const notificationKinds = {
  order: { label: 'Заказ', icon: 'assignment' },
  item: { label: 'Позиция', icon: 'inventory_2' },
  task: { label: 'Задача', icon: 'task_alt' },
  procurement: { label: 'Закупка', icon: 'local_shipping' },
  mail: { label: 'Почта', icon: 'mail' },
  birthday: { label: 'День рождения', icon: 'cake' },
  news: { label: 'Новости', icon: 'newspaper' },
  system: { label: 'Система', icon: 'notifications' },
};

export function notificationKindLabel(kind) {
  return notificationKinds[kind]?.label || notificationKinds.system.label;
}

export function notificationKindIcon(kind) {
  return notificationKinds[kind]?.icon || notificationKinds.system.icon;
}

export function eventEntityName(type) {
  return { order: 'заказ', item: 'позицию', task: 'задачу' }[type] || 'объект';
}

export function eventActionText(event) {
  const entity = eventEntityName(event?.entity_type);
  if (event?.action === 'create') return `создал ${entity}`;
  if (event?.action === 'delete') return `удалил ${entity}`;
  return `изменил ${entity}`;
}

export function eventIcon(event) {
  if (event?.action === 'create') return 'add_circle';
  if (event?.action === 'delete') return 'delete';
  if (event?.entity_type === 'task') return 'task_alt';
  if (event?.entity_type === 'item') return 'inventory_2';
  return 'edit';
}

export function eventToneClass(event) {
  return `is-${event?.action || 'update'}`;
}

export function taskStatusName(value) {
  return taskStatusChoices.find((choice) => choice.value === value)?.text || 'Не выбрано';
}

export function taskPriorityName(value) {
  return taskPriorityChoices.find((choice) => choice.value === value)?.text || 'Обычный';
}

export function taskStatusClass(value) {
  return {
    new: 'symbolika-costing-pill-blue',
    in_work: 'symbolika-costing-pill-orange',
    waiting: 'symbolika-costing-pill-warning',
    needs_revision: 'symbolika-costing-pill-warning',
    done: 'symbolika-costing-pill-success',
    cancelled: 'symbolika-costing-pill-muted',
  }[value] || 'symbolika-costing-pill-muted';
}

export function taskPriorityClass(value) {
  return {
    urgent: 'symbolika-costing-pill-danger',
    high: 'symbolika-costing-pill-orange',
    normal: 'symbolika-costing-pill-blue',
    low: 'symbolika-costing-pill-muted',
  }[value] || 'symbolika-costing-pill-muted';
}
