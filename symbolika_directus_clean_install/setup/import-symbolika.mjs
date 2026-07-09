// Symbolika Directus clean setup
// Run inside container:
// docker exec -it symbolika-directus node /directus/setup/import-symbolika.mjs

const DIRECTUS_URL = process.env.DIRECTUS_URL || 'http://127.0.0.1:8055';
const ADMIN_EMAIL = process.env.ADMIN_EMAIL || 'admin@symb.local';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'ChangeThisAdminPass2026';

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function request(path, options = {}) {
  const res = await fetch(`${DIRECTUS_URL}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(globalThis.TOKEN ? { Authorization: `Bearer ${globalThis.TOKEN}` } : {}),
      ...(options.headers || {}),
    },
  });
  const text = await res.text();
  let body = {};
  try { body = text ? JSON.parse(text) : {}; } catch { body = { raw: text }; }
  if (!res.ok) {
    const msg = body?.errors?.[0]?.message || body?.raw || res.statusText;
    throw new Error(`${options.method || 'GET'} ${path}: ${res.status} ${msg}`);
  }
  return body;
}

async function login() {
  for (let i = 0; i < 30; i++) {
    try {
      const body = await request('/auth/login', {
        method: 'POST',
        body: JSON.stringify({ email: ADMIN_EMAIL, password: ADMIN_PASSWORD }),
      });
      globalThis.TOKEN = body.data.access_token;
      return;
    } catch (e) {
      await sleep(3000);
    }
  }
  throw new Error('Directus не ответил или не удалось войти');
}

async function safe(label, fn) {
  try {
    await fn();
    console.log(`OK: ${label}`);
  } catch (e) {
    if (String(e.message).includes('already exists') || String(e.message).includes('already configured') || String(e.message).includes('Field') && String(e.message).includes('exists')) {
      console.log(`SKIP: ${label}`);
    } else {
      console.log(`WARN: ${label}: ${e.message}`);
    }
  }
}

function tr(text) {
  return [{ language: 'ru-RU', translation: text }];
}

async function collection(name, ru, icon='folder', sort=50, display='{{name}}') {
  await safe(`collection ${name}`, () => request('/collections', {
    method: 'POST',
    body: JSON.stringify({
      collection: name,
      meta: {
        collection: name,
        icon,
        hidden: false,
        singleton: false,
        translations: tr(ru),
        display_template: display,
        sort,
        accountability: 'all',
      },
      schema: { name },
    }),
  }));
}

async function field(collection, field, type, ru, schema={}, meta={}) {
  await safe(`field ${collection}.${field}`, () => request(`/fields/${collection}`, {
    method: 'POST',
    body: JSON.stringify({
      field,
      type,
      meta: {
        field,
        interface: meta.interface ?? 'input',
        readonly: meta.readonly ?? false,
        required: meta.required ?? false,
        hidden: meta.hidden ?? false,
        width: meta.width ?? 'full',
        translations: tr(ru),
        special: meta.special ?? null,
        options: meta.options ?? null,
        display: meta.display ?? null,
        display_options: meta.display_options ?? null,
        sort: meta.sort ?? null,
      },
      schema,
    }),
  }));
}

async function str(c,f,ru, opts={}) { return field(c,f,'string',ru,{ data_type:'character varying', max_length:255, is_nullable: !opts.required, default_value: opts.default ?? null }, opts); }
async function text(c,f,ru, opts={}) { return field(c,f,'text',ru,{ data_type:'text', is_nullable:true }, {interface:'input-multiline', ...opts}); }
async function dec(c,f,ru, opts={}) { return field(c,f,'decimal',ru,{ data_type:'numeric', numeric_precision:10, numeric_scale:2, is_nullable: !opts.required, default_value: opts.default ?? null }, opts); }
async function integer(c,f,ru, opts={}) { return field(c,f,'integer',ru,{ data_type:'integer', is_nullable:true }, opts); }
async function bool(c,f,ru, opts={}) { return field(c,f,'boolean',ru,{ data_type:'boolean', is_nullable:true, default_value: opts.default ?? false }, {interface:'boolean', special:['cast-boolean'], ...opts}); }
async function datetime(c,f,ru, opts={}) { return field(c,f,'dateTime',ru,{ data_type:'timestamp without time zone', is_nullable: !opts.required }, {interface:'datetime', ...opts}); }

async function m2o(c,f,ru,related, opts={}) {
  await field(c,f,'integer',ru,{ data_type:'integer', is_nullable: !opts.required, foreign_key_table: related, foreign_key_column:'id' }, {
    interface:'select-dropdown-m2o',
    special:['m2o'],
    display:'related-values',
    display_options:{ template: opts.template || '{{name}}' },
    options:{ template: opts.template || '{{name}}' },
    required: opts.required ?? false,
    sort: opts.sort ?? null,
  });
  await safe(`relation ${c}.${f}->${related}`, () => request('/relations', {
    method:'POST',
    body: JSON.stringify({
      collection:c,
      field:f,
      related_collection:related,
      meta:{
        many_collection:c,
        many_field:f,
        one_collection:related,
        one_field: opts.one_field || null,
        one_deselect_action: opts.on_delete === 'CASCADE' ? 'delete' : 'nullify',
      },
      schema:{
        table:c,
        column:f,
        foreign_key_table:related,
        foreign_key_column:'id',
        on_delete: opts.on_delete || 'SET NULL',
      }
    })
  }));
}

async function aliasO2M(c,f,ru) {
  await field(c,f,'alias',ru,{}, {interface:'list-o2m', special:['o2m'], readonly:false});
}

async function seed(collection, items, unique='name') {
  for (const item of items) {
    await safe(`seed ${collection}.${item[unique]}`, async () => {
      const filter = encodeURIComponent(JSON.stringify({ [unique]: { _eq: item[unique] } }));
      const exists = await request(`/items/${collection}?filter=${filter}&limit=1`);
      if (exists.data?.length) return;
      await request(`/items/${collection}`, { method:'POST', body: JSON.stringify(item) });
    });
  }
}

async function main() {
  await login();
  console.log('Logged in');

  // Collections
  await collection('employee_positions','Должности','badge',1);
  await collection('employees','Сотрудники','group',2,'{{full_name}}');
  await collection('customers','Клиенты','person',3);
  await collection('customer_companies','Компании','corporate_fare',4);
  await collection('contractors','Контрагенты','assignment_turned_in',5);
  await collection('order_statuses','Статусы заказов','flag',6);
  await collection('production_statuses','Статусы производства','engineering',7);
  await collection('payment_types','Типы оплат','payments',8);
  await collection('product_categories','Категории товаров','category',9);
  await collection('product_subcategories','Подкатегории товаров','category',10);
  await collection('production_places','Места производства','factory',11);
  await collection('tax_settings','Налоговые настройки','percent',12);
  await collection('orders','Заказы','assignment_ind',13,'{{order_number}}');
  await collection('orders_items','Позиции заказа','list_alt',14,'{{product_name}}');
  await collection('order_item_specs','Технические задания позиций','assignment',15);
  await collection('order_payments','Платежи','payments',16);
  await collection('payment_allocations','Распределение платежей','account_tree',17);
  await collection('contractor_payments','Оплаты контрагентам','paid',18);
  await collection('warehouse_categories','Категории склада','category',19);
  await collection('warehouse_items','Склад','inventory_2',20);

  // Simple dictionaries
  for (const c of ['employee_positions','order_statuses','production_statuses','payment_types','product_categories','production_places','warehouse_categories']) {
    await str(c,'name','Название',{required:true, sort:2});
    await integer(c,'sort','Сортировка',{sort:3});
    await bool(c,'is_active','Активно',{default:true, sort:4});
  }

  await m2o('product_subcategories','category','Категория','product_categories',{one_field:'subcategories', sort:3});
  await str('product_subcategories','name','Название',{required:true, sort:2});
  await integer('product_subcategories','sort','Сортировка',{sort:4});
  await bool('product_subcategories','is_active','Активно',{default:true, sort:5});

  // Employees
  await str('employees','full_name','ФИО',{required:true, sort:2});
  await m2o('employees','position','Должность','employee_positions',{sort:3});
  await dec('employees','salary_fixed','Оклад',{sort:4});
  await dec('employees','order_percent','% менеджера',{sort:5});
  await field('employees','directus_user','uuid','Пользователь Directus',{data_type:'uuid', foreign_key_table:'directus_users', foreign_key_column:'id', is_nullable:true},{interface:'select-dropdown-m2o', special:['m2o'], sort:6});
  await bool('employees','is_active','Активен',{default:true, sort:7});

  // Customers/companies
  for (const c of ['customers','customer_companies']) {
    await str(c,'name', c==='customers'?'Имя':'Название',{required:true, sort:2});
    await str(c,'phone','Телефон',{sort:3});
    await str(c,'email','Email',{sort:4});
    await m2o(c,'manager','Менеджер','employees',{template:'{{full_name}}', sort:5});
    await text(c,'comment','Комментарий',{sort:6});
    await dec(c,'orders_total_sum','Сумма заказов',{readonly:true, default:0, sort:20});
    await dec(c,'payments_total_in','Поступило оплат',{readonly:true, default:0, sort:21});
    await dec(c,'refunds_total_out','Возвращено клиенту',{readonly:true, default:0, sort:22});
    await dec(c,'balance','Баланс взаиморасчетов',{readonly:true, default:0, sort:23});
    await dec(c,'debt_to_us','Должен нам',{readonly:true, default:0, sort:24});
    await dec(c,'our_debt_to_customer','Мы должны клиенту',{readonly:true, default:0, sort:25});
  }
  await m2o('customers','company','Компания','customer_companies',{one_field:'customers', sort:5});

  // Contractors
  await str('contractors','name','Название',{required:true, sort:2});
  await str('contractors','contact_name','Контактное лицо',{sort:3});
  await str('contractors','phone','Телефон',{sort:4});
  await str('contractors','email','Email',{sort:5});
  await text('contractors','comment','Комментарий',{sort:6});
  await dec('contractors','items_total_cost','Себестоимость позиций',{readonly:true, default:0, sort:20});
  await dec('contractors','payments_total_out','Оплачено контрагенту',{readonly:true, default:0, sort:21});
  await dec('contractors','balance','Баланс взаиморасчетов',{readonly:true, default:0, sort:22});
  await dec('contractors','debt_to_contractor','Мы должны контрагенту',{readonly:true, default:0, sort:23});
  await dec('contractors','contractor_debt_to_us','Контрагент должен нам',{readonly:true, default:0, sort:24});

  // Orders
  await str('orders','order_number','Номер заказа',{required:true, sort:2});
  await datetime('orders','date','Дата создания',{required:true, sort:3});
  await datetime('orders','deadline','Общий срок',{sort:4});
  await m2o('orders','manager_employee','Менеджер','employees',{required:true, template:'{{full_name}}', sort:5});
  await m2o('orders','customer','Клиент','customers',{sort:6});
  await m2o('orders','customer_company','Компания','customer_companies',{sort:7});
  await m2o('orders','order_status','Статус заказа','order_statuses',{required:false, sort:8});
  await text('orders','comment','Комментарий',{sort:9});
  await bool('orders','issue_in_office','Выдача в офисе',{default:false, sort:10});
  await str('orders','shipping_method','Способ отгрузки',{sort:11, interface:'select-dropdown', options:{choices:[
    {text:'Выдача в офисе',value:'office_pickup'},
    {text:'Доставка клиенту',value:'client_delivery'},
    {text:'Транспортная компания',value:'transport_company'},
  ]}});
  await text('orders','shipping_comment','Комментарий по доставке',{sort:12});
  for (const [f,ru] of [
    ['order_sum','Сумма заказа'],['items_total_cost','Общая себестоимость'],['items_manager_commission_sum','Комиссия менеджера всего'],
    ['items_tax_sum','Налог всего'],['paid_amount','Оплачено'],['payment_due','Остаток к оплате'],
    ['profit_sum','Чистая прибыль'],['margin_percent','Маржинальность %'],['office_payment_due','К оплате при выдаче']
  ]) await dec('orders',f,ru,{readonly:true, default:0});

  // Order items
  await m2o('orders_items','order','Заказ','orders',{required:true, template:'{{order_number}}', one_field:'items', sort:2});
  await str('orders_items','product_name','Наименование',{required:true, sort:3});
  await dec('orders_items','quantity','Количество',{required:true, default:0, sort:4});
  await dec('orders_items','price_per_unit','Цена за единицу',{required:true, default:0, sort:5});
  await dec('orders_items','order_sum','Сумма позиции',{readonly:true, default:0, sort:6});
  await dec('orders_items','unit_cost','Себестоимость за единицу',{default:0, sort:7});
  await dec('orders_items','total_cost','Себестоимость всего',{readonly:true, default:0, sort:8});
  await dec('orders_items','manager_percent','% менеджера',{default:0, sort:9});
  await dec('orders_items','manager_commission_sum','Комиссия менеджера',{readonly:true, default:0, sort:10});
  await dec('orders_items','tax_percent','Налог %',{default:0, sort:11});
  await dec('orders_items','tax_sum','Сумма налога',{readonly:true, default:0, sort:12});
  await dec('orders_items','profit_sum','Прибыль',{readonly:true, default:0, sort:13});
  await dec('orders_items','margin_percent','Маржинальность %',{readonly:true, default:0, sort:14});
  await m2o('orders_items','product_category','Категория','product_categories',{sort:15});
  await m2o('orders_items','product_subcategory','Подкатегория','product_subcategories',{sort:16});
  await str('orders_items','item_status','Статус позиции',{sort:17, interface:'select-dropdown', options:{choices:[
    {text:'Ждем макет',value:'waiting_layout'}, {text:'Согласование',value:'approval'},
    {text:'Отправить в работу',value:'send_to_work'}, {text:'Отправлен в работу',value:'sent_to_work'},
    {text:'Готов',value:'ready'}, {text:'Отменен',value:'cancelled'}
  ]}});
  await m2o('orders_items','production_place','Место производства','production_places',{sort:18});
  await m2o('orders_items','production_status','Статус производства','production_statuses',{sort:19});
  await m2o('orders_items','contractor_1','Подрядчик 1','contractors',{sort:20});
  await m2o('orders_items','contractor_2','Подрядчик 2','contractors',{sort:21});
  await dec('orders_items','contractor_1_cost','Себестоимость подрядчика 1',{default:0, sort:22});
  await dec('orders_items','contractor_2_cost','Себестоимость подрядчика 2',{default:0, sort:23});
  await datetime('orders_items','deadline','Срок позиции',{sort:24});
  await text('orders_items','production_comment','Комментарий производства',{sort:25});
  await text('orders_items','technical_task_text','ТЗ (собранный текст)',{readonly:true, sort:26});

  // Specs
  await m2o('order_item_specs','order_item','Позиция заказа','orders_items',{required:true, template:'{{product_name}}', one_field:'spec', on_delete:'CASCADE', sort:2});
  await m2o('order_item_specs','category','Категория','product_categories',{sort:3});
  await m2o('order_item_specs','subcategory','Подкатегория','product_subcategories',{sort:4});
  await text('order_item_specs','technical_task_text','ТЗ (собранный текст)',{readonly:true, sort:5});
  await text('order_item_specs','comment','Комментарий к ТЗ',{sort:6});
  const specFields = [
    ['size_text','Размер / формат','string'],['color','Цвет','string'],['material','Материал','string'],['print_method','Способ печати / нанесения','string'],
    ['layout_status','Статус макета','string'],['packaging','Упаковка','string'],['notes','Примечания','text'],
    ['paper','Бумага','string'],['density','Плотность','string'],['print_sides','Печать сторон','string'],['lamination','Ламинация','string'],['postpress','Постпечатная обработка','text'],
    ['product_color','Цвет изделия','string'],['sizes_grid','Размерный ряд','text'],['brand_model','Модель / бренд','string'],['application_place','Место нанесения','string'],['application_size','Размер нанесения','string'],
    ['blank_type','Тип заготовки','string'],['print_area','Зона печати','string'],['individual_data','Персонализация','text'],
    ['banner_size','Размер изделия','string'],['grommets','Люверсы','string'],['pockets','Карманы','string'],['mounting','Крепление / монтаж','text'],
  ];
  let sort = 10;
  for (const [f,ru,t] of specFields) { t==='text' ? await text('order_item_specs',f,ru,{sort:sort++}) : await str('order_item_specs',f,ru,{sort:sort++}); }

  // Payments
  await m2o('order_payments','order','Заказ','orders',{template:'{{order_number}}', one_field:'order_payments', sort:2});
  await m2o('order_payments','customer','Клиент','customers',{sort:3});
  await m2o('order_payments','customer_company','Компания','customer_companies',{sort:4});
  await dec('order_payments','amount','Сумма платежа',{required:true, default:0, sort:5});
  await datetime('order_payments','payment_date','Дата платежа',{required:true, sort:6});
  await m2o('order_payments','payment_type','Тип оплаты','payment_types',{sort:7});
  await str('order_payments','payment_direction','Направление платежа',{required:true, default:'incoming', sort:8, interface:'select-dropdown', options:{choices:[
    {text:'Поступление от клиента',value:'incoming'}, {text:'Возврат клиенту',value:'outgoing_refund'}
  ]}});
  await str('order_payments','allocation_mode','Режим распределения',{required:true, default:'to_order', sort:9, interface:'select-dropdown', options:{choices:[
    {text:'В оплату заказа',value:'to_order'}, {text:'Аванс',value:'advance'}, {text:'Возврат',value:'refund'}
  ]}});
  await dec('order_payments','allocated_amount','Распределено',{readonly:true, default:0, sort:10});
  await dec('order_payments','unallocated_amount','Нераспределенный остаток',{readonly:true, default:0, sort:11});
  await text('order_payments','comment','Комментарий',{sort:12});

  await m2o('payment_allocations','payment','Платеж','order_payments',{required:true, one_field:'allocations', on_delete:'CASCADE', sort:2});
  await m2o('payment_allocations','order','Заказ','orders',{required:true, template:'{{order_number}}', one_field:'payment_allocations', sort:3});
  await dec('payment_allocations','amount','Сумма распределения',{required:true, default:0, sort:4});
  await text('payment_allocations','comment','Комментарий',{sort:5});

  // Contractor payments
  await m2o('contractor_payments','contractor','Контрагент','contractors',{required:true, one_field:'payments', on_delete:'CASCADE', sort:2});
  await dec('contractor_payments','amount','Сумма',{required:true, default:0, sort:3});
  await datetime('contractor_payments','payment_date','Дата оплаты',{required:true, sort:4});
  await m2o('contractor_payments','payment_type','Тип оплаты','payment_types',{sort:5});
  await m2o('contractor_payments','related_order','Связанный заказ','orders',{template:'{{order_number}}', sort:6});
  await m2o('contractor_payments','related_order_item','Связанная позиция','orders_items',{template:'{{product_name}}', sort:7});
  await text('contractor_payments','comment','Комментарий',{sort:8});

  // Warehouse
  await m2o('warehouse_items','category','Категория','warehouse_categories',{one_field:'items', sort:3});
  await str('warehouse_items','name','Наименование',{required:true, sort:2});
  await str('warehouse_items','unit','Единица измерения',{required:true, default:'pcs', sort:4, interface:'select-dropdown', options:{choices:[
    {text:'шт',value:'pcs'}, {text:'м',value:'m'}, {text:'м²',value:'m2'}, {text:'кг',value:'kg'},
    {text:'лист',value:'sheet'}, {text:'комплект',value:'set'}, {text:'рулон',value:'roll'}, {text:'упаковка',value:'pack'}
  ]}});
  await dec('warehouse_items','quantity_in_stock','Остаток',{required:true, default:0, sort:5});
  await dec('warehouse_items','min_quantity','Минимальный остаток',{sort:6});
  await str('warehouse_items','location','Место хранения',{sort:7});
  await text('warehouse_items','comment','Комментарий',{sort:8});
  await bool('warehouse_items','is_active','Активно',{default:true, sort:9});

  // Seed
  await seed('order_statuses', [
    {name:'Новый'}, {name:'Частично в работе'}, {name:'В работе'}, {name:'Получен'}, {name:'Доставлен'}, {name:'Отменен'}
  ]);
  await seed('production_statuses', [
    {name:'Ждем макет'}, {name:'Согласование'}, {name:'Отправить в работу'}, {name:'Отправлен в работу'}, {name:'Готов'}, {name:'Отменен'}
  ]);
  await seed('payment_types', [
    {name:'Наличные'}, {name:'Безналичный расчет'}, {name:'Карта'}, {name:'СБП'}, {name:'Другое'}
  ]);
  await seed('warehouse_categories', [
    {name:'Заготовки', sort:10, is_active:true}, {name:'Текстиль', sort:20, is_active:true},
    {name:'Сувенирные заготовки', sort:30, is_active:true}, {name:'Полиграфические материалы', sort:40, is_active:true},
    {name:'Бумага', sort:50, is_active:true}, {name:'Упаковка', sort:60, is_active:true},
    {name:'Расходные материалы', sort:70, is_active:true}, {name:'Прочее', sort:100, is_active:true}
  ]);
  await seed('contractors', [{name:'Собственное производство', comment:'Внутреннее производство компании'}]);

  console.log('\nГотово. Структура Символики создана.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
