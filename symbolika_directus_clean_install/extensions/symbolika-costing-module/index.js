const fields = [
  'id',
  'order',
  'order_link',
  'order_number',
  'date',
  'customer.name',
  'customer_company.name',
  'manager_employee.full_name',
  'product_name',
  'quantity',
  'deadline',
  'item_status',
  'production_status.id',
  'production_status.name',
  'price_per_unit',
  'order_sum',
  'contractor_1.id',
  'contractor_1.name',
  'contractor_2.id',
  'contractor_2.name',
  'contractor_1_cost',
  'contractor_2_cost',
  'unit_cost',
  'total_cost',
  'profit_sum',
  'margin_percent',
];

const workFields = [
  'id',
  'order',
  'order.order_number',
  'order_link',
  'date',
  'deadline',
  'customer.name',
  'customer_company.name',
  'manager_employee.full_name',
  'product_name',
  'quantity',
  'item_status',
  'office_status',
  'technical_task_text',
  'url',
  'production_status.id',
  'production_status.name',
  'production_comment',
];

const officeFields = [
  'id',
  'office_issue',
  'order_number',
  'customer_name',
  'customer_company_name',
  'manager_employee.full_name',
  'product_name',
  'quantity',
  'office_status',
];

const officeArchiveItemFields = [
  'id',
  'office_issue',
  'product_name',
  'quantity',
  'office_status',
];

const officeIssueFields = [
  'id',
  'order_link',
  'order_number',
  'date',
  'deadline',
  'customer_name',
  'customer_phone',
  'customer_company_name',
  'manager_name',
  'order_status_name',
  'office_status',
  'order_sum',
  'paid_amount',
  'payment_due',
  'office_payment_due',
  'add_payment',
  'overpayment',
  'payment_type',
  'payment_comment',
];

const officeArchiveFields = [
  'id',
  'order_link',
  'order_number',
  'date',
  'deadline',
  'customer_name',
  'customer_phone',
  'customer_company_name',
  'manager_name',
  'order_status_name',
  'office_status',
  'order_sum',
  'paid_amount',
  'payment_due',
  'office_payment_due',
  'overpayment',
];

const financeFields = [
  'id',
  'order_link',
  'order_number',
  'date',
  'deadline',
  'customer',
  'customer_name',
  'customer_company',
  'customer_company_name',
  'counterparty_name',
  'manager_name',
  'order_status_name',
  'order_sum',
  'paid_amount',
  'payment_due',
  'overpayment',
  'reconciliation_result',
];

const financeItemFields = [
  'id',
  'order_item',
  'order_link',
  'order_number',
  'date',
  'deadline',
  'customer',
  'customer_name',
  'customer_company',
  'customer_company_name',
  'counterparty_name',
  'manager_name',
  'order_status_name',
  'production_status_name',
  'product_name',
  'quantity',
  'price_per_unit',
  'item_sum',
  'order_sum',
  'paid_amount',
  'payment_due',
  'overpayment',
  'reconciliation_result',
];

const contractorFields = [
  'id',
  'name',
  'contact_name',
  'phone',
  'email',
  'items_total_cost',
  'payments_total_out',
  'balance',
  'debt_to_contractor',
  'contractor_debt_to_us',
  'has_own_view',
];

const expenseFields = [
  'id',
  'expense_date',
  'expense_type',
  'amount',
  'employee.id',
  'employee.full_name',
  'payment_type.id',
  'payment_type.name',
  'comment',
];

const salaryFields = [
  'id',
  'employee',
  'employee_name',
  'position_name',
  'salary_fixed',
  'order_percent',
  'orders_sum',
  'paid_orders_sum',
  'unpaid_orders_sum',
  'commission_accrued',
  'salary_accrued',
  'salary_paid',
  'advances_paid',
  'salary_debt',
];

const managerFinanceFields = [
  'id',
  'employee',
  'employee_name',
  'order_percent',
  'orders_count',
  'orders_sum',
  'paid_orders_sum',
  'unpaid_orders_sum',
  'commission_total',
  'commission_accrued',
  'commission_expected',
  'commission_paid',
  'commission_to_pay',
];

const expenseTypes = [
  { text: 'Аренда', value: 'rent' },
  { text: 'Выплата зарплаты', value: 'salary_payment' },
  { text: 'Оплата за доставку', value: 'delivery' },
  { text: 'Прочие расходы', value: 'other' },
  { text: 'Аванс сотруднику', value: 'employee_advance' },
];

const orderSummaryFields = [
  'id',
  'order_number',
  'date',
  'deadline',
  'customer',
  'customer_company',
  'customer_display',
  'manager_name',
  'order_status_name',
  'office_status',
  'shipping_method_name',
  'order_sum',
  'paid_amount',
  'payment_due',
  'order_link',
];

const overviewFields = [
  'id',
  'order_number',
  'date',
  'deadline',
  'customer',
  'customer_company',
  'customer_display',
  'manager_name',
  'order_status',
  'order_status_name',
  'office_status',
  'shipping_method_name',
  'order_sum',
  'paid_amount',
  'payment_due',
  'order_link',
];

const tabs = [
  { id: 'dashboard', title: 'Сводка', collection: '' },
  { id: 'queue', title: 'Очередь задач', collection: '' },
  { id: 'problems', title: 'Требует внимания', collection: '' },
  { id: 'search', title: 'Поиск', collection: '' },
  { id: 'all_orders', title: 'Все заказы', collection: 'orders_overview' },
  { id: 'deadlines', title: 'Сроки', collection: '' },
  { id: 'my_orders', title: 'Мои заказы', collection: 'my_orders_in_work' },
  { id: 'costing', title: 'Себестоимость', collection: 'contractor_costing' },
  { id: 'payroll', title: 'Зарплаты', collection: 'employee_salary_summary' },
  { id: 'expenses', title: 'Расходы', collection: 'business_expenses' },
  { id: 'finance', title: 'Сверки', collection: 'customer_reconciliation' },
  { id: 'clients', title: 'Клиенты', collection: 'customers' },
  { id: 'companies', title: 'Компании', collection: 'customer_companies' },
  { id: 'contractors', title: 'Контрагенты', collection: 'contractors' },
  { id: 'admin_employees', title: 'Сотрудники', collection: 'employees' },
  { id: 'admin_users', title: 'Пользователи и роли', collection: 'directus_users' },
  { id: 'admin_positions', title: 'Должности', collection: 'employee_positions' },
  { id: 'admin_categories', title: 'Категории', collection: 'product_categories' },
  { id: 'admin_subcategories', title: 'Подкатегории', collection: 'product_subcategories' },
  { id: 'admin_methods', title: 'Виды нанесения', collection: 'product_application_methods' },
  { id: 'admin_routing', title: 'Маршрутизация', collection: 'product_routing_rules' },
  { id: 'admin_order_statuses', title: 'Статусы заказов', collection: 'order_statuses' },
  { id: 'admin_production_statuses', title: 'Статусы производства', collection: 'production_statuses' },
  { id: 'production', title: 'Производство', collection: 'production_work' },
  { id: 'screen', title: 'Шелкография', collection: 'screen_printing_work' },
  { id: 'office', title: 'Офис', collection: 'office_items_in_office' },
];

const deadlineBuckets = [
  { id: 'urgent', title: 'Горящие', collection: 'orders_due_urgent' },
  { id: 'today', title: 'Сегодня', collection: 'orders_due_today' },
  { id: 'this_week', title: 'На этой неделе', collection: 'orders_due_this_week' },
  { id: 'next_week', title: 'На следующей неделе', collection: 'orders_due_next_week' },
  { id: 'this_month', title: 'В этом месяце', collection: 'orders_due_this_month' },
  { id: 'next_month', title: 'В следующем месяце', collection: 'orders_due_next_month' },
];

const officeBuckets = [
  { id: 'planned', title: 'К выдаче' },
  { id: 'in_office', title: 'Заказы в офисе' },
  { id: 'issued', title: 'Выданные' },
];

const officeSortOptions = [
  { id: 'deadline', title: 'По сроку' },
  { id: 'order_number', title: 'По номеру' },
  { id: 'customer', title: 'По клиенту' },
  { id: 'payment_due', title: 'По остатку' },
  { id: 'date', title: 'По дате' },
];

const moduleSections = {
  orders: {
    title: 'Заказы',
    tabs: ['dashboard', 'queue', 'problems', 'search', 'all_orders', 'deadlines', 'my_orders', 'office'],
    roles: ['Administrator', 'Управляющий', 'Менеджер', 'Офис-менеджер'],
  },
  production: {
    title: 'Производство',
    tabs: ['production', 'screen'],
    roles: ['Administrator', 'Управляющий', 'Производство', 'Шелкография'],
  },
  management: {
    title: 'Управление',
    tabs: ['costing'],
    roles: ['Administrator', 'Управляющий'],
  },
  finance: {
    title: 'Финансы',
    tabs: ['finance'],
    roles: ['Administrator', 'Управляющий', 'Менеджер'],
  },
  clients: {
    title: 'Клиенты',
    tabs: ['clients', 'companies'],
    roles: ['Administrator', 'Управляющий', 'Менеджер'],
  },
  admin: {
    title: 'Админка',
    tabs: [
      'admin_employees',
      'admin_users',
      'admin_positions',
      'contractors',
      'admin_categories',
      'admin_subcategories',
      'admin_methods',
      'admin_routing',
      'admin_order_statuses',
      'admin_production_statuses',
      'payroll',
      'expenses',
    ],
    roles: ['Administrator'],
  },
};

const adminDictionaryTabs = [
  'admin_employees',
  'admin_users',
  'admin_positions',
  'contractors',
  'admin_categories',
  'admin_subcategories',
  'admin_methods',
  'admin_routing',
  'admin_order_statuses',
  'admin_production_statuses',
];

const adminConfigs = {
  contractors: {
    collection: 'contractors',
    endpoint: '/items/contractors',
    title: 'Контрагенты',
    sort: 'name',
    fields: 'id,name,contact_name,phone,email,default_product_category,default_product_subcategory,has_own_view,directus_user,comment',
    columns: [
      { key: 'name', label: 'Название', type: 'text', required: true, wide: true },
      { key: 'contact_name', label: 'Контактное лицо', type: 'text' },
      { key: 'phone', label: 'Телефон', type: 'text' },
      { key: 'email', label: 'Email', type: 'text' },
      { key: 'default_product_category', label: 'Категория по умолчанию', type: 'relation', options: 'productCategories' },
      { key: 'default_product_subcategory', label: 'Подкатегория по умолчанию', type: 'relation', options: 'productSubcategories' },
      { key: 'has_own_view', label: 'Свое представление', type: 'boolean' },
      { key: 'directus_user', label: 'Пользователь', type: 'relation', options: 'directusUsers' },
    ],
  },
  admin_employees: {
    collection: 'employees',
    endpoint: '/items/employees',
    title: 'Сотрудники',
    sort: 'full_name',
    fields: 'id,full_name,phone,position,salary_fixed,order_percent,is_active,directus_user',
    columns: [
      { key: 'full_name', label: 'ФИО', type: 'text', required: true, wide: true },
      { key: 'phone', label: 'Телефон', type: 'text' },
      { key: 'position', label: 'Должность', type: 'relation', options: 'employeePositions' },
      { key: 'salary_fixed', label: 'Оклад', type: 'money' },
      { key: 'order_percent', label: '% с заказов', type: 'number' },
      { key: 'directus_user', label: 'Пользователь', type: 'relation', options: 'directusUsers' },
      { key: 'is_active', label: 'Активен', type: 'boolean' },
    ],
  },
  admin_users: {
    collection: 'directus_users',
    endpoint: '/users',
    title: 'Пользователи и роли',
    sort: 'email',
    fields: 'id,email,first_name,last_name,status,role',
    createDisabled: true,
    columns: [
      { key: 'email', label: 'Email', type: 'text', readonly: true, wide: true },
      { key: 'first_name', label: 'Имя', type: 'text' },
      { key: 'last_name', label: 'Фамилия', type: 'text' },
      { key: 'role', label: 'Роль', type: 'relation', options: 'directusRoles', required: true },
      { key: 'status', label: 'Статус', type: 'select', choices: [
        { value: 'active', text: 'Активен' },
        { value: 'invited', text: 'Приглашен' },
        { value: 'suspended', text: 'Заблокирован' },
        { value: 'archived', text: 'Архив' },
      ] },
    ],
  },
  admin_positions: {
    collection: 'employee_positions',
    endpoint: '/items/employee_positions',
    title: 'Должности',
    sort: 'sort,name',
    fields: 'id,name,sort,is_active',
    columns: [
      { key: 'name', label: 'Название', type: 'text', required: true, wide: true },
      { key: 'sort', label: 'Сортировка', type: 'number' },
      { key: 'is_active', label: 'Активно', type: 'boolean' },
    ],
  },
  admin_categories: {
    collection: 'product_categories',
    endpoint: '/items/product_categories',
    title: 'Категории',
    sort: 'sort,name',
    fields: 'id,name,detail_mode,sort,is_active',
    columns: [
      { key: 'name', label: 'Название', type: 'text', required: true, wide: true },
      { key: 'detail_mode', label: 'Тип детализации', type: 'select', choices: [
        { value: 'subcategory', text: 'Подкатегории' },
        { value: 'application_method', text: 'Виды нанесения' },
        { value: 'none', text: 'Без детализации' },
      ] },
      { key: 'sort', label: 'Сортировка', type: 'number' },
      { key: 'is_active', label: 'Активно', type: 'boolean' },
    ],
  },
  admin_subcategories: {
    collection: 'product_subcategories',
    endpoint: '/items/product_subcategories',
    title: 'Подкатегории',
    sort: 'category,sort,name',
    fields: 'id,category,name,sort,is_active',
    columns: [
      { key: 'category', label: 'Категория', type: 'relation', options: 'productCategories', required: true },
      { key: 'name', label: 'Название', type: 'text', required: true, wide: true },
      { key: 'sort', label: 'Сортировка', type: 'number' },
      { key: 'is_active', label: 'Активно', type: 'boolean' },
    ],
  },
  admin_methods: {
    collection: 'product_application_methods',
    endpoint: '/items/product_application_methods',
    title: 'Виды нанесения',
    sort: 'category,sort,name',
    fields: 'id,category,name,sort,is_active',
    columns: [
      { key: 'category', label: 'Категория', type: 'relation', options: 'productCategories' },
      { key: 'name', label: 'Название', type: 'text', required: true, wide: true },
      { key: 'sort', label: 'Сортировка', type: 'number' },
      { key: 'is_active', label: 'Активно', type: 'boolean' },
    ],
  },
  admin_routing: {
    collection: 'product_routing_rules',
    endpoint: '/items/product_routing_rules',
    title: 'Правила маршрутизации',
    sort: 'priority,name',
    fields: 'id,name,product_category,product_subcategory,application_method,contractor_1,contractor_2,priority,is_active',
    columns: [
      { key: 'name', label: 'Название', type: 'text', required: true, wide: true },
      { key: 'product_category', label: 'Категория', type: 'relation', options: 'productCategories', required: true },
      { key: 'product_subcategory', label: 'Подкатегория', type: 'relation', options: 'productSubcategories' },
      { key: 'application_method', label: 'Вид нанесения', type: 'relation', options: 'applicationMethods' },
      { key: 'contractor_1', label: 'Подрядчик 1', type: 'relation', options: 'contractors' },
      { key: 'contractor_2', label: 'Подрядчик 2', type: 'relation', options: 'contractors' },
      { key: 'priority', label: 'Приоритет', type: 'number' },
      { key: 'is_active', label: 'Активно', type: 'boolean' },
    ],
  },
  admin_order_statuses: {
    collection: 'order_statuses',
    endpoint: '/items/order_statuses',
    title: 'Статусы заказов',
    sort: 'sort,name',
    fields: 'id,name,sort,is_active',
    columns: [
      { key: 'name', label: 'Название', type: 'text', required: true, wide: true },
      { key: 'sort', label: 'Сортировка', type: 'number' },
      { key: 'is_active', label: 'Активно', type: 'boolean' },
    ],
  },
  admin_production_statuses: {
    collection: 'production_statuses',
    endpoint: '/items/production_statuses',
    title: 'Статусы производства',
    sort: 'sort,name',
    fields: 'id,name,sort,is_active',
    columns: [
      { key: 'name', label: 'Название', type: 'text', required: true, wide: true },
      { key: 'sort', label: 'Сортировка', type: 'number' },
      { key: 'is_active', label: 'Активно', type: 'boolean' },
    ],
  },
};

const baseFilters = [
  { id: 'all', title: 'Все' },
  { id: 'today', title: 'Сегодня' },
  { id: 'overdue', title: 'Просрочено' },
  { id: 'this_week', title: 'Эта неделя' },
  { id: 'next_week', title: 'Следующая неделя' },
  { id: 'this_month', title: 'Этот месяц' },
  { id: 'next_month', title: 'Следующий месяц' },
  { id: 'missing_cost', title: 'Без себестоимости' },
  { id: 'layout_revision', title: 'Доработка макета' },
  { id: 'in_office', title: 'В офисе' },
  { id: 'ready', title: 'Готово' },
];

const officeStatusChoices = [
  { text: 'Не в офисе', value: 'not_in_office' },
  { text: 'В офисе', value: 'in_office' },
  { text: 'Выдан', value: 'issued' },
];

const itemStatusChoices = [
  { text: 'Новый', value: 'new' },
  { text: 'Согласование', value: 'approval' },
  { text: 'Доработка макета', value: 'layout_revision' },
  { text: 'Отправлен в работу', value: 'sent_to_work' },
  { text: 'В работе', value: 'in_work' },
  { text: 'Готов', value: 'ready' },
  { text: 'Доставлен', value: 'delivered' },
  { text: 'Отменен', value: 'cancelled' },
];

const shippingMethodChoices = [
  { text: 'Выдача в офисе', value: 'office_pickup' },
  { text: 'Доставка клиенту', value: 'client_delivery' },
  { text: 'Транспортная компания', value: 'transport_company' },
];

export const CostingModule = {
  data() {
    return {
      rows: [],
      contractors: [],
      loading: true,
      saving: {},
      error: '',
      search: '',
      activeFilter: 'all',
      limit: 100,
      activeTab: 'dashboard',
      moduleSection: 'orders',
      currentRoleName: '',
      tabs,
      officeStatusChoices,
      itemStatusChoices,
      shippingMethodChoices,
      expenseTypes,
      officeBuckets,
      officeSortOptions,
      productionRows: [],
      screenRows: [],
      officeRows: [],
      officeIssueRows: [],
      officeArchiveRows: [],
      officeArchiveItems: [],
      officeBucket: 'planned',
      officeSort: 'deadline',
      productionStatuses: [],
      orderStatuses: [],
      financeRows: [],
      financeItemRows: [],
      financeLevel: 'orders',
      financeCustomerFilter: '',
      financeCompanyFilter: '',
      financeDateFrom: '',
      financeDateTo: '',
      contractorRows: [],
      adminRows: {},
      adminEditing: null,
      adminForm: {},
      adminSaving: false,
      directusUsers: [],
      directusRoles: [],
      employeePositions: [],
      expenseRows: [],
      salaryRows: [],
      managerFinanceSummary: null,
      myOrderRows: [],
      allOrderRows: [],
      urgentRows: [],
      deadlineRows: {},
      activeDeadlineBucket: 'urgent',
      paymentTypes: [],
      employees: [],
      customers: [],
      companies: [],
      productCategories: [],
      productSubcategories: [],
      applicationMethods: [],
      currentUserId: '',
      currentEmployeeId: null,
      expandedOfficeOrders: {},
      expandedClientRows: {},
      paymentDialog: null,
      newOrderDialog: null,
      expenseDialog: null,
      selectedRows: {},
      detail: null,
      entityDetail: null,
    };
  },

  computed: {
    activeTabTitle() {
      return tabs.find((tab) => tab.id === this.activeTab)?.title || '';
    },

    moduleTitle() {
      return moduleSections[this.moduleSection]?.title || 'Рабочий центр';
    },

    availableTabs() {
      const workTabs = ['dashboard', 'queue', 'problems', 'search', 'deadlines'];
      const withWorkTabs = (ids) => tabs.filter((tab) => workTabs.includes(tab.id) || ids.includes(tab.id));
      let roleTabs = [];
      if (['Administrator', 'Управляющий'].includes(this.currentRoleName)) roleTabs = tabs;
      else if (this.currentRoleName === 'Производство') roleTabs = withWorkTabs(['production']);
      else if (this.currentRoleName === 'Шелкография') roleTabs = withWorkTabs(['screen']);
      else if (this.currentRoleName === 'Менеджер') roleTabs = withWorkTabs(['my_orders', 'office', 'finance', 'clients', 'companies']);
      else if (this.currentRoleName === 'Офис-менеджер') roleTabs = withWorkTabs(['my_orders', 'office']);
      else roleTabs = [];

      const section = moduleSections[this.moduleSection];
      if (!section) return roleTabs;
      if (!section.roles.includes(this.currentRoleName)) return [];

      const sectionTabs = new Set(section.tabs);
      return roleTabs.filter((tab) => sectionTabs.has(tab.id));
    },

    activeCollection() {
      return tabs.find((tab) => tab.id === this.activeTab)?.collection || 'contractor_costing';
    },

    isAdminDictionaryTab() {
      return adminDictionaryTabs.includes(this.activeTab);
    },

    activeAdminConfig() {
      return adminConfigs[this.activeTab] || null;
    },

    activeAdminRows() {
      if (!this.activeAdminConfig) return [];
      const rows = this.adminRows[this.activeTab] || [];
      const query = (this.search || '').trim().toLowerCase();
      if (!query || this.moduleSection !== 'admin') return rows;
      return rows.filter((row) => this.adminRowSearchText(row).includes(query));
    },

    canSeeCostingTotals() {
      return this.currentRoleName === 'Administrator';
    },

    canCreateOrders() {
      return ['Administrator', 'Управляющий', 'Менеджер'].includes(this.currentRoleName);
    },

    canCreateOrderHere() {
      return this.canCreateOrders && ['dashboard', 'all_orders', 'my_orders'].includes(this.activeTab);
    },

    navigationGroups() {
      const groups = [
        { title: 'Работа', tabs: ['dashboard', 'queue', 'problems', 'search'] },
        { title: 'Заказы', tabs: ['all_orders', 'deadlines', 'my_orders'] },
        { title: 'Производство', tabs: ['production', 'screen'] },
        { title: 'Управление', tabs: ['costing'] },
        { title: 'Офис', tabs: ['office'] },
        { title: 'Клиенты', tabs: ['clients', 'companies'] },
        { title: 'Финансы', tabs: ['finance'] },
        { title: 'Админка', tabs: ['admin_employees', 'admin_users', 'admin_positions', 'contractors', 'admin_categories', 'admin_subcategories', 'admin_methods', 'admin_routing', 'admin_order_statuses', 'admin_production_statuses', 'payroll', 'expenses'] },
      ];
      const available = new Map(this.availableTabs.map((tab) => [tab.id, tab]));
      return groups
        .map((group) => ({
          ...group,
          tabs: group.tabs.map((id) => available.get(id)).filter(Boolean),
        }))
        .filter((group) => group.tabs.length);
    },

    quickFilters() {
      if (['dashboard', 'search', 'deadlines'].includes(this.activeTab)) return baseFilters.filter((filter) => filter.id === 'all');
      if (this.activeTab === 'all_orders') return baseFilters.filter((filter) => ['all', 'today', 'overdue', 'this_week', 'next_week', 'this_month', 'next_month'].includes(filter.id));
      if (this.activeTab === 'problems') return baseFilters.filter((filter) => this.problemRows.some((row) => filter.id === 'all' || row.filters.includes(filter.id)));
      if (this.activeTab === 'my_orders') return baseFilters.filter((filter) => ['all', 'today', 'overdue', 'this_week', 'next_week', 'this_month', 'next_month'].includes(filter.id));
      if (this.activeTab === 'costing') return baseFilters.filter((filter) => ['all', 'missing_cost'].includes(filter.id));
      if (['payroll', 'expenses', 'finance', 'clients', 'companies', 'contractors'].includes(this.activeTab) || this.isAdminDictionaryTab) return baseFilters.filter((filter) => filter.id === 'all');
      if (this.activeTab === 'office') return baseFilters.filter((filter) => filter.id === 'all');
      if (['production', 'screen'].includes(this.activeTab)) {
        return baseFilters.filter((filter) => ['all', 'today', 'overdue', 'layout_revision', 'ready'].includes(filter.id));
      }

      return baseFilters.filter((filter) => this.queueRows.some((row) => filter.id === 'all' || row.filters.includes(filter.id)));
    },

    visibleQuickFilters() {
      return this.quickFilters.length > 1 ? this.quickFilters : [];
    },

    dashboardCards() {
      const cards = [];
      const queueCount = this.queueRows.length;
      const problemCount = this.problemRows.length;
      cards.push({ title: 'Очередь задач', value: queueCount, note: 'активных действий', accent: 'orange' });
      cards.push({ title: 'Требует внимания', value: problemCount, note: 'проверить сегодня', accent: problemCount ? 'danger' : 'green' });

      if (this.availableTabs.some((tab) => tab.id === 'my_orders')) {
        cards.push({ title: 'Мои заказы', value: this.myOrderRows.length, note: 'в работе', accent: 'blue' });
      }

      if (this.availableTabs.some((tab) => tab.id === 'all_orders')) {
        cards.push({ title: 'Все заказы', value: this.allOrderRows.length, note: 'общая картина', accent: 'blue' });
      }

      if (this.availableTabs.some((tab) => tab.id === 'deadlines')) {
        const urgent = (this.deadlineRows.urgent || []).length;
        const today = (this.deadlineRows.today || []).length;
        cards.push({ title: 'Горящие сроки', value: urgent, note: 'просрочено или сегодня', accent: urgent ? 'danger' : 'green' });
        cards.push({ title: 'Сегодня', value: today, note: 'заказов по сроку', accent: today ? 'orange' : 'green' });
      }

      if (this.availableTabs.some((tab) => tab.id === 'office')) {
        cards.push({ title: 'В офисе', value: this.officeIssueRows.filter((row) => row.office_status === 'in_office').length, note: 'заказов лежит в офисе', accent: 'orange' });
      }

      if (this.availableTabs.some((tab) => tab.id === 'costing')) {
        const missingCost = this.rows.filter((row) => this.parseMoney(row.contractor_1_cost) === 0 && this.parseMoney(row.contractor_2_cost) === 0).length;
        cards.push({ title: 'Без себестоимости', value: missingCost, note: 'позиций', accent: missingCost ? 'danger' : 'green' });
      }

      if (this.availableTabs.some((tab) => tab.id === 'finance')) {
        const revenue = this.financeRows.reduce((sum, row) => sum + this.parseMoney(row.order_sum), 0);
        const paid = this.financeRows.reduce((sum, row) => sum + this.parseMoney(row.paid_amount), 0);
        const debt = this.financeRows.reduce((sum, row) => sum + this.parseMoney(row.payment_due), 0);
        cards.push({ title: 'Сумма заказов', value: this.formatMoney(revenue), note: 'по сверке', accent: 'blue' });
        cards.push({ title: 'Оплачено', value: this.formatMoney(paid), note: 'по сверке', accent: 'green' });
        cards.push({ title: 'К оплате', value: this.formatMoney(debt), note: 'остаток', accent: debt ? 'danger' : 'green' });
      }

      if (this.availableTabs.some((tab) => tab.id === 'expenses')) {
        const expensesMonth = this.expenseRows.reduce((sum, row) => {
          return this.isCurrentMonth(row.expense_date) ? sum + this.parseMoney(row.amount) : sum;
        }, 0);
        const salaryDebt = this.salaryRows.reduce((sum, row) => sum + Math.max(this.parseMoney(row.salary_debt), 0), 0);
        cards.push({ title: 'Расходы месяца', value: this.formatMoney(expensesMonth), note: 'операционные выплаты', accent: 'orange' });
        cards.push({ title: 'Долг по ЗП', value: this.formatMoney(salaryDebt), note: 'оклад + проценты - выплаты', accent: salaryDebt ? 'danger' : 'green' });
      }

      return cards;
    },

    deadlineBucketTabs() {
      return deadlineBuckets.map((bucket) => ({
        ...bucket,
        count: (this.deadlineRows[bucket.id] || []).length,
      }));
    },

    visibleDeadlineRows() {
      const rows = this.deadlineRows[this.activeDeadlineBucket] || [];
      return this.applySearchAndFilter(rows, (row) => [
        row.order_number,
        row.customer_display,
        row.manager_name,
        row.order_status_name,
        row.shipping_method_name,
      ], () => true);
    },

    problemRows() {
      const rows = [];
      this.queueRows.forEach((row) => rows.push(row));

      this.financeRows.forEach((row) => {
        if (this.parseMoney(row.payment_due) > 0) {
          rows.push(this.queueItem('finance', row, 'Неоплаченный заказ', `К оплате ${this.formatMoney(row.payment_due)}`, ['missing_cost']));
        }
      });

      this.myOrderRows.forEach((row) => {
        if (this.isOverdue(row.deadline)) {
          rows.push(this.queueItem('my_orders', row, 'Просрочен срок', row.order_status_name || 'Проверить заказ', ['overdue']));
        } else if (this.isToday(row.deadline)) {
          rows.push(this.queueItem('my_orders', row, 'Срок сегодня', row.order_status_name || 'Проверить заказ', ['today']));
        }
      });

      return this.applySearchAndFilter(rows);
    },

    globalSearchRows() {
      if (!this.search.trim()) return [];
      const rows = [
        ...this.myOrderRows.map((row) => this.searchItem('Мой заказ', 'my_orders', row)),
        ...this.allOrderRows.map((row) => this.searchItem('Все заказы', 'all_orders', row)),
        ...Object.values(this.deadlineRows).flat().map((row) => this.searchItem('Сроки', 'deadlines', row)),
        ...this.financeRows.map((row) => this.searchItem('Сверка', 'finance', row)),
        ...this.rows.map((row) => this.searchItem('Себестоимость', 'costing', row)),
        ...this.productionRows.map((row) => this.searchItem('Производство', 'production', row)),
        ...this.screenRows.map((row) => this.searchItem('Шелкография', 'screen', row)),
        ...this.officeIssueRows.map((row) => this.searchItem('Офис', 'office_issue', row)),
        ...this.officeArchiveRows.map((row) => this.searchItem('Архив офиса', 'office_issue_archive', row)),
      ];

      return this.applySearchAndFilter(rows);
    },

    queueRows() {
      const rows = [];

      if (this.availableTabs.some((tab) => tab.id === 'costing')) {
        this.rows.forEach((row) => {
          const missingCost = !this.contractorId(row.contractor_1) && !this.contractorId(row.contractor_2);
          const zeroCost = this.parseMoney(row.contractor_1_cost) === 0 && this.parseMoney(row.contractor_2_cost) === 0;
          if (missingCost || zeroCost) {
            rows.push(this.queueItem('costing', row, 'Заполнить себестоимость', 'Без подрядчика или себестоимости', ['missing_cost']));
          }
        });
      }

      if (this.availableTabs.some((tab) => tab.id === 'production')) {
        this.productionRows.forEach((row) => this.workQueueItems(rows, 'production', row));
      }

      if (this.availableTabs.some((tab) => tab.id === 'screen')) {
        this.screenRows.forEach((row) => this.workQueueItems(rows, 'screen', row));
      }

      if (this.availableTabs.some((tab) => tab.id === 'office')) {
        this.officeIssueRows.forEach((row) => {
          if (row.office_status === 'in_office') {
            rows.push(this.queueItem('office_issue', row, 'Выдать заказ', 'Заказ находится в офисе', ['in_office']));
          }
        });
      }

      return this.applySearchAndFilter(rows);
    },

    visibleRows() {
      return this.applySearchAndFilter(this.rows, (row) => [
        row.order_number,
        row.product_name,
        this.relatedName(row.customer),
        this.relatedName(row.customer_company),
        this.relatedName(row.manager_employee, 'full_name'),
      ], (row) => {
        if (this.activeFilter !== 'missing_cost') return true;
        return this.parseMoney(row.contractor_1_cost) === 0 && this.parseMoney(row.contractor_2_cost) === 0;
      });
    },

    visibleProductionRows() {
      return this.filterRows(this.productionRows);
    },

    visibleScreenRows() {
      return this.filterRows(this.screenRows);
    },

    visibleOfficeRows() {
      return this.applySearchAndFilter(this.officeRows, (row) => [
        row.order_number,
        row.product_name,
        row.customer_name,
        row.customer_company_name,
        this.relatedName(row.manager_employee, 'full_name'),
      ], (row) => {
        if (this.activeFilter === 'all') return true;
        if (this.activeFilter === 'in_office') return row.office_status === 'in_office';
        if (this.activeFilter === 'ready') return row.office_status === 'issued';
        return true;
      });
    },

    visibleFinanceRows() {
      return this.applySearchAndFilter(this.financeRows, (row) => [
        row.order_number,
        row.customer_name,
        row.customer_company_name,
        row.counterparty_name,
        row.manager_name,
        row.order_status_name,
        row.reconciliation_result,
      ], (row) => this.matchesFinanceEntityFilter(row));
    },

    visibleFinanceItemRows() {
      return this.applySearchAndFilter(this.financeItemRows, (row) => [
        row.order_number,
        row.customer_name,
        row.customer_company_name,
        row.counterparty_name,
        row.manager_name,
        row.order_status_name,
        row.product_name,
        row.reconciliation_result,
      ], (row) => this.matchesFinanceEntityFilter(row));
    },

    visibleFinanceItemRowsAllocated() {
      return this.allocatePaymentsToItems(this.visibleFinanceItemRows);
    },

    visibleReconciliationRows() {
      return this.financeLevel === 'items' ? this.visibleFinanceItemRows : this.visibleFinanceRows;
    },

    visibleClientRows() {
      const groups = new Map();

      this.visibleFinanceRows.forEach((row) => {
        const customerId = this.entityId(row.customer) || row.customer_name || '';
        const companyId = this.entityId(row.customer_company) || row.customer_company_name || '';
        const key = `${customerId || 'no-customer'}:${companyId || 'personal'}`;
        const current = groups.get(key) || {
          key,
          customer: row.customer,
          customer_name: row.customer_name || row.counterparty_name || '-',
          customer_company: row.customer_company,
          customer_company_name: row.customer_company_name || '',
          manager_name: row.manager_name || '-',
          order_sum: 0,
          paid_amount: 0,
          payment_due: 0,
          overpayment: 0,
          orders: [],
        };

        current.order_sum += this.parseMoney(row.order_sum);
        current.paid_amount += this.parseMoney(row.paid_amount);
        current.payment_due += this.parseMoney(row.payment_due);
        current.overpayment += this.parseMoney(row.overpayment);
        if (!current.manager_name || current.manager_name === '-') current.manager_name = row.manager_name || '-';
        current.orders.push(row);
        groups.set(key, current);
      });

      return [...groups.values()].sort((a, b) => {
        const debtDiff = this.parseMoney(b.payment_due) - this.parseMoney(a.payment_due);
        if (debtDiff) return debtDiff;
        return String(a.customer_name).localeCompare(String(b.customer_name), 'ru');
      });
    },

    visibleCustomerDirectoryRows() {
      return this.applySearchAndFilter(this.customers.map((customer) => {
        const orders = this.financeRows.filter((row) => {
          const rowCustomerId = this.entityId(row.customer);
          return rowCustomerId && rowCustomerId === String(customer.id);
        });
        const orderSum = orders.reduce((sum, row) => sum + this.parseMoney(row.order_sum), 0);
        const paid = orders.reduce((sum, row) => sum + this.parseMoney(row.paid_amount), 0);
        const due = orders.reduce((sum, row) => sum + this.parseMoney(row.payment_due), 0);
        const balance = orderSum ? paid - orderSum : this.parseMoney(customer.balance);

        return {
          ...customer,
          key: `customer:${customer.id}`,
          orders,
          orders_count: orders.length,
          orders_total_sum: orderSum || this.parseMoney(customer.orders_total_sum),
          payments_total_in: paid || this.parseMoney(customer.payments_total_in),
          payment_due: due,
          balance,
        };
      }), (row) => [
        row.name,
        row.phone,
        row.email,
        row.vk_page_url,
        this.relatedName(row.company),
      ], () => true);
    },

    visibleCompanyDirectoryRows() {
      return this.applySearchAndFilter(this.companies.map((company) => {
        const customers = this.customers.filter((customer) => String(this.entityId(customer.company)) === String(company.id));
        const orders = this.financeRows.filter((row) => {
          const rowCompanyId = this.entityId(row.customer_company);
          return rowCompanyId && rowCompanyId === String(company.id);
        });
        const orderSum = orders.reduce((sum, row) => sum + this.parseMoney(row.order_sum), 0);
        const paid = orders.reduce((sum, row) => sum + this.parseMoney(row.paid_amount), 0);
        const due = orders.reduce((sum, row) => sum + this.parseMoney(row.payment_due), 0);
        const balance = orderSum ? paid - orderSum : this.parseMoney(company.balance);

        return {
          ...company,
          key: `company:${company.id}`,
          customers,
          orders,
          orders_count: orders.length,
          customers_count: customers.length,
          orders_total_sum: orderSum || this.parseMoney(company.orders_total_sum),
          payments_total_in: paid || this.parseMoney(company.payments_total_in),
          payment_due: due,
          balance,
        };
      }), (row) => [
        row.name,
        row.phone,
        row.email,
        row.customers.map((customer) => customer.name).join(' '),
      ], () => true);
    },

    financeSummary() {
      if (this.financeLevel === 'items') {
        const rows = this.visibleFinanceItemRows;
        const uniqueOrders = new Map();

        rows.forEach((row) => {
          const key = this.entityId(row.order_link) || row.order_number || `item-${row.id}`;
          if (!uniqueOrders.has(key)) {
            uniqueOrders.set(key, row);
          }
        });

        const summary = {
          order_sum: rows.reduce((total, row) => total + this.parseMoney(row.item_sum), 0),
          paid_amount: 0,
          payment_due: 0,
          overpayment: 0,
        };

        uniqueOrders.forEach((row) => {
          summary.paid_amount += this.parseMoney(row.paid_amount);
          summary.payment_due += this.parseMoney(row.payment_due);
          summary.overpayment += this.parseMoney(row.overpayment);
        });

        return summary;
      }

      return this.visibleFinanceRows.reduce((summary, row) => {
        summary.order_sum += this.parseMoney(row.order_sum);
        summary.paid_amount += this.parseMoney(row.paid_amount);
        summary.payment_due += this.parseMoney(row.payment_due);
        summary.overpayment += this.parseMoney(row.overpayment);
        return summary;
      }, {
        order_sum: 0,
        paid_amount: 0,
        payment_due: 0,
        overpayment: 0,
      });
    },

    managerFinanceStats() {
      const row = this.managerFinanceSummary || {};
      const fallback = this.financeRows.reduce((summary, item) => {
        summary.orders_sum += this.parseMoney(item.order_sum);
        summary.paid_orders_sum += this.parseMoney(item.paid_amount);
        summary.unpaid_orders_sum += this.parseMoney(item.payment_due);
        return summary;
      }, {
        orders_sum: 0,
        paid_orders_sum: 0,
        unpaid_orders_sum: 0,
      });
      const orderPercent = this.parseMoney(row.order_percent);
      const ordersSum = this.parseMoney(row.orders_sum) || fallback.orders_sum;
      const paidOrdersSum = this.parseMoney(row.paid_orders_sum) || fallback.paid_orders_sum;
      const unpaidOrdersSum = this.parseMoney(row.unpaid_orders_sum) || fallback.unpaid_orders_sum;
      const commissionTotal = this.parseMoney(row.commission_total) || (ordersSum * orderPercent / 100);
      const commissionAccrued = this.parseMoney(row.commission_accrued) || (paidOrdersSum * orderPercent / 100);
      const commissionExpected = this.parseMoney(row.commission_expected) || (unpaidOrdersSum * orderPercent / 100);
      const commissionPaid = this.parseMoney(row.commission_paid);
      const commissionToPay = this.parseMoney(row.commission_to_pay) || Math.max(commissionAccrued - commissionPaid, 0);
      const paidRatio = ordersSum > 0 ? Math.min(100, Math.round((paidOrdersSum / ordersSum) * 100)) : 0;

      return {
        employee_name: row.employee_name || '',
        order_percent: orderPercent,
        orders_count: Number(row.orders_count || this.financeRows.length || 0),
        orders_sum: ordersSum,
        paid_orders_sum: paidOrdersSum,
        unpaid_orders_sum: unpaidOrdersSum,
        commission_total: commissionTotal,
        commission_accrued: commissionAccrued,
        commission_expected: commissionExpected,
        commission_paid: commissionPaid,
        commission_to_pay: commissionToPay,
        paid_ratio: paidRatio,
      };
    },

    managerFinanceMotivation() {
      const stats = this.managerFinanceStats;

      if (!stats.orders_count) return 'Пока нет заказов в периоде. Самое время забрать первый.';
      if (stats.unpaid_orders_sum <= 0) return `Отлично: все оплачено, к выплате ${this.formatMoney(stats.commission_to_pay)}.`;
      if (stats.paid_ratio >= 70) return `Оплачено ${stats.paid_ratio}% выручки. Осталось дожать ${this.formatMoney(stats.unpaid_orders_sum)}.`;
      return `В оплатах есть запас роста: ${this.formatMoney(stats.commission_expected)} процентов ждут оплату клиентами.`;
    },

    visibleContractorRows() {
      return this.applySearchAndFilter(this.contractorRows, (row) => [
        row.name,
        row.contact_name,
        row.phone,
        row.email,
      ], () => true);
    },

    visibleExpenseRows() {
      return this.applySearchAndFilter(this.expenseRows, (row) => [
        this.expenseTypeName(row.expense_type),
        this.relatedName(row.employee, 'full_name'),
        this.relatedName(row.payment_type),
        row.comment,
      ], (row) => !['salary_payment', 'employee_advance'].includes(row.expense_type));
    },

    visiblePayrollExpenseRows() {
      return this.applySearchAndFilter(this.expenseRows, (row) => [
        this.expenseTypeName(row.expense_type),
        this.relatedName(row.employee, 'full_name'),
        this.relatedName(row.payment_type),
        row.comment,
      ], (row) => ['salary_payment', 'employee_advance'].includes(row.expense_type));
    },

    visibleSalaryRows() {
      return this.applySearchAndFilter(this.salaryRows, (row) => [
        row.employee_name,
        row.position_name,
      ], () => true);
    },

    visibleMyOrderRows() {
      return this.applySearchAndFilter(this.myOrderRows, (row) => [
        row.order_number,
        row.customer_display,
        row.manager_name,
        row.order_status_name,
        row.shipping_method_name,
      ], (row) => this.matchesDeadlineFilter(row));
    },

    visibleAllOrderRows() {
      return this.applySearchAndFilter(this.allOrderRows, (row) => [
        row.order_number,
        row.customer_display,
        row.manager_name,
        row.shipping_method_name,
      ], (row) => this.matchesDeadlineFilter(row));
    },

    visibleOfficeIssueRows() {
      const source = this.officeBucket === 'issued'
        ? this.officeArchiveRows
        : this.officeIssueRows.filter((row) => {
          if (this.officeBucket === 'in_office') return row.office_status === 'in_office';
          return row.office_status !== 'in_office' && row.office_status !== 'issued';
        });

      return this.sortOfficeRows(this.applySearchAndFilter(source, (row) => [
        row.order_number,
        row.customer_name,
        row.customer_phone,
        row.customer_company_name,
        row.manager_name,
        row.order_status_name,
        row.payment_comment,
      ], () => true));
    },
  },

  async mounted() {
    this.injectStyles();
    await this.loadCurrentUser();
    if (!this.availableTabs.some((tab) => tab.id === this.activeTab)) {
      this.activeTab = this.availableTabs[0]?.id || '';
    }

    await this.loadAllowedData();
  },

  methods: {
    setTab(tab) {
      this.activeTab = tab;
      this.activeFilter = 'all';
      this.detail = null;
    },

    setOfficeBucket(bucket) {
      this.officeBucket = bucket;
      this.activeFilter = 'all';
      this.expandedOfficeOrders = {};
    },

    filterRows(rows) {
      return this.applySearchAndFilter(rows, (row) => [
          row.order_number,
          row.product_name,
          row.technical_task_text,
          row.production_comment,
          row.customer_name,
          row.customer_company_name,
          this.relatedName(row.customer),
          this.relatedName(row.customer_company),
          this.relatedName(row.manager_employee, 'full_name'),
        ], (row) => this.matchesWorkFilter(row));
    },

    applySearchAndFilter(rows, values = null, predicate = null) {
      const query = this.search.trim().toLowerCase();
      return rows.filter((row) => {
        const searchable = values ? values(row) : [
          row.section,
          row.reason,
          row.order_number,
          row.product_name,
          row.customer_name,
          row.customer_company_name,
          row.manager_name,
          row.technical_task_text,
          row.production_comment,
        ];

        const matchesSearch = !query || searchable.some((value) => String(value || '').toLowerCase().includes(query));
        const matchesFilter = predicate ? predicate(row) : (this.activeFilter === 'all' || row.filters?.includes(this.activeFilter));
        return matchesSearch && matchesFilter;
      });
    },

    matchesWorkFilter(row) {
      if (this.activeFilter === 'all') return true;
      if (this.activeFilter === 'today') return this.isToday(row.deadline);
      if (this.activeFilter === 'overdue') return this.isOverdue(row.deadline);
      if (this.activeFilter === 'layout_revision') return this.statusName(row.production_status) === 'Доработка макета';
      if (this.activeFilter === 'ready') return this.statusName(row.production_status) === 'Готов';
      return true;
    },

    queueItem(type, row, section, reason, filters = []) {
      return {
        id: `${type}:${row.id}`,
        type,
        row,
        section,
        reason,
        filters,
        order_number: this.orderNumber(row),
        customer_name: row.customer_name || row.customer_display || row.counterparty_name || this.relatedName(row.customer),
        customer_company_name: row.customer_company_name || this.relatedName(row.customer_company),
        manager_name: row.manager_name || this.relatedName(row.manager_employee, 'full_name'),
        product_name: row.product_name,
        quantity: row.quantity,
        deadline: row.deadline || row.date,
        technical_task_text: row.technical_task_text,
        production_comment: row.production_comment,
      };
    },

    workQueueItems(list, type, row) {
      const status = this.statusName(row.production_status);
      if (this.isOverdue(row.deadline)) {
        list.push(this.queueItem(type, row, 'Срок просрочен', status || 'Проверить производство', ['overdue']));
      } else if (this.isToday(row.deadline)) {
        list.push(this.queueItem(type, row, 'Срок сегодня', status || 'Проверить производство', ['today']));
      }

      if (status === 'Доработка макета') {
        list.push(this.queueItem(type, row, 'Доработка макета', 'Нужны правки по макету', ['layout_revision']));
      }

      if (status === 'Готов') {
        list.push(this.queueItem(type, row, 'Готово', 'Позиция готова к следующему этапу', ['ready']));
      }
    },

    isToday(value) {
      if (!value) return false;
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return false;
      const now = new Date();
      return date.getFullYear() === now.getFullYear()
        && date.getMonth() === now.getMonth()
        && date.getDate() === now.getDate();
    },

    isCurrentMonth(value) {
      if (!value) return false;
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return false;
      const now = new Date();
      return date.getFullYear() === now.getFullYear()
        && date.getMonth() === now.getMonth();
    },

    weekRange(offsetWeeks = 0) {
      const start = new Date();
      start.setHours(0, 0, 0, 0);
      const mondayOffset = (start.getDay() + 6) % 7;
      start.setDate(start.getDate() - mondayOffset + offsetWeeks * 7);
      const end = new Date(start);
      end.setDate(start.getDate() + 7);
      return { start, end };
    },

    isCurrentWeek(value) {
      if (!value) return false;
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return false;
      date.setHours(0, 0, 0, 0);
      const { start, end } = this.weekRange(0);
      return date >= start && date < end;
    },

    isNextWeek(value) {
      if (!value) return false;
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return false;
      date.setHours(0, 0, 0, 0);
      const { start, end } = this.weekRange(1);
      return date >= start && date < end;
    },

    isNextMonth(value) {
      if (!value) return false;
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return false;
      const now = new Date();
      const nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
      return date.getFullYear() === nextMonth.getFullYear()
        && date.getMonth() === nextMonth.getMonth();
    },

    isOverdue(value) {
      if (!value) return false;
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return false;
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      date.setHours(0, 0, 0, 0);
      return date < today;
    },

    async loadCurrentUser() {
      try {
        const payload = await this.request('/users/me?fields=id,role.name');
        this.currentUserId = payload?.data?.id || '';
        this.currentRoleName = payload?.data?.role?.name || '';

        if (this.currentUserId) {
          try {
            const employeePayload = await this.request(`/items/employees?fields=id,full_name&filter[directus_user][_eq]=${this.currentUserId}&limit=1`);
            this.currentEmployeeId = employeePayload?.data?.[0]?.id || null;
          } catch {
            this.currentEmployeeId = null;
          }
        }
      } catch {
        this.currentUserId = '';
        this.currentEmployeeId = null;
        this.currentRoleName = '';
      }
    },

    async loadAllowedData() {
      const allowed = new Set(this.availableTabs.map((tab) => tab.id));
      const tasks = [];

      if (allowed.has('all_orders')) tasks.push(this.loadAllOrderRows());
      if (allowed.has('deadlines')) tasks.push(this.loadDeadlineRows());
      if (allowed.has('my_orders')) tasks.push(this.loadMyOrderRows());
      if (allowed.has('costing')) tasks.push(this.loadRows(), this.loadContractors());
      if (allowed.has('expenses') || allowed.has('payroll')) tasks.push(this.loadExpenseRows(), this.loadSalaryRows(), this.loadEmployees(), this.loadPaymentTypes());
      if (allowed.has('finance')) tasks.push(this.loadFinanceRows(), this.loadFinanceItemRows(), this.loadManagerFinanceSummary(), this.loadCustomers(), this.loadCompanies());
      if (allowed.has('clients') || allowed.has('companies')) tasks.push(this.loadFinanceRows(), this.loadCustomers(), this.loadCompanies());
      if (!allowed.has('finance') && !allowed.has('clients') && !allowed.has('companies') && (allowed.has('my_orders') || allowed.has('all_orders') || allowed.has('deadlines') || allowed.has('office'))) tasks.push(this.loadCustomers(), this.loadCompanies());
      if (allowed.has('contractors')) tasks.push(this.loadContractorRows());
      if (allowed.has('production') || allowed.has('screen') || allowed.has('my_orders')) tasks.push(this.loadProductionStatuses());
      if (allowed.has('my_orders') || allowed.has('all_orders') || allowed.has('deadlines')) tasks.push(this.loadOrderStatuses());
      if (allowed.has('production')) tasks.push(this.loadWorkRows('production_work'));
      if (allowed.has('screen')) tasks.push(this.loadWorkRows('screen_printing_work'));
      if (allowed.has('office')) tasks.push(this.loadOfficeRows(), this.loadOfficeIssueRows(), this.loadOfficeArchiveRows(), this.loadOfficeArchiveItems(), this.loadPaymentTypes());
      if (this.canCreateOrders) tasks.push(this.loadCreateOrderDictionaries());
      if (allowed.size && !allowed.has('expenses') && !allowed.has('payroll')) tasks.push(this.loadEmployees());
      if (this.moduleSection === 'admin') tasks.push(this.loadAdminData());

      await Promise.all(tasks);
    },

    searchItem(section, type, row) {
      return this.queueItem(type, row, section, row.order_status_name || this.statusName(row.production_status) || this.officeStatusName(row.office_status) || 'Найдено', ['all']);
    },

    setFilter(filter) {
      this.activeFilter = filter;
    },

    setFinanceLevel(level) {
      this.financeLevel = level;
    },

    clearFinanceEntityFilters() {
      this.financeCustomerFilter = '';
      this.financeCompanyFilter = '';
      this.financeDateFrom = '';
      this.financeDateTo = '';
    },

    entityId(value) {
      if (value === null || value === undefined || value === '') return '';
      if (typeof value === 'object') return String(value.id ?? value.value ?? '');
      return String(value);
    },

    matchesFinanceEntityFilter(row) {
      const customerId = this.entityId(row.customer);
      const companyId = this.entityId(row.customer_company);
      if (this.financeCompanyFilter && companyId !== String(this.financeCompanyFilter)) return false;
      if (this.financeCustomerFilter && customerId !== String(this.financeCustomerFilter)) return false;
      if (this.financeCustomerFilter && !this.financeCompanyFilter && companyId) return false;
      if (!this.matchesFinanceDateFilter(row)) return false;
      return true;
    },

    dateOnly(value) {
      if (!value) return '';
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return '';
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const day = String(date.getDate()).padStart(2, '0');
      return `${year}-${month}-${day}`;
    },

    matchesFinanceDateFilter(row) {
      const orderDate = this.dateOnly(row?.date);
      if (!orderDate) return !this.financeDateFrom && !this.financeDateTo;
      if (this.financeDateFrom && orderDate < this.financeDateFrom) return false;
      if (this.financeDateTo && orderDate > this.financeDateTo) return false;
      return true;
    },

    matchesDeadlineFilter(row) {
      if (this.activeFilter === 'all') return true;
      if (this.activeFilter === 'today') return this.isToday(row.deadline);
      if (this.activeFilter === 'overdue') return this.isOverdue(row.deadline);
      if (this.activeFilter === 'this_week') return this.isCurrentWeek(row.deadline);
      if (this.activeFilter === 'next_week') return this.isNextWeek(row.deadline);
      if (this.activeFilter === 'this_month') return this.isCurrentMonth(row.deadline);
      if (this.activeFilter === 'next_month') return this.isNextMonth(row.deadline);
      return true;
    },

    setDeadlineBucket(bucket) {
      this.activeDeadlineBucket = bucket;
    },

    sortOfficeRows(rows) {
      const sorted = [...rows];
      const value = (row) => {
        if (this.officeSort === 'order_number') return row.order_number || '';
        if (this.officeSort === 'customer') return row.customer_name || '';
        if (this.officeSort === 'payment_due') return this.parseMoney(row.office_payment_due ?? row.payment_due);
        if (this.officeSort === 'date') return row.date || '';
        return row.deadline || row.date || '';
      };

      return sorted.sort((left, right) => {
        const a = value(left);
        const b = value(right);
        if (typeof a === 'number' || typeof b === 'number') return Number(b || 0) - Number(a || 0);
        return String(a).localeCompare(String(b), 'ru');
      });
    },

    openDetail(type, row) {
      this.entityDetail = null;
      this.detail = { type, row };
    },

    closeDetail() {
      this.detail = null;
    },

    openParentOrderDetail(row) {
      this.openDetail('order', this.detailOrderContext(row));
    },

    openEntityDetail(type, row) {
      const entity = type === 'manager'
        ? this.resolveManager(row)
        : type === 'company'
          ? this.resolveCompany(row)
          : this.resolveCustomer(row);

      if (!entity) return;
      this.detail = null;
      this.entityDetail = { type, row, entity };
    },

    closeEntityDetail() {
      this.entityDetail = null;
    },

    toggleOfficeOrder(row) {
      const key = String(row.id);
      this.expandedOfficeOrders = {
        ...this.expandedOfficeOrders,
        [key]: !this.expandedOfficeOrders[key],
      };
    },

    isOfficeOrderExpanded(row) {
      return !!this.expandedOfficeOrders[String(row.id)];
    },

    toggleClientRow(row) {
      const key = String(row.key);
      this.expandedClientRows = {
        ...this.expandedClientRows,
        [key]: !this.expandedClientRows[key],
      };
    },

    isClientRowExpanded(row) {
      return !!this.expandedClientRows[String(row.key)];
    },

    officePositions(row) {
      if (this.officeBucket === 'issued') {
        return this.officeArchiveItems.filter((item) => Number(item.office_issue) === Number(row.id));
      }

      return this.officeRows.filter((item) => {
        const officeIssue = typeof item.office_issue === 'object' ? item.office_issue?.id : item.office_issue;
        const order = typeof item.order === 'object' ? item.order?.id : item.order;
        return Number(officeIssue || order) === Number(row.id || row.order_link);
      });
    },

    openPaymentDialog(row) {
      this.paymentDialog = {
        row,
        amount: this.moneyInput(row.office_payment_due ?? row.payment_due),
        paymentType: row.payment_type || '',
        comment: row.payment_comment || '',
      };
    },

    closePaymentDialog() {
      this.paymentDialog = null;
    },

    openExpenseDialog(type = 'other', employee = null) {
      this.error = '';
      this.expenseDialog = {
        saving: false,
        expense_date: this.todayInput(),
        expense_type: type,
        amount: '',
        employee: employee || '',
        payment_type: '',
        comment: '',
      };
    },

    closeExpenseDialog() {
      if (this.expenseDialog?.saving) return;
      this.expenseDialog = null;
    },

    async saveExpense() {
      if (!this.expenseDialog || this.expenseDialog.saving) return;
      const form = this.expenseDialog;
      const amount = this.parseMoney(form.amount);

      if (!amount) {
        this.error = 'Укажите сумму расхода.';
        return;
      }

      if (['salary_payment', 'employee_advance'].includes(form.expense_type) && !form.employee) {
        this.error = 'Для зарплаты или аванса нужно выбрать сотрудника.';
        return;
      }

      form.saving = true;
      this.error = '';

      try {
        await this.request('/items/business_expenses', {
          method: 'POST',
          body: JSON.stringify({
            expense_date: form.expense_date || this.todayInput(),
            expense_type: form.expense_type || 'other',
            amount,
            employee: form.employee ? Number(form.employee) : null,
            payment_type: form.payment_type ? Number(form.payment_type) : null,
            comment: form.comment || null,
          }),
        });

        this.expenseDialog = null;
        await Promise.all([
          this.loadExpenseRows(),
          this.loadSalaryRows(),
          this.loadFinanceRows(),
        ]);
      } catch (error) {
        this.error = error.message;
      } finally {
        if (this.expenseDialog) this.expenseDialog.saving = false;
      }
    },

    async saveOfficePayment() {
      if (!this.paymentDialog?.row) return;
      const { row, amount, paymentType, comment } = this.paymentDialog;
      const key = `office_issue:${row.id}:payment`;
      this.saving = { ...this.saving, [key]: true };
      this.error = '';

      try {
        await this.request(`/items/office_issue/${row.id}`, {
          method: 'PATCH',
          body: JSON.stringify({
            add_payment: this.parseMoney(amount),
            payment_type: paymentType || null,
            payment_comment: comment || null,
          }),
        });

        this.closePaymentDialog();
        await Promise.all([this.loadOfficeIssueRows(), this.loadOfficeRows(), this.loadOfficeArchiveRows(), this.loadOfficeArchiveItems()]);
      } catch (error) {
        this.error = error.message;
      } finally {
        const next = { ...this.saving };
        delete next[key];
        this.saving = next;
      }
    },

    async request(url, options = {}) {
      const response = await fetch(url, {
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          ...(options.headers || {}),
        },
        ...options,
      });

      const payload = await response.json().catch(() => ({}));

      if (!response.ok) {
        const message = payload?.errors?.[0]?.message || payload?.message || 'Ошибка запроса';
        throw new Error(message);
      }

      return payload;
    },

    adminRowSearchText(row) {
      if (!this.activeAdminConfig) return '';
      return this.activeAdminConfig.columns
        .map((column) => this.adminDisplayValue(row, column))
        .join(' ')
        .toLowerCase();
    },

    adminOptions(name, row = null) {
      if (name === 'contractors') return this.contractors;
      if (name === 'productCategories') return this.productCategories;
      if (name === 'productSubcategories') {
        const categoryId = row?.product_category || row?.category || this.adminForm.product_category || this.adminForm.category;
        if (categoryId) return this.productSubcategories.filter((item) => Number(this.entityId(item.category)) === Number(categoryId));
        return this.productSubcategories;
      }
      if (name === 'applicationMethods') {
        const categoryId = row?.product_category || row?.category || this.adminForm.product_category || this.adminForm.category;
        if (categoryId) return this.applicationMethods.filter((item) => !item.category || Number(this.entityId(item.category)) === Number(categoryId));
        return this.applicationMethods;
      }
      if (name === 'employeePositions') return this.employeePositions;
      if (name === 'directusUsers') return this.directusUsers;
      if (name === 'directusRoles') return this.directusRoles;
      return [];
    },

    adminOptionLabel(item) {
      return item?.name || item?.full_name || item?.email || [item?.first_name, item?.last_name].filter(Boolean).join(' ') || item?.id || '-';
    },

    adminDisplayValue(row, column) {
      const value = row?.[column.key];
      if (column.type === 'boolean') return value ? 'Да' : 'Нет';
      if (column.type === 'money') return this.formatMoney(value);
      if (column.type === 'relation') {
        const id = this.entityId(value);
        return this.adminOptionLabel(this.adminOptions(column.options, row).find((item) => String(item.id) === id)) || '-';
      }
      if (column.type === 'select') {
        return column.choices?.find((choice) => String(choice.value) === String(value))?.text || value || '-';
      }
      return value ?? '-';
    },

    adminFieldInputType(column) {
      if (['number', 'money'].includes(column.type)) return 'number';
      return 'text';
    },

    adminEmptyForm(config) {
      return Object.fromEntries(config.columns.map((column) => {
        if (column.type === 'boolean') return [column.key, true];
        if (['number', 'money'].includes(column.type)) return [column.key, ''];
        return [column.key, ''];
      }));
    },

    adminNormalizeForm(row) {
      const config = this.activeAdminConfig;
      return Object.fromEntries(config.columns.map((column) => {
        const value = row?.[column.key];
        if (column.type === 'relation') return [column.key, this.entityId(value)];
        if (column.type === 'boolean') return [column.key, value !== false];
        if (['number', 'money'].includes(column.type)) return [column.key, value ?? ''];
        return [column.key, value ?? ''];
      }));
    },

    adminPayload() {
      const config = this.activeAdminConfig;
      const payload = {};
      config.columns.forEach((column) => {
        if (column.readonly) return;
        let value = this.adminForm[column.key];
        if (column.type === 'relation') value = value ? value : null;
        if (['number', 'money'].includes(column.type)) value = value === '' || value === null ? null : Number(value);
        if (column.type === 'boolean') value = !!value;
        payload[column.key] = value;
      });
      return payload;
    },

    startAdminCreate() {
      if (!this.activeAdminConfig || this.activeAdminConfig.createDisabled) return;
      this.adminEditing = 'new';
      this.adminForm = this.adminEmptyForm(this.activeAdminConfig);
    },

    startAdminEdit(row) {
      this.adminEditing = row.id;
      this.adminForm = this.adminNormalizeForm(row);
    },

    cancelAdminEdit() {
      this.adminEditing = null;
      this.adminForm = {};
    },

    async saveAdminForm() {
      const config = this.activeAdminConfig;
      if (!config || this.adminSaving) return;
      const payload = this.adminPayload();

      const missing = config.columns.find((column) => column.required && !payload[column.key]);
      if (missing) {
        this.error = `Заполните поле "${missing.label}".`;
        return;
      }

      this.adminSaving = true;
      this.error = '';

      try {
        const isNew = this.adminEditing === 'new';
        const url = isNew ? config.endpoint : `${config.endpoint}/${this.adminEditing}`;
        await this.request(url, {
          method: isNew ? 'POST' : 'PATCH',
          body: JSON.stringify(payload),
        });
        this.cancelAdminEdit();
        await this.loadAdminData();
      } catch (error) {
        this.error = error.message;
      } finally {
        this.adminSaving = false;
      }
    },

    async archiveAdminRow(row) {
      const config = this.activeAdminConfig;
      if (!config || !row?.id) return;
      if (!config.columns.some((column) => column.key === 'is_active')) return;

      this.adminSaving = true;
      this.error = '';
      try {
        await this.request(`${config.endpoint}/${row.id}`, {
          method: 'PATCH',
          body: JSON.stringify({ is_active: false }),
        });
        await this.loadAdminData();
      } catch (error) {
        this.error = error.message;
      } finally {
        this.adminSaving = false;
      }
    },

    async loadAdminData() {
      await Promise.all([
        this.loadAdminReferenceLists(),
        ...adminDictionaryTabs.map((tab) => this.loadAdminRows(tab)),
      ]);
    },

    async loadAdminReferenceLists() {
      await Promise.all([
        this.loadContractors(),
        this.loadProductCategories(),
        this.loadProductSubcategories(),
        this.loadApplicationMethods(),
        this.loadEmployeePositions(),
        this.loadDirectusUsers(),
        this.loadDirectusRoles(),
      ]);
    },

    async loadAdminRows(tab) {
      const config = adminConfigs[tab];
      if (!config) return;
      try {
        const params = new URLSearchParams();
        params.set('fields', config.fields);
        params.set('sort', config.sort);
        params.set('limit', '-1');
        const payload = await this.request(`${config.endpoint}?${params.toString()}`);
        this.adminRows = {
          ...this.adminRows,
          [tab]: payload.data || [],
        };
      } catch (error) {
        this.adminRows = {
          ...this.adminRows,
          [tab]: [],
        };
        this.error = error.message;
      }
    },

    async loadEmployeePositions() {
      try {
        const payload = await this.request('/items/employee_positions?fields=id,name,sort,is_active&sort=sort,name&limit=-1');
        this.employeePositions = payload.data || [];
      } catch {
        this.employeePositions = [];
      }
    },

    async loadDirectusUsers() {
      try {
        const payload = await this.request('/users?fields=id,email,first_name,last_name,status,role&sort=email&limit=-1');
        this.directusUsers = payload.data || [];
      } catch {
        this.directusUsers = [];
      }
    },

    async loadDirectusRoles() {
      try {
        const payload = await this.request('/roles?fields=id,name&sort=name&limit=-1');
        this.directusRoles = payload.data || [];
      } catch {
        this.directusRoles = [];
      }
    },

    async loadRows() {
      this.loading = true;
      this.error = '';

      try {
        const params = new URLSearchParams();
        params.set('fields', this.costingFields().join(','));
        params.set('sort', '-date,order_number,product_name');
        params.set('limit', '-1');

        const payload = await this.request(`/items/contractor_costing?${params.toString()}`);
        this.rows = (payload.data || []).map((row) => ({
          ...row,
          contractor_1_cost: this.moneyInput(row.contractor_1_cost),
          contractor_2_cost: this.moneyInput(row.contractor_2_cost),
        }));
      } catch (error) {
        this.error = error.message;
      } finally {
        this.loading = false;
      }
    },

    costingFields() {
      if (this.canSeeCostingTotals) return fields;
      const adminOnly = new Set(['order', 'unit_cost', 'total_cost', 'profit_sum', 'margin_percent']);
      return fields.filter((field) => !adminOnly.has(field));
    },

    async loadContractors() {
      try {
        const payload = await this.request('/items/contractors?fields=id,name&sort=name&limit=-1');
        this.contractors = payload.data || [];
      } catch (error) {
        this.error = error.message;
      }
    },

    async loadProductionStatuses() {
      try {
        const payload = await this.request('/items/production_statuses?fields=id,name&sort=sort,name&limit=-1');
        this.productionStatuses = payload.data || [];
      } catch (error) {
        this.error = error.message;
      }
    },

    async loadOrderStatuses() {
      try {
        const payload = await this.request('/items/order_statuses?fields=id,name&sort=sort,name&limit=-1');
        this.orderStatuses = payload.data || [];
      } catch {
        this.orderStatuses = [];
      }
    },

    async loadWorkRows(collection) {
      try {
        const params = new URLSearchParams();
        params.set('fields', workFields.join(','));
        params.set('sort', 'deadline,date,order,product_name');
        params.set('limit', '-1');

        const payload = await this.request(`/items/${collection}?${params.toString()}`);
        const rows = payload.data || [];

        if (collection === 'production_work') this.productionRows = rows;
        if (collection === 'screen_printing_work') this.screenRows = rows;
      } catch (error) {
        this.error = error.message;
      }
    },

    async loadOfficeRows() {
      try {
        const params = new URLSearchParams();
        params.set('fields', officeFields.join(','));
        params.set('sort', 'order_number,product_name');
        params.set('limit', String(this.limit));

        const payload = await this.request(`/items/office_items_in_office?${params.toString()}`);
        this.officeRows = payload.data || [];
      } catch (error) {
        this.error = error.message;
      }
    },

    async loadFinanceRows() {
      try {
        const params = new URLSearchParams();
        params.set('fields', financeFields.join(','));
        params.set('sort', '-date,order_number');
        params.set('limit', '-1');

        const payload = await this.request(`/items/customer_reconciliation?${params.toString()}`);
        this.financeRows = payload.data || [];
      } catch (error) {
        this.error = error.message;
      }
    },

    async loadFinanceItemRows() {
      try {
        const params = new URLSearchParams();
        params.set('fields', financeItemFields.join(','));
        params.set('sort', '-date,order_number,product_name');
        params.set('limit', '-1');

        const payload = await this.request(`/items/customer_reconciliation_items?${params.toString()}`);
        this.financeItemRows = payload.data || [];
      } catch (error) {
        this.error = error.message;
        this.financeItemRows = [];
      }
    },

    async loadContractorRows() {
      try {
        const params = new URLSearchParams();
        params.set('fields', contractorFields.join(','));
        params.set('sort', 'name');
        params.set('limit', String(this.limit));

        const payload = await this.request(`/items/contractors?${params.toString()}`);
        this.contractorRows = payload.data || [];
      } catch (error) {
        this.error = error.message;
      }
    },

    async loadExpenseRows() {
      try {
        const params = new URLSearchParams();
        params.set('fields', expenseFields.join(','));
        params.set('sort', '-expense_date,-id');
        params.set('limit', String(this.limit));

        const payload = await this.request(`/items/business_expenses?${params.toString()}`);
        this.expenseRows = payload.data || [];
      } catch (error) {
        this.error = error.message;
        this.expenseRows = [];
      }
    },

    async loadSalaryRows() {
      try {
        const params = new URLSearchParams();
        params.set('fields', salaryFields.join(','));
        params.set('sort', 'employee_name');
        params.set('limit', String(this.limit));

        const payload = await this.request(`/items/employee_salary_summary?${params.toString()}`);
        this.salaryRows = payload.data || [];
      } catch (error) {
        this.error = error.message;
        this.salaryRows = [];
      }
    },

    async loadManagerFinanceSummary() {
      try {
        const params = new URLSearchParams();
        params.set('fields', managerFinanceFields.join(','));
        params.set('limit', '1');

        const payload = await this.request(`/items/manager_finance_summary?${params.toString()}`);
        this.managerFinanceSummary = payload.data?.[0] || null;
      } catch {
        this.managerFinanceSummary = null;
      }
    },

    async loadEmployees() {
      try {
        const payload = await this.request('/items/employees?fields=id,full_name,phone,position.name&filter[is_active][_neq]=false&sort=full_name&limit=-1');
        this.employees = payload.data || [];
      } catch {
        this.employees = [];
      }
    },

    async loadMyOrderRows() {
      try {
        if (!this.currentEmployeeId) {
          this.myOrderRows = [];
          return;
        }

        const params = new URLSearchParams();
        params.set('fields', orderSummaryFields.join(','));
        params.set('sort', 'deadline,-date,order_number');
        params.set('limit', String(this.limit));
        params.set('filter[manager_employee][_eq]', String(this.currentEmployeeId));

        const payload = await this.request(`/items/my_orders_in_work?${params.toString()}`);
        this.myOrderRows = payload.data || [];
      } catch {
        this.myOrderRows = [];
      }
    },

    async loadAllOrderRows() {
      try {
        const params = new URLSearchParams();
        params.set('fields', overviewFields.join(','));
        params.set('sort', 'deadline,-date,order_number');
        params.set('limit', String(this.limit));

        const payload = await this.request(`/items/orders_overview?${params.toString()}`);
        this.allOrderRows = payload.data || [];
      } catch {
        this.allOrderRows = [];
      }
    },

    async loadPaymentTypes() {
      try {
        const payload = await this.request('/items/payment_types?fields=id,name&filter[is_active][_eq]=true&sort=sort,name&limit=-1');
        this.paymentTypes = payload.data || [];
      } catch {
        this.paymentTypes = [];
      }
    },

    async loadCreateOrderDictionaries() {
      await Promise.all([
        this.loadCustomers(),
        this.loadCompanies(),
        this.loadProductCategories(),
        this.loadProductSubcategories(),
        this.loadApplicationMethods(),
        this.loadPaymentTypes(),
      ]);
    },

    async loadCustomers() {
      try {
        const payload = await this.request('/items/customers?fields=id,name,phone,email,vk_page_url,company.id,company.name,orders_total_sum,payments_total_in,balance&sort=name&limit=-1');
        this.customers = payload.data || [];
      } catch {
        this.customers = [];
      }
    },

    async loadCompanies() {
      try {
        const payload = await this.request('/items/customer_companies?fields=id,name,phone,email,orders_total_sum,payments_total_in,balance&sort=name&limit=-1');
        this.companies = payload.data || [];
      } catch {
        this.companies = [];
      }
    },

    async loadProductCategories() {
      try {
        const payload = await this.request('/items/product_categories?fields=id,name,detail_mode&filter[is_active][_eq]=true&sort=sort,name&limit=-1');
        this.productCategories = payload.data || [];
      } catch {
        this.productCategories = [];
      }
    },

    async loadProductSubcategories() {
      try {
        const payload = await this.request('/items/product_subcategories?fields=id,name,category&filter[is_active][_eq]=true&sort=sort,name&limit=-1');
        this.productSubcategories = payload.data || [];
      } catch {
        this.productSubcategories = [];
      }
    },

    async loadApplicationMethods() {
      try {
        const payload = await this.request('/items/product_application_methods?fields=id,name,category&filter[is_active][_eq]=true&sort=sort,name&limit=-1');
        this.applicationMethods = payload.data || [];
      } catch {
        this.applicationMethods = [];
      }
    },

    openNewOrderDialog() {
      if (!this.canCreateOrders) return;
      const date = this.todayInput();
      this.error = '';
      this.newOrderDialog = {
        saving: false,
        date,
        deadline: '',
        customer: '',
        customer_company: '',
        create_customer: false,
        create_company: false,
        new_customer_name: '',
        new_customer_phone: '',
        new_customer_email: '',
        new_company_name: '',
        new_company_phone: '',
        new_company_email: '',
        shipping_method: 'office_pickup',
        payment_on_receipt: false,
        payment_type: '',
        comment: '',
        shipping_comment: '',
        items: [this.newOrderItem('')],
      };
    },

    closeNewOrderDialog() {
      if (this.newOrderDialog?.saving) return;
      this.newOrderDialog = null;
    },

    newOrderItem(deadline = '') {
      return {
        product_name: '',
        quantity: '',
        price_per_unit: '',
        deadline,
        product_category: '',
        product_subcategory: '',
        application_method: '',
        technical_task_text: '',
        url: '',
      };
    },

    addNewOrderItem() {
      if (!this.newOrderDialog) return;
      this.newOrderDialog.items.push(this.newOrderItem(this.newOrderDialog.deadline || ''));
    },

    removeNewOrderItem(index) {
      if (!this.newOrderDialog || this.newOrderDialog.items.length <= 1) return;
      this.newOrderDialog.items.splice(index, 1);
    },

    syncNewOrderCustomer() {
      if (!this.newOrderDialog?.customer) return;
      const customer = this.customers.find((item) => Number(item.id) === Number(this.newOrderDialog.customer));
      const companyId = typeof customer?.company === 'object' ? customer.company?.id : customer?.company;
      if (companyId && !this.newOrderDialog.customer_company) {
        this.newOrderDialog.customer_company = String(companyId);
      }
    },

    toggleNewOrderCustomer() {
      if (!this.newOrderDialog) return;
      this.newOrderDialog.create_customer = !this.newOrderDialog.create_customer;
      if (this.newOrderDialog.create_customer) {
        this.newOrderDialog.customer = '';
      } else {
        this.newOrderDialog.new_customer_name = '';
        this.newOrderDialog.new_customer_phone = '';
        this.newOrderDialog.new_customer_email = '';
      }
    },

    toggleNewOrderCompany() {
      if (!this.newOrderDialog) return;
      this.newOrderDialog.create_company = !this.newOrderDialog.create_company;
      if (this.newOrderDialog.create_company) {
        this.newOrderDialog.customer_company = '';
      } else {
        this.newOrderDialog.new_company_name = '';
        this.newOrderDialog.new_company_phone = '';
        this.newOrderDialog.new_company_email = '';
      }
    },

    clearZeroInput(model, field) {
      if (!model || this.parseMoney(model[field]) !== 0) return;
      model[field] = '';
    },

    syncNewOrderDeadline() {
      if (!this.newOrderDialog?.deadline) return;
      this.newOrderDialog.items = this.newOrderDialog.items.map((item) => ({
        ...item,
        deadline: item.deadline || this.newOrderDialog.deadline,
      }));
    },

    clearNewOrderItemDetails(item) {
      item.product_subcategory = '';
      item.application_method = '';
    },

    filteredSubcategories(categoryId) {
      if (!categoryId) return [];
      return this.productSubcategories.filter((item) => Number(item.category) === Number(categoryId));
    },

    filteredApplicationMethods(categoryId) {
      if (!categoryId) return [];
      return this.applicationMethods.filter((item) => Number(item.category) === Number(categoryId));
    },

    async createOrderWithItems() {
      if (!this.newOrderDialog || this.newOrderDialog.saving) return;
      const form = this.newOrderDialog;
      const newCustomerName = String(form.new_customer_name || '').trim();
      const newCompanyName = String(form.new_company_name || '').trim();
      const items = form.items
        .map((item) => ({
          ...item,
          product_name: String(item.product_name || '').trim(),
          quantity: this.parseMoney(item.quantity),
          price_per_unit: this.parseMoney(item.price_per_unit),
        }))
        .filter((item) => item.product_name);

      if (!form.customer && !newCustomerName) {
        this.error = 'Выберите клиента для нового заказа.';
        return;
      }

      if (form.create_company && !newCompanyName) {
        this.error = 'Укажите название новой компании или выберите компанию из списка.';
        return;
      }

      if (!items.length) {
        this.error = 'Добавьте хотя бы одну позицию заказа.';
        return;
      }

      form.saving = true;
      this.error = '';

      try {
        let companyId = form.customer_company ? Number(form.customer_company) : null;
        if (!companyId && newCompanyName) {
          const companyBody = {
            name: newCompanyName,
            phone: String(form.new_company_phone || '').trim() || null,
            email: String(form.new_company_email || '').trim() || null,
          };
          if (this.currentEmployeeId) companyBody.manager = this.currentEmployeeId;

          const companyPayload = await this.request('/items/customer_companies', {
            method: 'POST',
            body: JSON.stringify(companyBody),
          });
          companyId = companyPayload?.data?.id;
          if (!companyId) throw new Error('Directus не вернул ID новой компании.');
        }

        let customerId = form.customer ? Number(form.customer) : null;
        if (!customerId) {
          const customerBody = {
            name: newCustomerName,
            phone: String(form.new_customer_phone || '').trim() || null,
            email: String(form.new_customer_email || '').trim() || null,
            company: companyId || null,
          };
          if (this.currentEmployeeId) customerBody.manager = this.currentEmployeeId;

          const customerPayload = await this.request('/items/customers', {
            method: 'POST',
            body: JSON.stringify(customerBody),
          });
          customerId = customerPayload?.data?.id;
          if (!customerId) throw new Error('Directus не вернул ID нового клиента.');
        }

        const orderBody = {
          date: form.date || this.todayInput(),
          deadline: form.deadline || null,
          customer: customerId,
          customer_company: companyId || null,
          order_status: 1,
          office_status: 'not_in_office',
          shipping_method: form.shipping_method || null,
          shipping_comment: form.shipping_comment || null,
          payment_on_receipt: !!form.payment_on_receipt,
          payment_type: form.payment_type ? Number(form.payment_type) : null,
          comment: form.comment || null,
        };
        if (this.currentEmployeeId) orderBody.manager_employee = this.currentEmployeeId;

        const orderPayload = await this.request('/items/orders', {
          method: 'POST',
          body: JSON.stringify(orderBody),
        });

        const orderId = orderPayload?.data?.id;
        if (!orderId) throw new Error('Directus не вернул ID нового заказа.');

        await Promise.all(items.map((item) => this.request('/items/orders_items', {
          method: 'POST',
          body: JSON.stringify({
            order: orderId,
            product_name: item.product_name,
            quantity: item.quantity,
            price_per_unit: item.price_per_unit,
            order_sum: item.quantity * item.price_per_unit,
            product_category: item.product_category ? Number(item.product_category) : null,
            product_subcategory: item.product_subcategory ? Number(item.product_subcategory) : null,
            application_method: item.application_method ? Number(item.application_method) : null,
            deadline: item.deadline || form.deadline || null,
            item_status: 'new',
            office_status: 'not_in_office',
            shipping_method: form.shipping_method || null,
            technical_task_text: item.technical_task_text || null,
            url: item.url || null,
          }),
        })));

        this.newOrderDialog = null;
        this.activeTab = this.availableTabs.some((tab) => tab.id === 'my_orders') ? 'my_orders' : 'all_orders';
        await this.loadAllowedData();
      } catch (error) {
        this.error = error.message;
      } finally {
        if (this.newOrderDialog) this.newOrderDialog.saving = false;
      }
    },

    async loadOfficeIssueRows() {
      try {
        const params = new URLSearchParams();
        params.set('fields', officeIssueFields.join(','));
        params.set('sort', 'deadline,order_number');
        params.set('limit', String(this.limit));

        const payload = await this.request(`/items/office_issue?${params.toString()}`);
        this.officeIssueRows = (payload.data || []).map((row) => ({
          ...row,
          add_payment: this.moneyInput(row.add_payment),
        }));
      } catch (error) {
        this.error = error.message;
        this.officeIssueRows = [];
      }
    },

    async loadOfficeArchiveRows() {
      try {
        const params = new URLSearchParams();
        params.set('fields', officeArchiveFields.join(','));
        params.set('sort', '-date,order_number');
        params.set('limit', String(this.limit));

        const payload = await this.request(`/items/office_issue_archive?${params.toString()}`);
        this.officeArchiveRows = (payload.data || []).map((row) => ({
          ...row,
          add_payment: this.moneyInput(row.add_payment),
        }));
      } catch (error) {
        this.error = error.message;
        this.officeArchiveRows = [];
      }
    },

    async loadOfficeArchiveItems() {
      try {
        const params = new URLSearchParams();
        params.set('fields', officeArchiveItemFields.join(','));
        params.set('sort', 'office_issue,product_name');
        params.set('limit', String(this.limit));

        const payload = await this.request(`/items/office_issue_archive_items?${params.toString()}`);
        this.officeArchiveItems = payload.data || [];
      } catch (error) {
        this.error = error.message;
        this.officeArchiveItems = [];
      }
    },

    async loadDeadlineRows() {
      const next = {};

      await Promise.all(deadlineBuckets.map(async (bucket) => {
        try {
          const params = new URLSearchParams();
          params.set('fields', overviewFields.join(','));
          params.set('sort', 'deadline,-date,order_number');
          params.set('limit', String(this.limit));

          const payload = await this.request(`/items/${bucket.collection}?${params.toString()}`);
          next[bucket.id] = payload.data || [];
        } catch {
          next[bucket.id] = [];
        }
      }));

      this.deadlineRows = next;
    },

    async saveField(row, field, value) {
      const key = `${row.id}:${field}`;
      this.saving = { ...this.saving, [key]: true };
      this.error = '';

      try {
        const normalized = field.includes('cost') ? this.parseMoney(value) : (value || null);
        await this.request(`/items/contractor_costing/${row.id}`, {
          method: 'PATCH',
          body: JSON.stringify({ [field]: normalized }),
        });

        await this.loadRows();
      } catch (error) {
        this.error = error.message;
        await this.loadRows();
      } finally {
        const next = { ...this.saving };
        delete next[key];
        this.saving = next;
      }
    },

    async saveWorkField(collection, row, field, value) {
      const key = `${collection}:${row.id}:${field}`;
      this.saving = { ...this.saving, [key]: true };
      this.error = '';

      try {
        await this.request(`/items/${collection}/${row.id}`, {
          method: 'PATCH',
          body: JSON.stringify({ [field]: value || null }),
        });

        await this.loadWorkRows(collection);
      } catch (error) {
        this.error = error.message;
        await this.loadWorkRows(collection);
      } finally {
        const next = { ...this.saving };
        delete next[key];
        this.saving = next;
      }
    },

    async saveOfficeField(row, value) {
      const key = `office_items_in_office:${row.id}:office_status`;
      this.saving = { ...this.saving, [key]: true };
      this.error = '';

      try {
        await this.request(`/items/office_items_in_office/${row.id}`, {
          method: 'PATCH',
          body: JSON.stringify({ office_status: value || null }),
        });

        await Promise.all([this.loadOfficeIssueRows(), this.loadOfficeRows(), this.loadOfficeArchiveRows(), this.loadOfficeArchiveItems()]);
      } catch (error) {
        this.error = error.message;
        await Promise.all([this.loadOfficeIssueRows(), this.loadOfficeRows()]);
      } finally {
        const next = { ...this.saving };
        delete next[key];
        this.saving = next;
      }
    },

    async saveOfficeIssueField(row, field, value) {
      const key = `office_issue:${row.id}:${field}`;
      this.saving = { ...this.saving, [key]: true };
      this.error = '';

      try {
        const normalized = ['add_payment'].includes(field) ? this.parseMoney(value) : (value || null);
        await this.request(`/items/office_issue/${row.id}`, {
          method: 'PATCH',
          body: JSON.stringify({ [field]: normalized }),
        });

        await Promise.all([this.loadOfficeIssueRows(), this.loadOfficeRows(), this.loadOfficeArchiveRows(), this.loadOfficeArchiveItems()]);
      } catch (error) {
        this.error = error.message;
        await Promise.all([this.loadOfficeIssueRows(), this.loadOfficeRows()]);
      } finally {
        const next = { ...this.saving };
        delete next[key];
        this.saving = next;
      }
    },

    async saveOrderField(row, field, value) {
      const orderId = this.entityId(this.orderId(row));
      if (!orderId) return;

      const key = `orders:${orderId}:${field}`;
      this.saving = { ...this.saving, [key]: true };
      this.error = '';

      try {
        const normalized = field === 'order_status'
          ? (value ? Number(value) : null)
          : (value || null);
        await this.request(`/items/orders/${orderId}`, {
          method: 'PATCH',
          body: JSON.stringify({ [field]: normalized }),
        });

        this.updateOrderCaches(orderId, { [field]: normalized });
        await this.loadAllowedData();
      } catch (error) {
        this.error = error.message;
        await this.loadAllowedData();
      } finally {
        const next = { ...this.saving };
        delete next[key];
        this.saving = next;
      }
    },

    async saveOrderItemField(row, field, value) {
      const itemId = this.entityId(row?.order_item) || row?.id;
      if (!itemId) return;

      const key = `orders_items:${itemId}:${field}`;
      this.saving = { ...this.saving, [key]: true };
      this.error = '';

      try {
        const normalized = field === 'production_status'
          ? (value ? Number(value) : null)
          : (value || null);
        await this.request(`/items/orders_items/${itemId}`, {
          method: 'PATCH',
          body: JSON.stringify({ [field]: normalized }),
        });

        this.updateOrderItemCaches(itemId, { [field]: normalized });
        await this.loadAllowedData();
      } catch (error) {
        this.error = error.message;
        await this.loadAllowedData();
      } finally {
        const next = { ...this.saving };
        delete next[key];
        this.saving = next;
      }
    },

    updateOrderCaches(orderId, patch) {
      const id = this.entityId(orderId);
      const groups = [
        this.myOrderRows,
        this.allOrderRows,
        ...Object.values(this.deadlineRows),
        this.officeIssueRows,
        this.officeArchiveRows,
        this.financeRows,
      ];

      groups.forEach((rows) => {
        (rows || []).forEach((item) => {
          if (this.entityId(this.orderId(item)) === id) Object.assign(item, patch);
        });
      });

      if (this.detail?.row && this.entityId(this.orderId(this.detail.row)) === id) {
        Object.assign(this.detail.row, patch);
      }
    },

    updateOrderItemCaches(itemId, patch) {
      const id = this.entityId(itemId);
      const groups = [
        this.rows,
        this.productionRows,
        this.screenRows,
        this.officeRows,
        this.officeArchiveItems,
        this.financeItemRows,
      ];

      groups.forEach((rows) => {
        (rows || []).forEach((item) => {
          const currentId = this.entityId(item?.order_item) || this.entityId(item?.id);
          if (currentId === id) Object.assign(item, patch);
        });
      });

      if (this.detail?.row) {
        const detailItemId = this.entityId(this.detail.row?.order_item) || this.entityId(this.detail.row?.id);
        if (detailItemId === id) Object.assign(this.detail.row, patch);
      }
    },

    rowKey(type, row) {
      return `${type}:${row.id}`;
    },

    isSelected(type, row) {
      return !!this.selectedRows[this.rowKey(type, row)];
    },

    toggleSelected(type, row, checked) {
      const next = { ...this.selectedRows };
      if (checked) next[this.rowKey(type, row)] = { type, row };
      else delete next[this.rowKey(type, row)];
      this.selectedRows = next;
    },

    selectedFor(type) {
      return Object.values(this.selectedRows).filter((item) => item.type === type);
    },

    clearSelection() {
      this.selectedRows = {};
    },

    async bulkSetProductionStatus(collection, type, value) {
      const selected = this.selectedFor(type);
      if (!selected.length || !value) return;
      this.error = '';

      try {
        await Promise.all(selected.map((item) => this.request(`/items/${collection}/${item.row.id}`, {
          method: 'PATCH',
          body: JSON.stringify({ production_status: value }),
        })));
        this.clearSelection();
        await this.loadWorkRows(collection);
      } catch (error) {
        this.error = error.message;
        await this.loadWorkRows(collection);
      }
    },

    async bulkSetOfficeStatus(value) {
      const selected = this.selectedFor('office');
      if (!selected.length || !value) return;
      this.error = '';

      try {
        await Promise.all(selected.map((item) => this.request(`/items/office_items_in_office/${item.row.id}`, {
          method: 'PATCH',
          body: JSON.stringify({ office_status: value }),
        })));
        this.clearSelection();
        await this.loadOfficeRows();
      } catch (error) {
        this.error = error.message;
        await this.loadOfficeRows();
      }
    },

    exportCurrentTable() {
      if (this.activeTab === 'finance') {
        this.exportFinanceReconciliationExcel();
        return;
      }

      const rows = this.exportRows();
      if (!rows.length) return;

      const headers = Object.keys(rows[0]);
      const csv = [
        headers.join(';'),
        ...rows.map((row) => headers.map((header) => this.csvCell(row[header])).join(';')),
      ].join('\n');

      const blob = new Blob([`\uFEFF${csv}`], { type: 'text/csv;charset=utf-8' });
      const link = document.createElement('a');
      link.href = URL.createObjectURL(blob);
      link.download = `symbolika-${this.activeTab}-${new Date().toISOString().slice(0, 10)}.csv`;
      link.click();
      URL.revokeObjectURL(link.href);
    },

    allocatePaymentsToItems(rows) {
      const groups = new Map();

      (rows || []).forEach((row) => {
        const key = this.entityId(row.order_link) || row.order_number || `order-${row.id}`;
        if (!groups.has(key)) groups.set(key, []);
        groups.get(key).push(row);
      });

      const allocated = [];

      groups.forEach((items) => {
        let remainingPaid = this.parseMoney(items[0]?.paid_amount);

        items.forEach((row, index) => {
          const itemSum = this.parseMoney(row.item_sum);
          const paidForItem = Math.min(Math.max(remainingPaid, 0), itemSum);
          remainingPaid -= paidForItem;
          const overpaymentForItem = index === items.length - 1 ? Math.max(remainingPaid, 0) : 0;

          allocated.push({
            ...row,
            paid_amount: paidForItem,
            payment_due: Math.max(itemSum - paidForItem, 0),
            overpayment: overpaymentForItem,
            item_paid_amount: paidForItem,
            item_payment_due: Math.max(itemSum - paidForItem, 0),
            item_overpayment: overpaymentForItem,
          });
        });
      });

      return allocated;
    },

    financeExportMeta() {
      const selectedCustomer = this.customers.find((item) => String(item.id) === String(this.financeCustomerFilter));
      const selectedCompany = this.companies.find((item) => String(item.id) === String(this.financeCompanyFilter));
      const firstRow = this.visibleFinanceRows[0] || this.visibleFinanceItemRows[0] || {};

      return {
        date: this.formatDate(new Date()),
        customer: selectedCustomer?.name || (!this.financeCompanyFilter ? firstRow.customer_name : '') || 'Все клиенты',
        company: selectedCompany?.name || firstRow.customer_company_name || 'Все компании',
        manager: this.currentRoleName === 'Менеджер' ? (this.managerFinanceStats.employee_name || firstRow.manager_name || '-') : (firstRow.manager_name || 'Все менеджеры'),
        period: `${this.financeDateFrom ? this.formatDate(this.financeDateFrom) : 'с начала'} - ${this.financeDateTo ? this.formatDate(this.financeDateTo) : 'по сегодня'}`,
      };
    },

    exportFinanceReconciliationExcel() {
      const rows = this.allocatePaymentsToItems(this.visibleFinanceItemRows);
      if (!rows.length) return;

      const meta = this.financeExportMeta();
      const totals = rows.reduce((summary, row) => {
        summary.item_sum += this.parseMoney(row.item_sum);
        summary.paid += this.parseMoney(row.item_paid_amount);
        summary.due += this.parseMoney(row.item_payment_due);
        summary.overpayment += this.parseMoney(row.item_overpayment);
        return summary;
      }, { item_sum: 0, paid: 0, due: 0, overpayment: 0 });

      const tableRows = rows.map((row) => `
        <tr>
          <td>${this.escapeHtml(row.order_number)}</td>
          <td>${this.escapeHtml(this.formatDate(row.date))}</td>
          <td>${this.escapeHtml(this.formatDate(row.deadline))}</td>
          <td>${this.escapeHtml(row.counterparty_name || row.customer_name || '')}</td>
          <td>${this.escapeHtml(row.customer_company_name || '')}</td>
          <td>${this.escapeHtml(row.product_name || '')}</td>
          <td class="num">${this.escapeHtml(this.formatQuantity(row.quantity))}</td>
          <td class="num">${this.escapeHtml(this.formatMoney(row.price_per_unit))}</td>
          <td class="num">${this.escapeHtml(this.formatMoney(row.item_sum))}</td>
          <td class="num">${this.escapeHtml(this.formatMoney(row.item_paid_amount))}</td>
          <td class="num">${this.escapeHtml(this.formatMoney(row.item_payment_due))}</td>
          <td>${this.escapeHtml(row.order_status_name || '')}</td>
        </tr>
      `).join('');

      const html = `<!doctype html>
        <html>
          <head>
            <meta charset="utf-8" />
            <style>
              body { font-family: Arial, sans-serif; color: #111827; }
              h1 { margin: 0 0 8px; font-size: 22px; }
              .meta { margin: 0 0 14px; border-collapse: collapse; }
              .meta td { padding: 3px 12px 3px 0; font-size: 12px; }
              .meta .label { color: #6b7280; font-weight: 700; }
              table.data { width: 100%; border-collapse: collapse; }
              table.data th { background: #f97316; color: #111827; text-align: left; font-weight: 700; }
              table.data th, table.data td { border: 1px solid #d1d5db; padding: 6px 8px; font-size: 12px; vertical-align: top; }
              table.data tr:nth-child(even) td { background: #f9fafb; }
              .num { text-align: right; mso-number-format: "\\#\\ ##0\\,00"; }
              .total td { background: #111827 !important; color: #fff; font-weight: 700; }
            </style>
          </head>
          <body>
            <h1>Сверка по заказам и позициям</h1>
            <table class="meta">
              <tr><td class="label">Дата сверки</td><td>${this.escapeHtml(meta.date)}</td></tr>
              <tr><td class="label">Период заказов</td><td>${this.escapeHtml(meta.period)}</td></tr>
              <tr><td class="label">Менеджер</td><td>${this.escapeHtml(meta.manager)}</td></tr>
              <tr><td class="label">Клиент</td><td>${this.escapeHtml(meta.customer)}</td></tr>
              <tr><td class="label">Компания</td><td>${this.escapeHtml(meta.company)}</td></tr>
            </table>
            <table class="data">
              <thead>
                <tr>
                  <th>Заказ</th>
                  <th>Дата</th>
                  <th>Срок</th>
                  <th>Заказчик</th>
                  <th>Компания</th>
                  <th>Позиция</th>
                  <th>Кол-во</th>
                  <th>Цена</th>
                  <th>Сумма позиции</th>
                  <th>Оплачено</th>
                  <th>Остаток</th>
                  <th>Статус</th>
                </tr>
              </thead>
              <tbody>
                ${tableRows}
                <tr class="total">
                  <td colspan="8">Итого</td>
                  <td class="num">${this.escapeHtml(this.formatMoney(totals.item_sum))}</td>
                  <td class="num">${this.escapeHtml(this.formatMoney(totals.paid))}</td>
                  <td class="num">${this.escapeHtml(this.formatMoney(totals.due))}</td>
                  <td>${totals.overpayment > 0 ? `Переплата ${this.escapeHtml(this.formatMoney(totals.overpayment))}` : ''}</td>
                </tr>
              </tbody>
            </table>
          </body>
        </html>`;

      const blob = new Blob([html], { type: 'application/vnd.ms-excel;charset=utf-8' });
      const link = document.createElement('a');
      const nameParts = ['sverka', meta.customer, meta.company, new Date().toISOString().slice(0, 10)]
        .filter(Boolean)
        .map((item) => String(item).replace(/[\\/:*?"<>|]+/g, '-').replace(/\s+/g, '-'));
      link.href = URL.createObjectURL(blob);
      link.download = `${nameParts.join('-')}.xls`;
      link.click();
      URL.revokeObjectURL(link.href);
    },

    exportRows() {
      if (this.activeTab === 'queue') {
        return this.queueRows.map((row) => ({
          "Раздел": row.section,
          "Причина": row.reason,
          "Заказ": row.order_number,
          "Клиент": row.customer_name,
          "Компания": row.customer_company_name,
          "Позиция": row.product_name,
          "Количество": row.quantity,
          "Срок": this.formatDate(row.deadline),
        }));
      }

      if (this.activeTab === 'problems') {
        return this.problemRows.map((row) => ({
          "Раздел": row.section,
          "Причина": row.reason,
          "Заказ": row.order_number,
          "Клиент": row.customer_name,
          "Компания": row.customer_company_name,
          "Позиция": row.product_name,
          "Количество": row.quantity,
          "Срок": this.formatDate(row.deadline),
        }));
      }

      if (this.activeTab === 'search') {
        return this.globalSearchRows.map((row) => ({
          "Раздел": row.section,
          "Статус": row.reason,
          "Заказ": row.order_number,
          "Клиент": row.customer_name,
          "Компания": row.customer_company_name,
          "Позиция": row.product_name,
          "Количество": row.quantity,
          "Срок": this.formatDate(row.deadline),
        }));
      }

      if (this.activeTab === 'my_orders') {
        return this.visibleMyOrderRows.map((row) => ({
          "Заказ": row.order_number,
          "Дата": this.formatDate(row.date),
          "Срок": this.formatDate(row.deadline),
          "Клиент": row.customer_display,
          "Менеджер": row.manager_name,
          "Статус": row.order_status_name,
          "Офис": this.officeStatusName(row.office_status),
          "Сумма": this.formatMoney(row.order_sum),
          "Оплачено": this.formatMoney(row.paid_amount),
          "Остаток": this.formatMoney(row.payment_due),
        }));
      }

      if (this.activeTab === 'all_orders') {
        return this.visibleAllOrderRows.map((row) => ({
          "Заказ": row.order_number,
          "Дата": this.formatDate(row.date),
          "Срок": this.formatDate(row.deadline),
          "Клиент": row.customer_display,
          "Менеджер": row.manager_name,
          "Отгрузка": row.shipping_method_name,
          "Сумма": this.formatMoney(row.order_sum),
          "Оплачено": this.formatMoney(row.paid_amount),
          "Остаток": this.formatMoney(row.payment_due),
        }));
      }

      if (this.activeTab === 'deadlines') {
        return this.visibleDeadlineRows.map((row) => ({
          "Заказ": row.order_number,
          "Дата": this.formatDate(row.date),
          "Срок": this.formatDate(row.deadline),
          "Клиент": row.customer_display,
          "Менеджер": row.manager_name,
          "Статус": row.order_status_name,
          "Офис": this.officeStatusName(row.office_status),
          "Сумма": this.formatMoney(row.order_sum),
          "Оплачено": this.formatMoney(row.paid_amount),
          "Остаток": this.formatMoney(row.payment_due),
        }));
      }

      if (this.activeTab === 'costing') {
        return this.visibleRows.map((row) => ({
          "Заказ": row.order_number,
          "Дата": this.formatDate(row.date),
          "Клиент": this.relatedName(row.customer),
          "Позиция": row.product_name,
          "Количество": row.quantity,
          "Сумма": this.formatMoney(row.order_sum),
          "Подрядчик1": this.relatedName(row.contractor_1),
          "Себестоимость1": row.contractor_1_cost,
          "Подрядчик2": this.relatedName(row.contractor_2),
          "Себестоимость2": row.contractor_2_cost,
          "Прибыль": this.formatMoney(row.profit_sum),
          "Маржа": `${this.formatMoney(row.margin_percent)}%`,
        }));
      }

      if (this.activeTab === 'payroll') {
        return [
          ...this.visibleSalaryRows.map((row) => ({
            "Тип": 'Расчет ЗП',
            "Сотрудник": row.employee_name,
            "Должность": row.position_name,
            "СуммаЗаказов": this.formatMoney(row.orders_sum),
            "Оплачено": this.formatMoney(row.paid_orders_sum),
            "НеОплачено": this.formatMoney(row.unpaid_orders_sum),
            "Оклад": this.formatMoney(row.salary_fixed),
            "Процент": `${this.formatMoney(row.order_percent)}%`,
            "Проценты": this.formatMoney(row.commission_accrued),
            "Начислено": this.formatMoney(row.salary_accrued),
            "Выплачено": this.formatMoney(row.salary_paid),
            "Авансы": this.formatMoney(row.advances_paid),
            "Долг": this.formatMoney(row.salary_debt),
          })),
          ...this.visiblePayrollExpenseRows.map((row) => ({
            "Тип": this.expenseTypeName(row.expense_type),
            "Дата": this.formatDate(row.expense_date),
            "Сумма": this.formatMoney(row.amount),
            "Сотрудник": this.relatedName(row.employee, 'full_name'),
            "ТипОплаты": this.relatedName(row.payment_type),
            "Комментарий": row.comment,
          })),
        ];
      }

      if (this.activeTab === 'expenses') {
        return [
          ...this.visibleExpenseRows.map((row) => ({
            "Тип": 'Расход',
            "Дата": this.formatDate(row.expense_date),
            "Категория": this.expenseTypeName(row.expense_type),
            "Сумма": this.formatMoney(row.amount),
            "ТипОплаты": this.relatedName(row.payment_type),
            "Комментарий": row.comment,
          })),
        ];
      }

      if (this.activeTab === 'clients') {
        return this.visibleCustomerDirectoryRows.map((row) => ({
          "Клиент": row.name,
          "Компания": this.relatedName(row.company) || 'Лично',
          "Телефон": row.phone,
          Email: row.email,
          VK: row.vk_page_url,
          "Менеджер": this.customerManagerName(row),
          "Заказов": row.orders_count,
          "СуммаЗаказов": this.formatMoney(row.orders_total_sum),
          "Оплачено": this.formatMoney(row.payments_total_in),
          "Баланс": this.formatMoney(row.balance),
        }));
      }

      if (this.activeTab === 'companies') {
        return this.visibleCompanyDirectoryRows.map((row) => ({
          "Компания": row.name,
          "Телефон": row.phone,
          Email: row.email,
          "Клиентов": row.customers_count,
          "Клиенты": row.customers.map((customer) => customer.name).join(', '),
          "Заказов": row.orders_count,
          "СуммаЗаказов": this.formatMoney(row.orders_total_sum),
          "Оплачено": this.formatMoney(row.payments_total_in),
          "Баланс": this.formatMoney(row.balance),
        }));
      }

      if (this.activeTab === 'finance') {
        if (this.financeLevel === 'items') {
          return this.visibleFinanceItemRowsAllocated.map((row) => ({
            "Заказ": row.order_number,
            "Дата": this.formatDate(row.date),
            "Срок": this.formatDate(row.deadline),
            "Контрагент": row.counterparty_name,
            "Клиент": row.customer_name,
            "Компания": row.customer_company_name,
            "Менеджер": row.manager_name,
            "Статус": row.order_status_name,
            "Позиция": row.product_name,
            "Количество": row.quantity,
            "Цена": this.formatMoney(row.price_per_unit),
            "СуммаПозиции": this.formatMoney(row.item_sum),
            "СуммаЗаказа": this.formatMoney(row.order_sum),
            "ОплаченоПоЗаказу": this.formatMoney(row.paid_amount),
            "ОстатокПоЗаказу": this.formatMoney(row.payment_due),
            "Переплата": this.formatMoney(row.overpayment),
            "Итог": row.reconciliation_result,
          }));
        }

        return this.visibleFinanceRows.map((row) => ({
          "Заказ": row.order_number,
          "Дата": this.formatDate(row.date),
          "Срок": this.formatDate(row.deadline),
          "Контрагент": row.counterparty_name,
          "Клиент": row.customer_name,
          "Компания": row.customer_company_name,
          "Менеджер": row.manager_name,
          "Статус": row.order_status_name,
          "Сумма": this.formatMoney(row.order_sum),
          "Оплачено": this.formatMoney(row.paid_amount),
          "Остаток": this.formatMoney(row.payment_due),
          "Переплата": this.formatMoney(row.overpayment),
          "Итог": row.reconciliation_result,
        }));
      }

      if (this.activeTab === 'contractors') {
        return this.visibleContractorRows.map((row) => ({
          "Контрагент": row.name,
          "Контакт": row.contact_name,
          "Телефон": row.phone,
          Email: row.email,
          "Работ": this.formatMoney(row.items_total_cost),
          "Оплачено": this.formatMoney(row.payments_total_out),
          "Баланс": this.formatMoney(row.balance),
          "МыДолжны": this.formatMoney(row.debt_to_contractor),
          "НамДолжны": this.formatMoney(row.contractor_debt_to_us),
          "СвоеПредставление": row.has_own_view ? 'Да' : 'Нет',
        }));
      }

      if (['production', 'screen'].includes(this.activeTab)) {
        const rows = this.activeTab === 'production' ? this.visibleProductionRows : this.visibleScreenRows;
        return rows.map((row) => ({
          "Дата": this.formatDate(row.date),
          "Срок": this.formatDate(row.deadline),
          "Заказ": this.orderNumber(row),
          "Клиент": this.relatedName(row.customer),
          "Позиция": row.product_name,
          "Количество": row.quantity,
          "Статус": this.statusName(row.production_status),
          "Комментарий": row.production_comment,
        }));
      }

      if (this.activeTab === 'office') {
        return this.visibleOfficeIssueRows.map((row) => ({
          "Раздел": officeBuckets.find((bucket) => bucket.id === this.officeBucket)?.title,
          "Заказ": row.order_number,
          "Клиент": row.customer_name,
          "Телефон": row.customer_phone,
          "Компания": row.customer_company_name,
          "Менеджер": row.manager_name,
          "СтатусОфиса": this.officeStatusName(row.office_status),
          "Сумма": this.formatMoney(row.order_sum),
          "Оплачено": this.formatMoney(row.paid_amount),
          "Остаток": this.formatMoney(row.office_payment_due ?? row.payment_due),
        }));
      }

      return this.visibleOfficeRows.map((row) => ({
        "Заказ": row.order_number,
        "Клиент": row.customer_name,
        "Компания": row.customer_company_name,
        "Менеджер": this.relatedName(row.manager_employee, 'full_name'),
        "Позиция": row.product_name,
        "Количество": row.quantity,
        "Статус": this.officeStatusName(row.office_status),
      }));
    },

    csvCell(value) {
      return `"${String(value ?? '').replace(/"/g, '""')}"`;
    },

    escapeHtml(value) {
      return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
    },

    relatedName(value, field = 'name') {
      if (!value) return '';
      if (typeof value === 'object') return value[field] || value.name || value.id || '';
      return '';
    },

    contractorId(value) {
      if (!value) return '';
      if (typeof value === 'object') return value.id || '';
      return value;
    },

    formatDate(value) {
      if (!value) return '-';
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return '-';
      return new Intl.DateTimeFormat('ru-RU', {
        day: '2-digit',
        month: '2-digit',
        year: '2-digit',
      }).format(date);
    },

    todayInput() {
      const date = new Date();
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const day = String(date.getDate()).padStart(2, '0');
      return `${year}-${month}-${day}`;
    },

    statusName(value) {
      return this.relatedName(value);
    },

    normalizeStatus(value) {
      return String(value || '').trim().toLowerCase();
    },

    statusBadgeClass(value) {
      const status = this.normalizeStatus(value);
      if (status.includes('доработ')) return 'symbolika-costing-pill-danger';
      if (status.includes('отмен')) return 'symbolika-costing-pill-muted';
      if (status.includes('достав') || status.includes('выдан')) return 'symbolika-costing-pill-green';
      if (status.includes('готов')) return 'symbolika-costing-pill-blue';
      if (status.includes('работ')) return 'symbolika-costing-pill-orange';
      if (status.includes('соглас')) return 'symbolika-costing-pill-purple';
      if (status.includes('нов')) return 'symbolika-costing-pill-blue';
      return 'symbolika-costing-pill-muted';
    },

    statusToneClass(value) {
      const badge = this.statusBadgeClass(this.statusName(value) || value);
      return badge.replace('symbolika-costing-pill-', 'symbolika-costing-select-');
    },

    officeBadgeClass(value) {
      if (value === 'issued') return 'symbolika-costing-pill-green';
      if (value === 'in_office') return 'symbolika-costing-pill-orange';
      return 'symbolika-costing-pill-muted';
    },

    officeSelectClass(value) {
      if (value === 'issued') return 'symbolika-costing-select-green';
      if (value === 'in_office') return 'symbolika-costing-select-orange';
      return 'symbolika-costing-select-muted';
    },

    deadlineClass(value) {
      if (this.isOverdue(value)) return 'symbolika-costing-date-danger';
      if (this.isToday(value)) return 'symbolika-costing-date-hot';
      return 'symbolika-costing-date-normal';
    },

    deadlineIcon(value) {
      if (this.isOverdue(value) || this.isToday(value)) return 'local_fire_department';
      return 'event';
    },

    paymentBadgeClass(value) {
      return this.parseMoney(value) > 0 ? 'symbolika-costing-pill-danger' : 'symbolika-costing-pill-green';
    },

    balanceBadgeClass(value) {
      const balance = this.parseMoney(value);
      if (balance < 0) return 'symbolika-costing-pill-danger';
      if (balance > 0) return 'symbolika-costing-pill-orange';
      return 'symbolika-costing-pill-green';
    },

    clientBalance(row) {
      return this.parseMoney(row?.overpayment) - this.parseMoney(row?.payment_due);
    },

    customerManagerName(row) {
      const order = row?.orders?.find((item) => item.manager_name);
      return order?.manager_name || '-';
    },

    rowStateClass(row) {
      return {
        'symbolika-costing-row-overdue': this.isOverdue(row?.deadline),
        'symbolika-costing-row-today': this.isToday(row?.deadline),
        'symbolika-costing-row-unpaid': this.parseMoney(row?.payment_due ?? row?.office_payment_due) > 0,
      };
    },

    officeStatusName(value) {
      return officeStatusChoices.find((choice) => choice.value === value)?.text || 'Не выбран';
    },

    tabIcon(tabId) {
      return {
        dashboard: 'dashboard',
        queue: 'playlist_add_check',
        problems: 'priority_high',
        search: 'search',
        all_orders: 'inventory',
        deadlines: 'event_upcoming',
        my_orders: 'assignment_ind',
        production: 'precision_manufacturing',
        screen: 'format_paint',
        costing: 'price_check',
        office: 'storefront',
        finance: 'receipt_long',
        payroll: 'payments',
        expenses: 'account_balance_wallet',
        contractors: 'groups',
      }[tabId] || 'table';
    },

    expenseTypeName(value) {
      return expenseTypes.find((choice) => choice.value === value)?.text || 'Прочие расходы';
    },

    formatMoney(value) {
      const number = Number(String(value ?? '').replace(',', '.'));
      if (!Number.isFinite(number)) return '0,00';
      return new Intl.NumberFormat('ru-RU', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      }).format(number);
    },

    pluralRu(count, one, few, many) {
      const value = Math.abs(Number(count)) % 100;
      const last = value % 10;
      if (value > 10 && value < 20) return many;
      if (last > 1 && last < 5) return few;
      if (last === 1) return one;
      return many;
    },

    moneyInput(value) {
      const number = Number(String(value ?? '').replace(',', '.'));
      if (!Number.isFinite(number)) return '';
      return String(Math.round(number * 100) / 100);
    },

    parseMoney(value) {
      const number = Number(String(value ?? '').replace(/\s/g, '').replace(',', '.'));
      return Number.isFinite(number) ? number : 0;
    },

    orderUrl(row) {
      return '#';
    },

    entityUrl(collection, id) {
      const entityId = this.entityId(id);
      return entityId ? '#' : '';
    },

    resolveCustomer(row) {
      const context = this.detailOrderContext(row);
      const id = this.entityId(row?.customer || context?.customer);
      if (id) {
        const byId = this.customers.find((item) => String(item.id) === id);
        if (byId) return byId;
      }

      const name = row?.customer_name || this.relatedName(row?.customer)
        || context?.customer_name || this.relatedName(context?.customer)
        || row?.customer_display || row?.counterparty_name
        || context?.customer_display || context?.counterparty_name;
      if (!name || name === '-') return null;
      return this.customers.find((item) => item.name === name) || { id: id || '', name };
    },

    resolveCompany(row) {
      const context = this.detailOrderContext(row);
      const id = this.entityId(row?.customer_company || context?.customer_company);
      if (id) {
        const byId = this.companies.find((item) => String(item.id) === id);
        if (byId) return byId;
      }

      const name = row?.customer_company_name || this.relatedName(row?.customer_company)
        || context?.customer_company_name || this.relatedName(context?.customer_company);
      if (!name || name === '-') return null;
      return this.companies.find((item) => item.name === name) || { id: id || '', name };
    },

    resolveManager(row) {
      const context = this.detailOrderContext(row);
      const id = this.entityId(row?.manager_employee || context?.manager_employee);
      if (id) {
        const byId = this.employees.find((item) => String(item.id) === id);
        if (byId) return byId;
      }

      const name = row?.manager_name || this.relatedName(row?.manager_employee, 'full_name')
        || context?.manager_name || this.relatedName(context?.manager_employee, 'full_name');
      if (!name || name === '-') return null;
      return this.employees.find((item) => item.full_name === name) || { id: id || '', full_name: name };
    },

    entityDetailTitle() {
      if (!this.entityDetail) return '';
      if (this.entityDetail.type === 'manager') return this.entityDetail.entity.full_name || 'Менеджер';
      return this.entityDetail.entity.name || 'Карточка';
    },

    entityDetailSubtitle() {
      if (!this.entityDetail) return '';
      if (this.entityDetail.type === 'manager') return 'Карточка менеджера';
      if (this.entityDetail.type === 'company') return 'Карточка компании';
      return 'Карточка клиента';
    },

    entityDetailUrl() {
      return '';
    },

    entityDetailFields() {
      if (!this.entityDetail) return [];
      const entity = this.entityDetail.entity;

      if (this.entityDetail.type === 'manager') {
        return [
          { label: 'ФИО', value: entity.full_name || '-' },
          { label: 'Должность', value: this.relatedName(entity.position) || '-' },
          { label: 'Телефон', value: entity.phone || '-' },
        ];
      }

      const fields = [
        { label: this.entityDetail.type === 'company' ? 'Компания' : 'Имя клиента', value: entity.name || '-' },
        { label: 'Телефон', value: entity.phone || '-' },
        { label: 'Email', value: entity.email || '-' },
      ];

      if (this.entityDetail.type === 'customer') {
        fields.push(
          { label: 'Компания', value: this.relatedName(entity.company) || '-' },
          { label: 'ВК', value: entity.vk_page_url || '-' },
        );
      }

      fields.push(
        { label: 'Сумма заказов', value: this.formatMoney(entity.orders_total_sum) },
        { label: 'Оплачено', value: this.formatMoney(entity.payments_total_in) },
        { label: 'Баланс', value: this.formatMoney(entity.balance) },
      );

      return fields;
    },

    customerUrl(row) {
      const customer = this.resolveCustomer(row);
      return customer?.id ? this.entityUrl('customers', customer.id) : '';
    },

    companyUrl(row) {
      const company = this.resolveCompany(row);
      return company?.id ? this.entityUrl('customer_companies', company.id) : '';
    },

    managerUrl(row) {
      const manager = this.resolveManager(row);
      return manager?.id ? this.entityUrl('employees', manager.id) : '';
    },

    orderId(row) {
      if (row?.order_link) return row.order_link;
      if (row?.order_number && !row?.product_name && row?.id) return row.id;
      if (!row?.order) return '';
      if (typeof row.order === 'object') return row.order.id || '';
      return row.order;
    },

    dateInput(value) {
      if (!value) return '';
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return '';
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const day = String(date.getDate()).padStart(2, '0');
      return `${year}-${month}-${day}`;
    },

    itemStatusName(value) {
      return itemStatusChoices.find((choice) => choice.value === value)?.text || value || '-';
    },

    orderNumber(row) {
      if (row?.order_number) return row.order_number;
      if (typeof row?.order === 'object') return row.order.order_number || `#${row.order.id}`;
      return row?.order ? `#${row.order}` : '-';
    },

    detailIsOrder(row) {
      return !row?.product_name && !row?.quantity;
    },

    detailOrderContext(row) {
      const orderId = this.entityId(this.orderId(row));
      const orderNumber = this.orderNumber(row);
      const sources = [
        ...this.myOrderRows,
        ...this.allOrderRows,
        ...Object.values(this.deadlineRows).flat(),
        ...this.officeIssueRows,
        ...this.financeRows,
      ];

      return sources.find((item) => {
        const itemOrderId = this.entityId(this.orderId(item));
        const matchesOrderId = orderId && itemOrderId && itemOrderId === orderId;
        const matchesNumber = orderNumber !== '-' && item.order_number === orderNumber;
        return matchesOrderId || matchesNumber;
      }) || row;
    },

    detailCustomerName(row) {
      const context = this.detailOrderContext(row);
      const customer = this.resolveCustomer(row);
      return customer?.name || row?.customer_name || this.relatedName(row?.customer)
        || context?.customer_name || this.relatedName(context?.customer)
        || row?.customer_display || row?.counterparty_name
        || context?.customer_display || context?.counterparty_name || '-';
    },

    detailCompanyName(row) {
      const context = this.detailOrderContext(row);
      const company = this.resolveCompany(row);
      return company?.name || row?.customer_company_name || this.relatedName(row?.customer_company)
        || context?.customer_company_name || this.relatedName(context?.customer_company) || '-';
    },

    detailManagerName(row) {
      const context = this.detailOrderContext(row);
      return row?.manager_name || this.relatedName(row?.manager_employee, 'full_name')
        || context?.manager_name || this.relatedName(context?.manager_employee, 'full_name') || '-';
    },

    detailOrderStatus(row) {
      const context = this.detailOrderContext(row);
      return row?.order_status_name || this.statusName(row?.order_status)
        || context?.order_status_name || this.statusName(context?.order_status) || '-';
    },

    detailOfficeStatus(row) {
      const context = this.detailOrderContext(row);
      return row?.office_status || context?.office_status || '';
    },

    detailPositions(row) {
      const orderId = this.entityId(this.orderId(row));
      const orderNumber = this.orderNumber(row);
      const sources = [
        ...this.rows,
        ...this.productionRows,
        ...this.screenRows,
        ...this.officeRows,
        ...this.financeItemRows,
      ];
      const positions = new Map();

      sources.forEach((item) => {
        const itemOrderId = this.entityId(this.orderId(item));
        const matchesOrderId = orderId && itemOrderId && itemOrderId === orderId;
        const matchesNumber = orderNumber !== '-' && item.order_number === orderNumber;
        if (!matchesOrderId && !matchesNumber) return;

        const key = `${String(item.product_name || '').trim().toLowerCase()}:${this.formatQuantity(item.quantity)}`;
        const current = positions.get(key);
        positions.set(key, {
          ...item,
          ...current,
          deadline: current?.deadline || item.deadline,
          item_status: current?.item_status || item.item_status,
          production_status: current?.production_status || item.production_status,
          production_status_name: current?.production_status_name || item.production_status_name,
          order_status_name: current?.order_status_name || item.order_status_name,
          office_status: current?.office_status || item.office_status,
          technical_task_text: current?.technical_task_text || item.technical_task_text,
          production_comment: current?.production_comment || item.production_comment,
        });
      });

      return [...positions.values()];
    },

    formatQuantity(value) {
      const number = Number(String(value ?? '').replace(',', '.'));
      if (!Number.isFinite(number)) return '0';
      return Number.isInteger(number) ? String(number) : new Intl.NumberFormat('ru-RU', {
        maximumFractionDigits: 2,
      }).format(number);
    },

    detailProductionStatus(item) {
      return item?.production_status_name || this.statusName(item?.production_status) || item?.order_status_name || '';
    },

    savingClass(row, field) {
      return this.saving[`${row.id}:${field}`] ? 'is-saving' : '';
    },

    savingWorkClass(collection, row, field) {
      const rowId = collection === 'orders_items'
        ? (this.entityId(row?.order_item) || row?.id)
        : row?.id;
      return this.saving[`${collection}:${rowId}:${field}`] ? 'is-saving' : '';
    },

    injectStyles() {
      if (document.getElementById('symbolika-costing-module-style')) return;

      const style = document.createElement('style');
      style.id = 'symbolika-costing-module-style';
      style.textContent = `
        .symbolika-costing-page {
          padding: 12px 14px;
          color: var(--theme--foreground);
        }

        .symbolika-costing-workspace {
          display: block;
        }

        .symbolika-costing-main {
          min-inline-size: 0;
        }

        .symbolika-costing-side-nav {
          display: grid;
          gap: 8px;
          inline-size: 100%;
          block-size: 100%;
          overflow: auto;
          border: 0;
          border-radius: 0;
          background: transparent;
          padding: 16px 12px 18px;
          box-shadow: none;
          align-content: start;
        }

        .symbolika-costing-side-title {
          color: var(--theme--foreground);
          font-size: 18px;
          font-weight: 950;
          line-height: 1.15;
          margin-block-end: 2px;
        }

        .symbolika-costing-side-create {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: 5px;
          inline-size: 100%;
          block-size: 34px;
          border: 1px solid var(--theme--primary);
          border-radius: 7px;
          background: color-mix(in srgb, var(--theme--primary) 92%, black);
          color: #111;
          font: inherit;
          font-size: 12px;
          font-weight: 900;
          cursor: pointer;
          box-shadow: 0 8px 20px color-mix(in srgb, var(--theme--primary) 14%, transparent);
        }

        .symbolika-costing-side-create:hover {
          transform: translateY(-1px);
          filter: brightness(1.05);
        }

        .symbolika-costing-side-group {
          display: grid;
          gap: 3px;
          padding-block-start: 7px;
          margin-block-start: 2px;
          border-block-start: 1px solid color-mix(in srgb, var(--theme--border-color) 70%, transparent);
        }

        .symbolika-costing-side-group-title {
          color: var(--theme--foreground-subdued);
          font-size: 10px;
          font-weight: 950;
          letter-spacing: .055em;
          text-transform: uppercase;
          padding: 0 6px;
          margin-block: 2px 1px;
        }

        .symbolika-costing-side-item {
          display: flex;
          align-items: center;
          gap: 7px;
          inline-size: 100%;
          min-block-size: 28px;
          border: 1px solid transparent;
          border-radius: 6px;
          background: transparent;
          color: var(--theme--foreground-subdued);
          padding: 0 8px;
          font: inherit;
          font-size: 11.5px;
          font-weight: 800;
          text-align: left;
          cursor: pointer;
        }

        .symbolika-costing-side-item .v-icon {
          opacity: .9;
        }

        .symbolika-costing-side-item:hover {
          background: color-mix(in srgb, var(--theme--foreground) 7%, transparent);
          color: var(--theme--foreground);
        }

        .symbolika-costing-side-item.is-active {
          border-color: color-mix(in srgb, var(--theme--primary) 58%, transparent);
          background: color-mix(in srgb, var(--theme--primary) 16%, transparent);
          color: var(--theme--foreground);
        }

        .symbolika-costing-toolbar {
          display: grid;
          grid-template-columns: minmax(220px, 360px) minmax(0, 1fr);
          gap: 9px;
          align-items: center;
          margin-block-end: 10px;
        }

        .symbolika-costing-tabs {
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
          margin-block-end: 10px;
        }

        .symbolika-costing-tab {
          block-size: 30px;
          border: 1px solid var(--theme--border-color);
          border-radius: 6px;
          background: color-mix(in srgb, var(--theme--background-normal) 86%, black);
          color: var(--theme--foreground-subdued);
          padding: 0 10px;
          font: inherit;
          font-size: 11.5px;
          font-weight: 800;
          cursor: pointer;
        }

        .symbolika-costing-tab.is-active {
          border-color: var(--theme--primary);
          background: color-mix(in srgb, var(--theme--primary) 18%, var(--theme--background));
          color: var(--theme--foreground);
        }

        .symbolika-costing-search {
          block-size: 36px;
          inline-size: 100%;
          border: 1px solid var(--theme--form--field--input--border-color);
          border-radius: var(--theme--border-radius);
          background: var(--theme--form--field--input--background);
          color: var(--theme--foreground);
          padding: 0 12px;
          font: inherit;
          font-size: 12px;
          outline: none;
        }

        .symbolika-costing-search:focus,
        .symbolika-costing-input:focus,
        .symbolika-costing-select:focus {
          border-color: var(--theme--primary);
          box-shadow: 0 0 0 1px var(--theme--primary);
        }

        .symbolika-costing-meta {
          color: var(--theme--foreground-subdued);
          font-size: 13px;
        }

        .symbolika-costing-actions {
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
          align-items: center;
          justify-content: flex-end;
        }

        .symbolika-costing-segments {
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
          margin-block-end: 12px;
        }

        .symbolika-costing-subtoolbar {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          justify-content: space-between;
          gap: 12px;
          margin-block-end: 14px;
        }

        .symbolika-costing-subtoolbar .symbolika-costing-segments {
          margin-block-end: 0;
        }

        .symbolika-costing-sort {
          display: inline-flex;
          align-items: center;
          gap: 10px;
          color: var(--theme--foreground-subdued);
          font-size: 12px;
          font-weight: 800;
        }

        .symbolika-costing-segment-count {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          min-inline-size: 22px;
          block-size: 22px;
          margin-inline-start: 8px;
          border-radius: 999px;
          background: color-mix(in srgb, var(--theme--foreground) 12%, transparent);
          color: var(--theme--foreground);
          font-size: 11px;
          font-weight: 900;
        }

        .symbolika-costing-filter {
          block-size: 29px;
          border: 1px solid var(--theme--border-color);
          border-radius: 999px;
          background: transparent;
          color: var(--theme--foreground-subdued);
          padding: 0 10px;
          font: inherit;
          font-size: 11.5px;
          font-weight: 800;
          cursor: pointer;
        }

        .symbolika-costing-filter.is-active {
          border-color: var(--theme--primary);
          background: color-mix(in srgb, var(--theme--primary) 18%, transparent);
          color: var(--theme--foreground);
        }

        .symbolika-costing-button {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: 6px;
          block-size: 32px;
          border: 1px solid var(--theme--primary);
          border-radius: 6px;
          background: var(--theme--primary);
          color: #111;
          padding: 0 11px;
          font: inherit;
          font-size: 11.5px;
          font-weight: 900;
          text-decoration: none;
          cursor: pointer;
        }

        .symbolika-costing-button:hover {
          filter: brightness(1.08);
        }

        .symbolika-costing-button:disabled,
        .symbolika-costing-mini-button:disabled {
          opacity: .55;
          cursor: not-allowed;
        }

        .symbolika-costing-button-compact {
          block-size: 30px;
          padding: 0 9px;
          font-size: 11px;
        }

        .symbolika-costing-bulk {
          display: flex;
          gap: 8px;
          align-items: center;
          margin-block-end: 10px;
          border: 1px solid color-mix(in srgb, var(--theme--primary) 35%, transparent);
          border-radius: 7px;
          background: color-mix(in srgb, var(--theme--primary) 10%, transparent);
          padding: 8px;
        }

        .symbolika-costing-check {
          inline-size: 16px;
          block-size: 16px;
          accent-color: var(--theme--primary);
          cursor: pointer;
        }

        .symbolika-costing-admin {
          display: grid;
          gap: 12px;
        }

        .symbolika-costing-admin-head {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: 16px;
          border: 1px solid var(--theme--border-color);
          border-radius: 8px;
          background: linear-gradient(145deg, color-mix(in srgb, var(--theme--background-normal) 94%, black), color-mix(in srgb, var(--theme--background) 98%, black));
          padding: 14px;
        }

        .symbolika-costing-admin-head h2 {
          margin: 0 0 4px;
          font-size: 18px;
          line-height: 1.1;
        }

        .symbolika-costing-admin-head p {
          max-inline-size: 620px;
          margin: 0;
          color: var(--theme--foreground-subdued);
          font-size: 12px;
          line-height: 1.45;
        }

        .symbolika-costing-admin-form {
          display: grid;
          grid-template-columns: repeat(4, minmax(150px, 1fr));
          gap: 10px;
          border: 1px solid color-mix(in srgb, var(--theme--primary) 42%, transparent);
          border-radius: 8px;
          background: color-mix(in srgb, var(--theme--primary) 8%, var(--theme--background));
          padding: 12px;
        }

        .symbolika-costing-label-wide {
          grid-column: span 2;
        }

        .symbolika-costing-checkbox-line {
          display: flex;
          align-items: center;
          gap: 8px;
          block-size: 32px;
          border: 1px solid var(--theme--border-color);
          border-radius: 6px;
          background: color-mix(in srgb, var(--theme--background-normal) 90%, black);
          padding: 0 10px;
        }

        .symbolika-costing-checkbox-line input {
          accent-color: var(--theme--primary);
        }

        .symbolika-costing-admin-actions {
          grid-column: 1 / -1;
          display: flex;
          justify-content: flex-end;
          gap: 8px;
        }

        .symbolika-costing-admin-table {
          min-inline-size: 1100px;
        }

        .symbolika-costing-row-actions {
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
        }

        .symbolika-costing-mini-button.muted {
          color: var(--theme--foreground-subdued);
        }

        .symbolika-costing-dashboard {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
          gap: 10px;
          margin-block-end: 12px;
        }

        .symbolika-costing-card {
          border: 1px solid var(--theme--border-color);
          border-radius: 8px;
          background: linear-gradient(145deg, color-mix(in srgb, var(--theme--background-normal) 92%, black), color-mix(in srgb, var(--theme--background) 96%, black));
          padding: 12px;
          box-shadow: 0 8px 22px rgb(0 0 0 / 16%);
        }

        .symbolika-costing-card-title {
          color: var(--theme--foreground-subdued);
          font-size: 10px;
          font-weight: 900;
          letter-spacing: .035em;
          text-transform: uppercase;
        }

        .symbolika-costing-card-value {
          margin-block: 7px 2px;
          color: var(--theme--foreground);
          font-size: clamp(21px, 1.9vw, 28px);
          line-height: 1;
          font-weight: 950;
          font-variant-numeric: tabular-nums;
        }

        .symbolika-costing-card-note {
          color: var(--theme--foreground-subdued);
          font-size: 11px;
          font-weight: 700;
        }

        .symbolika-costing-card.orange {
          border-color: color-mix(in srgb, var(--theme--primary) 55%, transparent);
        }

        .symbolika-costing-card.danger {
          border-color: color-mix(in srgb, var(--theme--danger) 55%, transparent);
        }

        .symbolika-costing-card.green {
          border-color: color-mix(in srgb, var(--theme--success) 55%, transparent);
        }

        .symbolika-costing-card.blue {
          border-color: color-mix(in srgb, #60a5fa 55%, transparent);
        }

        .symbolika-costing-dashboard-tight {
          grid-template-columns: repeat(4, minmax(150px, 1fr));
        }

        .symbolika-costing-reconciliation {
          display: grid;
          gap: 14px;
        }

        .symbolika-costing-reconciliation-toolbar {
          align-items: flex-start;
        }

        .symbolika-costing-reconciliation-filters {
          display: grid;
          grid-template-columns: minmax(150px, 230px) minmax(150px, 230px) 140px 140px auto;
          gap: 10px;
          align-items: center;
        }

        .symbolika-costing-reconciliation-filters .symbolika-costing-input {
          min-inline-size: 0;
        }

        .symbolika-costing-table-finance-items {
          min-inline-size: 930px;
        }

        .symbolika-costing-section-title {
          margin-block: 18px 10px;
          color: var(--theme--foreground);
          font-size: 16px;
          font-weight: 950;
        }

        .symbolika-costing-expand {
          inline-size: 28px;
          block-size: 28px;
          border: 1px solid var(--theme--border-color);
          border-radius: 6px;
          background: color-mix(in srgb, var(--theme--background-normal) 90%, black);
          color: var(--theme--foreground);
          font: inherit;
          font-size: 18px;
          font-weight: 900;
          cursor: pointer;
        }

        .symbolika-costing-position-panel {
          padding: 8px 10px;
          background: color-mix(in srgb, var(--theme--background-normal) 54%, black);
        }

        .symbolika-costing-position-list {
          display: grid;
          gap: 6px;
        }

        .symbolika-costing-position-row {
          display: grid;
          grid-template-columns: minmax(180px, 1fr) 64px 138px;
          gap: 10px;
          align-items: center;
          border: 1px solid color-mix(in srgb, var(--theme--border-color) 72%, transparent);
          border-radius: 6px;
          background: color-mix(in srgb, var(--theme--background) 94%, black);
          padding: 8px 10px;
        }

        .symbolika-costing-client-orders {
          display: grid;
          gap: 6px;
        }

        .symbolika-costing-client-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(360px, 1fr));
          gap: 14px;
        }

        .symbolika-costing-client-card {
          border: 1px solid color-mix(in srgb, var(--theme--border-color) 72%, transparent);
          border-radius: 10px;
          background:
            linear-gradient(145deg, color-mix(in srgb, var(--theme--background-accent) 56%, transparent), transparent 72%),
            color-mix(in srgb, var(--theme--background) 96%, black);
          padding: 14px;
        }

        .symbolika-costing-client-card.has-debt {
          border-color: color-mix(in srgb, var(--theme--danger) 46%, var(--theme--border-color));
        }

        .symbolika-costing-client-card-head {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: 12px;
        }

        .symbolika-costing-client-card-title {
          min-inline-size: 0;
        }

        .symbolika-costing-client-card-kicker {
          color: var(--theme--foreground-subdued);
          font-size: 10px;
          font-weight: 850;
          letter-spacing: 0;
          text-transform: uppercase;
        }

        .symbolika-costing-client-card h3 {
          margin: 2px 0 0;
          color: var(--theme--foreground);
          font-size: 19px;
          font-weight: 900;
          line-height: 1.16;
        }

        .symbolika-costing-client-card-meta {
          display: grid;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          gap: 8px;
          margin-block-start: 12px;
        }

        .symbolika-costing-client-card-meta span,
        .symbolika-costing-client-card-meta a {
          min-inline-size: 0;
          overflow: hidden;
          color: var(--theme--foreground-subdued);
          font-size: 12px;
          font-weight: 750;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .symbolika-costing-client-card-meta span {
          display: flex;
          align-items: center;
          gap: 6px;
        }

        .symbolika-costing-client-card-money {
          display: grid;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          gap: 8px;
          margin-block-start: 12px;
        }

        .symbolika-costing-client-card-money span {
          min-inline-size: 0;
          border: 1px solid color-mix(in srgb, var(--theme--border-color) 58%, transparent);
          border-radius: 8px;
          background: color-mix(in srgb, var(--theme--background-subdued) 34%, transparent);
          padding: 9px 10px;
        }

        .symbolika-costing-client-card-money em {
          display: block;
          color: var(--theme--foreground-subdued);
          font-size: 10px;
          font-style: normal;
          font-weight: 850;
          line-height: 1.2;
          text-transform: uppercase;
        }

        .symbolika-costing-client-card-money strong {
          display: block;
          margin-block-start: 4px;
          color: var(--theme--foreground);
          font-size: 17px;
          font-weight: 900;
          line-height: 1.15;
          white-space: nowrap;
        }

        .symbolika-costing-client-card-actions {
          display: flex;
          align-items: center;
          gap: 10px;
          margin-block-start: 12px;
        }

        .symbolika-costing-client-order-title {
          display: inline-flex;
          align-items: baseline;
          flex-wrap: wrap;
          gap: 6px;
          min-inline-size: 0;
        }

        .symbolika-costing-client-order {
          display: grid;
          grid-template-columns: minmax(220px, 1fr) 180px;
          gap: 12px;
          align-items: center;
          inline-size: 100%;
          border: 1px solid color-mix(in srgb, var(--theme--border-color) 64%, transparent);
          border-radius: 6px;
          background: color-mix(in srgb, var(--theme--background) 95%, black);
          color: var(--theme--foreground);
          padding: 8px 10px;
          text-align: left;
          cursor: pointer;
        }

        .symbolika-costing-client-order:hover {
          border-color: color-mix(in srgb, var(--theme--primary) 60%, var(--theme--border-color));
          background: color-mix(in srgb, var(--theme--primary) 7%, var(--theme--background));
        }

        .symbolika-costing-link-button {
          display: inline;
          border: 0;
          background: transparent;
          color: var(--theme--foreground);
          font: inherit;
          font-weight: 850;
          line-height: 1.25;
          padding: 0;
          text-align: left;
          cursor: pointer;
        }

        .symbolika-costing-link-button:hover {
          color: var(--theme--primary);
          text-decoration: underline;
          text-underline-offset: 3px;
        }

        .symbolika-costing-expanded-row td {
          background: color-mix(in srgb, var(--theme--background-subdued) 22%, transparent);
          padding-block: 10px;
        }

        .symbolika-costing-inline-list {
          display: flex;
          flex-wrap: wrap;
          gap: 6px 10px;
          align-items: center;
        }

        .symbolika-costing-empty-inline {
          min-block-size: 0;
          padding: 10px;
        }

        .symbolika-costing-position-qty {
          color: var(--theme--foreground);
          font-size: 12px;
          font-weight: 850;
          text-align: right;
          white-space: nowrap;
        }

        .symbolika-costing-modal-backdrop {
          position: fixed;
          inset: 0;
          z-index: 100;
          display: grid;
          place-items: center;
          background: rgb(0 0 0 / 58%);
        }

        .symbolika-costing-modal {
          inline-size: min(520px, 92vw);
          border: 1px solid var(--theme--border-color);
          border-radius: 12px;
          background: var(--theme--background);
          box-shadow: 0 22px 60px rgb(0 0 0 / 36%);
          padding: 22px;
        }

        .symbolika-costing-modal h2 {
          margin: 0 0 16px;
          font-size: 24px;
        }

        .symbolika-costing-modal-head {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: 16px;
          margin-block-end: 16px;
        }

        .symbolika-costing-modal-head h2 {
          margin: 2px 0 0;
        }

        .symbolika-costing-order-modal {
          inline-size: min(1180px, 94vw);
          max-block-size: 88vh;
          overflow: auto;
        }

        .symbolika-costing-new-order-grid {
          display: grid;
          grid-template-columns: repeat(4, minmax(0, 1fr));
          gap: 11px;
          margin-block-end: 16px;
        }

        .symbolika-costing-new-order-wide {
          grid-column: span 2;
        }

        .symbolika-costing-field-with-action {
          display: grid;
          grid-template-columns: minmax(0, 1fr) auto;
          gap: 8px;
          align-items: center;
        }

        .symbolika-costing-inline-button {
          block-size: 32px;
          border: 1px solid color-mix(in srgb, var(--theme--primary) 70%, transparent);
          border-radius: 6px;
          background: color-mix(in srgb, var(--theme--primary) 16%, transparent);
          color: var(--theme--primary);
          padding: 0 10px;
          font: inherit;
          font-size: 11px;
          font-weight: 850;
          cursor: pointer;
          white-space: nowrap;
        }

        .symbolika-costing-inline-button:hover {
          background: var(--theme--primary);
          color: var(--theme--primary-subdued);
        }

        .symbolika-costing-checkbox {
          display: flex;
          align-items: center;
          gap: 8px;
          min-block-size: 32px;
          align-self: end;
          border: 1px solid var(--theme--form--field--input--border-color);
          border-radius: 6px;
          background: var(--theme--form--field--input--background);
          color: var(--theme--foreground);
          padding: 0 10px;
          font-size: 11.5px;
          font-weight: 800;
        }

        .symbolika-costing-checkbox input {
          inline-size: 16px;
          block-size: 16px;
          accent-color: var(--theme--primary);
        }

        .symbolika-costing-new-order-items-head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 12px;
          margin-block: 8px 0;
        }

        .symbolika-costing-new-order-items-head h3 {
          margin: 0;
          font-size: 17px;
        }

        .symbolika-costing-new-order-items {
          display: grid;
          gap: 8px;
          margin-block-start: 8px;
        }

        .symbolika-costing-new-order-item {
          display: grid;
          grid-template-columns: minmax(180px, 1.35fr) 82px 100px 126px repeat(3, minmax(126px, 1fr)) 148px 64px;
          gap: 8px;
          align-items: end;
          border: 1px solid color-mix(in srgb, var(--theme--border-color) 74%, transparent);
          border-radius: 7px;
          background: color-mix(in srgb, var(--theme--background-normal) 78%, black);
          padding: 10px;
        }

        .symbolika-costing-new-order-task,
        .symbolika-costing-new-order-url {
          grid-column: span 2;
        }

        .symbolika-costing-new-order-remove {
          align-self: end;
          padding: 0 8px;
        }

        .symbolika-costing-modal-grid {
          display: grid;
          gap: 11px;
        }

        .symbolika-costing-modal-actions {
          display: flex;
          justify-content: flex-end;
          gap: 8px;
          margin-block-start: 15px;
        }

        .symbolika-costing-label {
          display: grid;
          gap: 5px;
          color: var(--theme--foreground);
          font-size: 12px;
          font-weight: 850;
        }

        .symbolika-costing-error {
          margin-block-end: 14px;
          border: 1px solid color-mix(in srgb, var(--theme--danger) 70%, transparent);
          border-radius: var(--theme--border-radius);
          background: color-mix(in srgb, var(--theme--danger) 12%, transparent);
          color: var(--theme--danger);
          padding: 12px 14px;
          font-weight: 700;
        }

        .symbolika-costing-table-wrap {
          overflow: auto;
          border: 1px solid var(--theme--border-color);
          border-radius: 7px;
          background: color-mix(in srgb, var(--theme--background) 94%, black);
          box-shadow: 0 8px 22px rgb(0 0 0 / 14%);
        }

        .symbolika-costing-table {
          inline-size: 100%;
          min-inline-size: 920px;
          table-layout: fixed;
          border-collapse: collapse;
          font-size: 11px;
          line-height: 1.25;
        }

        .symbolika-costing-table-office {
          min-inline-size: 720px;
        }

        .symbolika-costing-table-compact {
          min-inline-size: 860px;
        }

        .symbolika-costing-table-finance {
          min-inline-size: 720px;
        }

        .symbolika-costing-table-orders {
          min-inline-size: 820px;
        }

        .symbolika-costing-table-deadlines {
          min-inline-size: 760px;
        }

        .symbolika-costing-table-finance th:nth-child(5),
        .symbolika-costing-table-finance td:nth-child(5) {
          display: none;
        }

        .symbolika-costing-table-deadlines th:nth-child(n+8),
        .symbolika-costing-table-deadlines td:nth-child(n+8) {
          display: none;
        }

        .symbolika-costing-table-work {
          min-inline-size: 740px;
        }

        .symbolika-costing-table-work th:nth-child(6),
        .symbolika-costing-table-work td:nth-child(6) {
          display: none;
        }

        .symbolika-costing-table th,
        .symbolika-costing-table td {
          border-block-end: 1px solid var(--theme--border-color);
          padding: 6px 8px;
          text-align: left;
          vertical-align: middle;
        }

        .symbolika-costing-table th {
          position: sticky;
          inset-block-start: 0;
          z-index: 1;
          background: color-mix(in srgb, var(--theme--background-normal) 92%, black);
          color: color-mix(in srgb, var(--theme--foreground) 84%, var(--theme--primary));
          font-size: 10px;
          font-weight: 850;
          letter-spacing: .01em;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .symbolika-costing-table tr:hover td {
          background: color-mix(in srgb, var(--theme--primary) 5%, transparent);
        }

        .symbolika-costing-order {
          color: var(--theme--primary);
          font-weight: 950;
          text-decoration: none;
          white-space: nowrap;
          display: inline-block;
        }

        .symbolika-costing-product {
          font-weight: 800;
          color: var(--theme--foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }

        .symbolika-costing-subtle {
          color: var(--theme--foreground-subdued);
          font-size: 10.5px;
          margin-block-start: 2px;
        }

        .symbolika-costing-link {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          block-size: 26px;
          border: 1px solid color-mix(in srgb, var(--theme--primary) 48%, transparent);
          border-radius: 6px;
          color: var(--theme--primary);
          padding: 0 8px;
          font-size: 10.5px;
          font-weight: 800;
          text-decoration: none;
          white-space: nowrap;
        }

        .symbolika-costing-link-inline {
          margin-block-start: 7px;
        }

        .symbolika-costing-mini-button {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: 5px;
          block-size: 26px;
          border: 1px solid var(--theme--border-color);
          border-radius: 6px;
          background: color-mix(in srgb, var(--theme--background-normal) 92%, black);
          color: var(--theme--foreground);
          padding: 0 7px;
          font: inherit;
          font-size: 10.5px;
          font-weight: 800;
          cursor: pointer;
        }

        .symbolika-costing-text {
          max-inline-size: 240px;
          color: var(--theme--foreground-subdued);
          overflow: hidden;
          text-overflow: ellipsis;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }

        .symbolika-costing-comment {
          inline-size: 100%;
          min-block-size: 36px;
          max-block-size: 64px;
          border: 1px solid var(--theme--form--field--input--border-color);
          border-radius: var(--theme--border-radius);
          background: var(--theme--form--field--input--background);
          color: var(--theme--foreground);
          padding: 8px 10px;
          font: inherit;
          font-size: 12px;
          resize: vertical;
          outline: none;
        }

        .symbolika-costing-input,
        .symbolika-costing-select {
          inline-size: 100%;
          block-size: 30px;
          border: 1px solid var(--theme--form--field--input--border-color);
          border-radius: 6px;
          background: var(--theme--form--field--input--background);
          color: var(--theme--foreground);
          padding: 0 8px;
          font: inherit;
          font-size: 11px;
          font-weight: 650;
          outline: none;
        }

        .symbolika-costing-input.is-saving,
        .symbolika-costing-select.is-saving {
          border-color: var(--theme--primary);
          opacity: .76;
        }

        .symbolika-costing-select-green {
          border-color: color-mix(in srgb, var(--theme--success) 42%, var(--theme--form--field--input--border-color));
          background: color-mix(in srgb, var(--theme--success) 10%, var(--theme--form--field--input--background));
        }

        .symbolika-costing-select-blue {
          border-color: color-mix(in srgb, #60a5fa 42%, var(--theme--form--field--input--border-color));
          background: color-mix(in srgb, #60a5fa 9%, var(--theme--form--field--input--background));
        }

        .symbolika-costing-select-orange {
          border-color: color-mix(in srgb, var(--theme--primary) 48%, var(--theme--form--field--input--border-color));
          background: color-mix(in srgb, var(--theme--primary) 10%, var(--theme--form--field--input--background));
        }

        .symbolika-costing-select-purple {
          border-color: color-mix(in srgb, #a78bfa 42%, var(--theme--form--field--input--border-color));
          background: color-mix(in srgb, #a78bfa 9%, var(--theme--form--field--input--background));
        }

        .symbolika-costing-select-danger {
          border-color: color-mix(in srgb, var(--theme--danger) 45%, var(--theme--form--field--input--border-color));
          background: color-mix(in srgb, var(--theme--danger) 10%, var(--theme--form--field--input--background));
        }

        .symbolika-costing-select-muted {
          opacity: .88;
        }

        .symbolika-costing-table-select,
        .symbolika-costing-table-date {
          inline-size: 100%;
          min-inline-size: 0;
          block-size: 28px;
          border: 1px solid var(--theme--form--field--input--border-color);
          border-radius: 6px;
          background: var(--theme--form--field--input--background);
          color: var(--theme--foreground);
          padding: 0 7px;
          font: inherit;
          font-size: 10.5px;
          font-weight: 800;
          outline: none;
        }

        .symbolika-costing-table-date {
          color-scheme: dark;
        }

        .symbolika-costing-date-stack {
          display: grid;
          gap: 4px;
          min-inline-size: 0;
        }

        .symbolika-costing-date-stack > span {
          color: var(--theme--foreground-subdued);
          font-size: 10.5px;
          font-weight: 800;
          line-height: 1.1;
          white-space: nowrap;
        }

        .symbolika-costing-date-stack .symbolika-costing-table-date {
          block-size: 24px;
          padding-inline: 5px;
          font-size: 10px;
        }

        .symbolika-costing-cell-stack {
          display: grid;
          gap: 4px;
          min-inline-size: 0;
          align-content: center;
        }

        .symbolika-costing-cell-line {
          display: flex;
          align-items: center;
          gap: 6px;
          min-inline-size: 0;
          flex-wrap: wrap;
        }

        .symbolika-costing-cell-main {
          min-inline-size: 0;
          overflow: hidden;
          color: var(--theme--foreground);
          font-weight: 850;
          line-height: 1.15;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .symbolika-costing-cell-meta {
          min-inline-size: 0;
          overflow: hidden;
          color: var(--theme--foreground-subdued);
          font-size: 11px;
          font-weight: 750;
          line-height: 1.15;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .symbolika-costing-cell-money {
          display: grid;
          gap: 3px;
          min-inline-size: 0;
          justify-items: end;
          color: var(--theme--foreground-subdued);
          font-size: 10.5px;
          font-weight: 750;
          line-height: 1.15;
        }

        .symbolika-costing-cell-money span {
          display: inline-flex;
          align-items: center;
          gap: 5px;
          max-inline-size: 100%;
        }

        .symbolika-costing-cell-money strong {
          color: var(--theme--foreground);
          font-size: 12.5px;
          font-weight: 900;
        }

        .symbolika-costing-table-select.is-saving,
        .symbolika-costing-table-date.is-saving {
          border-color: var(--theme--primary);
          box-shadow: 0 0 0 1px color-mix(in srgb, var(--theme--primary) 28%, transparent);
        }

        .symbolika-costing-entity-link {
          color: var(--theme--foreground);
          font-weight: 850;
          text-decoration: none;
        }

        .symbolika-costing-entity-link:hover {
          color: var(--theme--primary);
          text-decoration: underline;
        }

        .symbolika-costing-entity-link-muted {
          color: var(--theme--foreground-subdued);
          font-size: 11px;
          font-weight: 750;
        }

        .symbolika-costing-status-stack {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
          gap: 8px;
          align-items: center;
          min-inline-size: 0;
        }

        .symbolika-costing-stacked-input {
          margin-block-start: 7px;
        }

        .symbolika-costing-pill {
          display: inline-flex;
          align-items: center;
          gap: 5px;
          min-block-size: 23px;
          max-inline-size: 100%;
          border-radius: 999px;
          background: color-mix(in srgb, var(--theme--background-normal) 88%, white);
          color: var(--theme--foreground);
          padding: 3px 8px;
          font-size: 11px;
          font-weight: 850;
          line-height: 1.15;
          white-space: nowrap;
        }

        .symbolika-costing-pill-green {
          background: color-mix(in srgb, var(--theme--success) 18%, var(--theme--background-normal));
          color: color-mix(in srgb, var(--theme--success) 82%, white);
        }

        .symbolika-costing-pill-blue {
          background: color-mix(in srgb, #60a5fa 18%, var(--theme--background-normal));
          color: color-mix(in srgb, #93c5fd 88%, white);
        }

        .symbolika-costing-pill-orange {
          background: color-mix(in srgb, var(--theme--primary) 18%, var(--theme--background-normal));
          color: color-mix(in srgb, var(--theme--primary) 88%, white);
        }

        .symbolika-costing-pill-purple {
          background: color-mix(in srgb, #a78bfa 18%, var(--theme--background-normal));
          color: color-mix(in srgb, #c4b5fd 88%, white);
        }

        .symbolika-costing-pill-danger {
          background: color-mix(in srgb, var(--theme--danger) 18%, var(--theme--background-normal));
          color: color-mix(in srgb, var(--theme--danger) 78%, white);
        }

        .symbolika-costing-pill-muted {
          background: color-mix(in srgb, var(--theme--foreground-subdued) 13%, var(--theme--background-normal));
          color: color-mix(in srgb, var(--theme--foreground-subdued) 82%, white);
        }

        .symbolika-costing-icon {
          flex: 0 0 auto;
          font-family: 'Material Symbols Outlined', 'Material Icons';
          font-size: 17px;
          font-weight: 400;
          line-height: 1;
          font-style: normal;
          letter-spacing: normal;
          text-transform: none;
          white-space: nowrap;
          word-wrap: normal;
          direction: ltr;
          font-feature-settings: 'liga';
          -webkit-font-feature-settings: 'liga';
          -webkit-font-smoothing: antialiased;
          font-variation-settings: 'FILL' 0, 'wght' 600, 'GRAD' 0, 'opsz' 20;
        }

        .symbolika-costing-date {
          display: inline-flex;
          align-items: center;
          gap: 5px;
          min-block-size: 24px;
          border-radius: 999px;
          padding: 3px 9px;
          font-size: 12px;
          font-weight: 850;
          white-space: nowrap;
        }

        .symbolika-costing-date-normal {
          background: color-mix(in srgb, var(--theme--foreground-subdued) 10%, transparent);
          color: var(--theme--foreground-subdued);
        }

        .symbolika-costing-date-hot {
          background: color-mix(in srgb, var(--theme--primary) 20%, transparent);
          color: color-mix(in srgb, var(--theme--primary) 88%, white);
        }

        .symbolika-costing-date-danger {
          background: color-mix(in srgb, var(--theme--danger) 20%, transparent);
          color: color-mix(in srgb, var(--theme--danger) 76%, white);
        }

        .symbolika-costing-row-overdue td {
          background: color-mix(in srgb, var(--theme--danger) 5%, transparent);
        }

        .symbolika-costing-row-today td {
          background: color-mix(in srgb, var(--theme--primary) 5%, transparent);
        }

        .symbolika-costing-row-unpaid td:first-child {
          box-shadow: inset 3px 0 0 color-mix(in srgb, var(--theme--danger) 78%, var(--theme--primary));
        }

        .symbolika-costing-money-stack {
          display: grid;
          gap: 3px;
          color: var(--theme--foreground-subdued);
          font-size: 11px;
          font-weight: 750;
          line-height: 1.15;
        }

        .symbolika-costing-money-stack span {
          display: flex;
          justify-content: space-between;
          gap: 6px;
          white-space: nowrap;
        }

        .symbolika-costing-money-stack strong {
          color: var(--theme--foreground);
          font-size: 11.5px;
          font-weight: 900;
          font-variant-numeric: tabular-nums;
        }

        .symbolika-costing-kpi {
          white-space: nowrap;
          font-weight: 700;
        }

        .symbolika-costing-num {
          text-align: right;
          white-space: nowrap;
          font-variant-numeric: tabular-nums;
        }

        .symbolika-costing-table th.symbolika-costing-num {
          text-align: right;
        }

        .symbolika-costing-input.symbolika-costing-num {
          text-align: right;
        }

        @media (max-width: 1280px) {
          .symbolika-costing-page {
            padding: 12px;
          }

          .symbolika-costing-workspace {
            display: block;
          }

          .symbolika-costing-side-nav {
            border: 0;
            border-radius: 0;
            background: transparent;
            padding: 14px 10px 18px;
            box-shadow: none;
          }

          .symbolika-costing-main {
            margin-inline-start: 0;
          }

          .symbolika-costing-toolbar {
            grid-template-columns: 1fr;
          }

          .symbolika-costing-actions,
          .symbolika-costing-subtoolbar {
            justify-content: flex-start;
          }

          .symbolika-costing-dashboard-tight {
            grid-template-columns: repeat(2, minmax(180px, 1fr));
          }

          .symbolika-costing-reconciliation-filters {
            grid-template-columns: 1fr;
            inline-size: 100%;
          }

          .symbolika-costing-table {
            min-inline-size: 980px;
          }

          .symbolika-costing-table-compact,
          .symbolika-costing-table-work {
            min-inline-size: 960px;
          }

          .symbolika-costing-table-office {
            min-inline-size: 760px;
          }

          .symbolika-costing-table-finance,
          .symbolika-costing-table-deadlines,
          .symbolika-costing-table-work {
            min-inline-size: 740px;
          }
        }

        .symbolika-costing-empty {
          padding: 40px;
          text-align: center;
          color: var(--theme--foreground-subdued);
        }

        .symbolika-costing-detail {
          position: fixed;
          inset-block: 0;
          inset-inline-end: 0;
          z-index: 90;
          inline-size: min(460px, 92vw);
          border-inline-start: 1px solid var(--theme--border-color);
          background: var(--theme--background);
          box-shadow: -18px 0 40px rgb(0 0 0 / 26%);
          padding: 22px;
          overflow: auto;
        }

        .symbolika-costing-detail-head {
          display: flex;
          justify-content: space-between;
          gap: 16px;
          align-items: flex-start;
          margin-block-end: 18px;
        }

        .symbolika-costing-detail h2 {
          margin: 0;
          font-size: 24px;
          line-height: 1.1;
        }

        .symbolika-costing-detail-close {
          inline-size: 36px;
          block-size: 36px;
          border: 1px solid var(--theme--border-color);
          border-radius: 50%;
          background: transparent;
          color: var(--theme--foreground);
          font-size: 22px;
          cursor: pointer;
        }

        .symbolika-costing-detail-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 12px;
        }

        .symbolika-costing-detail-field {
          border: 1px solid var(--theme--border-color);
          border-radius: 7px;
          background: color-mix(in srgb, var(--theme--background-normal) 82%, black);
          padding: 10px;
        }

        .symbolika-costing-detail-label {
          color: var(--theme--foreground-subdued);
          font-size: 11px;
          font-weight: 800;
          margin-block-end: 5px;
        }

        .symbolika-costing-detail-value {
          font-size: 14px;
          font-weight: 750;
        }

        .symbolika-costing-detail-wide {
          grid-column: 1 / -1;
        }

        .symbolika-costing-detail-items {
          display: grid;
          gap: 7px;
        }

        .symbolika-costing-detail-item {
          display: grid;
          grid-template-columns: minmax(0, 1fr);
          gap: 7px;
          align-items: start;
          border-block-end: 1px solid color-mix(in srgb, var(--theme--border-color) 70%, transparent);
          padding-block-end: 9px;
        }

        .symbolika-costing-detail-item:last-child {
          border-block-end: 0;
          padding-block-end: 0;
        }

        .symbolika-costing-detail-item strong {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .symbolika-costing-detail-item span {
          color: var(--theme--foreground-subdued);
          font-size: 12px;
          font-weight: 750;
        }

        .symbolika-costing-detail-item-meta {
          display: grid;
          grid-template-columns: minmax(70px, .75fr) minmax(0, 1fr);
          gap: 6px;
          align-items: center;
        }

        .symbolika-costing-detail-item-meta span {
          white-space: nowrap;
        }

        .symbolika-costing-detail-item-meta .symbolika-costing-table-select,
        .symbolika-costing-detail-item-meta .symbolika-costing-table-date {
          min-inline-size: 0;
          inline-size: 100%;
          block-size: 26px;
          font-size: 10px;
        }

        @media (max-width: 680px) {
          .symbolika-costing-detail-item-meta {
            grid-template-columns: 1fr 1fr;
          }
        }
      `;
      document.head.appendChild(style);
    },
  },

  template: `
    <private-view :title="moduleTitle">
      <template #navigation>
        <nav v-if="availableTabs.length" class="symbolika-costing-side-nav" aria-label="Навигация рабочего центра">
          <div class="symbolika-costing-side-title">{{ moduleTitle }}</div>
          <button v-if="canCreateOrders" type="button" class="symbolika-costing-side-create" @click="openNewOrderDialog">
            <v-icon name="add" small />
            Новый заказ
          </button>
          <div v-for="group in navigationGroups" :key="group.title" class="symbolika-costing-side-group">
            <div class="symbolika-costing-side-group-title">{{ group.title }}</div>
            <button
              v-for="tab in group.tabs"
              :key="tab.id"
              type="button"
              class="symbolika-costing-side-item"
              :class="{ 'is-active': activeTab === tab.id }"
              @click="setTab(tab.id)"
            >
              <v-icon :name="tabIcon(tab.id)" small />
              {{ tab.title }}
            </button>
          </div>
        </nav>
      </template>
      <div class="symbolika-costing-page">
        <div class="symbolika-costing-workspace">
          <main class="symbolika-costing-main">

        <div v-if="!availableTabs.length" class="symbolika-costing-empty">
          Для вашей роли нет доступных рабочих таблиц.
        </div>

        <div v-if="availableTabs.length" class="symbolika-costing-toolbar">
          <input
            v-model="search"
            class="symbolika-costing-search"
            type="search"
            :placeholder="'Поиск: ' + activeTabTitle.toLowerCase()"
          />
          <div class="symbolika-costing-actions">
            <button v-if="canCreateOrderHere" type="button" class="symbolika-costing-button" @click="openNewOrderDialog">
              <v-icon name="add" small />
              Новый заказ
            </button>
            <button
              v-for="filter in visibleQuickFilters"
              :key="filter.id"
              type="button"
              class="symbolika-costing-filter"
              :class="{ 'is-active': activeFilter === filter.id }"
              @click="setFilter(filter.id)"
            >
              {{ filter.title }}
            </button>
            <button type="button" class="symbolika-costing-button" @click="exportCurrentTable">
              <v-icon name="download" small />
              Экспорт
            </button>
          </div>
        </div>

        <div v-if="error && availableTabs.length" class="symbolika-costing-error">{{ error }}</div>

        <div v-if="activeTab === 'dashboard'">
          <div class="symbolika-costing-dashboard">
            <button
              v-for="card in dashboardCards"
              :key="card.title"
              type="button"
              class="symbolika-costing-card"
              :class="card.accent"
              @click="card.title === 'Очередь задач' ? setTab('queue') : card.title === 'Требует внимания' ? setTab('problems') : null"
            >
              <div class="symbolika-costing-card-title">{{ card.title }}</div>
              <div class="symbolika-costing-card-value">{{ card.value }}</div>
              <div class="symbolika-costing-card-note">{{ card.note }}</div>
            </button>
          </div>

          <div class="symbolika-costing-table-wrap">
            <table class="symbolika-costing-table">
              <colgroup>
                <col style="width: 135px" />
                <col style="width: 210px" />
                <col style="width: 145px" />
                <col style="width: 220px" />
                <col style="width: 78px" />
              </colgroup>
              <thead>
                <tr>
                  <th>Что сделать</th>
                  <th>Причина</th>
                  <th>Заказ</th>
                  <th>Клиент / позиция</th>
                  <th>Детали</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="item in problemRows.slice(0, 8)" :key="item.id" :class="rowStateClass(item.row)">
                  <td><span class="symbolika-costing-pill" :class="item.filters.includes('overdue') ? 'symbolika-costing-pill-danger' : item.filters.includes('today') ? 'symbolika-costing-pill-orange' : 'symbolika-costing-pill-blue'">{{ item.section }}</span></td>
                  <td>{{ item.reason }}</td>
                  <td>
                    <div class="symbolika-costing-cell-stack">
                      <a class="symbolika-costing-order" :href="orderUrl(item.row)" @click.prevent="openDetail(item.type, item.row)">{{ item.order_number }}</a>
                      <span class="symbolika-costing-cell-meta">{{ formatDate(item.row?.date) }}</span>
                      <span class="symbolika-costing-date" :class="deadlineClass(item.deadline)"><v-icon :name="deadlineIcon(item.deadline)" small />{{ formatDate(item.deadline) }}</span>
                    </div>
                  </td>
                  <td>
                    <div class="symbolika-costing-cell-stack">
                      <span class="symbolika-costing-cell-main">{{ item.customer_name || '-' }}</span>
                      <span class="symbolika-costing-product">{{ item.product_name || '-' }}</span>
                      <span class="symbolika-costing-cell-meta">
                        {{ formatQuantity(item.quantity) }} шт. В·
                        <a v-if="managerUrl(item.row)" class="symbolika-costing-entity-link" :href="managerUrl(item.row)" @click.prevent="openEntityDetail('manager', item.row)">{{ item.manager_name || detailManagerName(item.row) }}</a>
                        <span v-else>{{ item.customer_company_name || item.manager_name || '-' }}</span>
                      </span>
                    </div>
                  </td>
                  <td>
                    <button type="button" class="symbolika-costing-mini-button" @click="openDetail(item.type, item.row)">
                      <v-icon name="info" small />
                      Инфо
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
            <div v-if="!problemRows.length" class="symbolika-costing-empty">Критичных задач сейчас нет</div>
          </div>
        </div>

        <div v-if="activeTab === 'problems' || activeTab === 'search'" class="symbolika-costing-table-wrap">
          <table class="symbolika-costing-table symbolika-costing-table-orders">
            <colgroup>
              <col style="width: 126px" />
              <col style="width: 210px" />
              <col style="width: 145px" />
              <col style="width: 240px" />
              <col style="width: 74px" />
            </colgroup>
            <thead>
              <tr>
                <th>Раздел</th>
                <th>Статус / причина</th>
                <th>Заказ</th>
                <th>Клиент / позиция</th>
                <th>Детали</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="item in activeTab === 'problems' ? problemRows : globalSearchRows" :key="item.id" :class="rowStateClass(item.row)">
                <td><span class="symbolika-costing-pill" :class="item.filters.includes('overdue') ? 'symbolika-costing-pill-danger' : item.filters.includes('today') ? 'symbolika-costing-pill-orange' : 'symbolika-costing-pill-blue'">{{ item.section }}</span></td>
                <td>{{ item.reason }}</td>
                <td>
                  <div class="symbolika-costing-cell-stack">
                    <a class="symbolika-costing-order" :href="orderUrl(item.row)" @click.prevent="openDetail(item.type, item.row)">{{ item.order_number }}</a>
                    <span class="symbolika-costing-cell-meta">{{ formatDate(item.row?.date) }}</span>
                    <span class="symbolika-costing-date" :class="deadlineClass(item.deadline)"><v-icon :name="deadlineIcon(item.deadline)" small />{{ formatDate(item.deadline) }}</span>
                  </div>
                </td>
                <td>
                  <div class="symbolika-costing-cell-stack">
                    <span class="symbolika-costing-cell-main">{{ item.customer_name || '-' }}</span>
                    <span class="symbolika-costing-product">{{ item.product_name || '-' }}</span>
                    <span class="symbolika-costing-cell-meta">
                      {{ formatQuantity(item.quantity) }} шт. В·
                      <a v-if="managerUrl(item.row)" class="symbolika-costing-entity-link" :href="managerUrl(item.row)" @click.prevent="openEntityDetail('manager', item.row)">{{ item.manager_name || detailManagerName(item.row) }}</a>
                      <span v-else>{{ item.customer_company_name || item.manager_name || '-' }}</span>
                    </span>
                  </div>
                </td>
                <td>
                  <button type="button" class="symbolika-costing-mini-button" @click="openDetail(item.type, item.row)">
                    <v-icon name="info" small />
                    Инфо
                  </button>
                </td>
              </tr>
            </tbody>
          </table>

          <div
            v-if="!(activeTab === 'problems' ? problemRows : globalSearchRows).length"
            class="symbolika-costing-empty"
          >
            {{ activeTab === 'search' ? 'Начните вводить номер заказа, клиента или позицию' : 'Нет проблемных строк' }}
          </div>
        </div>

        <div v-if="activeTab === 'my_orders'" class="symbolika-costing-table-wrap">
          <table class="symbolika-costing-table">
            <colgroup>
              <col style="width: 145px" />
              <col style="width: 190px" />
              <col style="width: 150px" />
              <col style="width: 260px" />
              <col style="width: 190px" />
              <col style="width: 70px" />
            </colgroup>
            <thead>
              <tr>
                <th>Заказ</th>
                <th>Заказчик</th>
                <th>Менеджер</th>
                <th>Статусы</th>
                <th class="symbolika-costing-num">Деньги</th>
                <th>Детали</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in visibleMyOrderRows" :key="row.id" :class="rowStateClass(row)">
                <td>
                  <div class="symbolika-costing-cell-stack">
                    <a class="symbolika-costing-order" :href="orderUrl(row)" @click.prevent="openDetail('my_orders', row)">{{ row.order_number }}</a>
                    <span class="symbolika-costing-cell-meta">{{ formatDate(row.date) }}</span>
                    <input
                      class="symbolika-costing-table-date"
                      :class="[savingWorkClass('orders', row, 'deadline'), deadlineClass(row.deadline)]"
                      type="date"
                      :value="dateInput(row.deadline)"
                      @change="saveOrderField(row, 'deadline', $event.target.value)"
                    />
                  </div>
                </td>
                <td>
                  <div class="symbolika-costing-cell-stack">
                    <a v-if="customerUrl(row)" class="symbolika-costing-entity-link" :href="customerUrl(row)" @click.prevent="openEntityDetail('customer', row)">{{ detailCustomerName(row) }}</a>
                    <span v-else class="symbolika-costing-cell-main">{{ detailCustomerName(row) }}</span>
                    <a v-if="companyUrl(row)" class="symbolika-costing-entity-link symbolika-costing-entity-link-muted" :href="companyUrl(row)" @click.prevent="openEntityDetail('company', row)">{{ detailCompanyName(row) }}</a>
                    <span v-else class="symbolika-costing-cell-meta">{{ detailCompanyName(row) !== '-' ? detailCompanyName(row) : 'Лично' }}</span>
                    <span class="symbolika-costing-cell-meta">{{ row.shipping_method_name || '-' }}</span>
                  </div>
                </td>
                <td>
                  <div class="symbolika-costing-cell-stack">
                    <a v-if="managerUrl(row)" class="symbolika-costing-entity-link" :href="managerUrl(row)" @click.prevent="openEntityDetail('manager', row)">{{ row.manager_name || '-' }}</a>
                    <span v-else class="symbolika-costing-cell-main">{{ row.manager_name || '-' }}</span>
                  </div>
                </td>
                <td>
                  <div class="symbolika-costing-status-stack">
                    <select
                      class="symbolika-costing-table-select"
                      :class="[savingWorkClass('orders', row, 'order_status'), statusToneClass(row.order_status_name)]"
                      :value="row.order_status"
                      @change="saveOrderField(row, 'order_status', $event.target.value)"
                    >
                      <option v-for="status in orderStatuses" :key="status.id" :value="status.id">
                        {{ status.name }}
                      </option>
                    </select>
                    <select
                      class="symbolika-costing-table-select"
                      :class="[savingWorkClass('orders', row, 'office_status'), officeSelectClass(row.office_status)]"
                      :value="row.office_status"
                      @change="saveOrderField(row, 'office_status', $event.target.value)"
                    >
                      <option v-for="status in officeStatusChoices" :key="status.value" :value="status.value">
                        {{ status.text }}
                      </option>
                    </select>
                  </div>
                </td>
                <td class="symbolika-costing-num">
                  <div class="symbolika-costing-cell-money">
                    <span>Сумма <strong>{{ formatMoney(row.order_sum) }}</strong></span>
                    <span>Оплачено <strong>{{ formatMoney(row.paid_amount) }}</strong></span>
                    <span>Остаток <strong><span class="symbolika-costing-pill" :class="paymentBadgeClass(row.payment_due)">{{ formatMoney(row.payment_due) }}</span></strong></span>
                  </div>
                </td>
                <td>
                  <button type="button" class="symbolika-costing-mini-button" @click="openDetail('my_orders', row)">Инфо</button>
                </td>
              </tr>
            </tbody>
          </table>
          <div v-if="!visibleMyOrderRows.length" class="symbolika-costing-empty">Нет заказов в работе</div>
        </div>

        <div v-if="activeTab === 'all_orders'" class="symbolika-costing-table-wrap">
          <table class="symbolika-costing-table">
            <colgroup>
              <col style="width: 145px" />
              <col style="width: 190px" />
              <col style="width: 150px" />
              <col style="width: 260px" />
              <col style="width: 150px" />
              <col style="width: 190px" />
              <col style="width: 70px" />
            </colgroup>
            <thead>
              <tr>
                <th>Заказ</th>
                <th>Заказчик</th>
                <th>Менеджер</th>
                <th>Статусы</th>
                <th>Отгрузка</th>
                <th class="symbolika-costing-num">Деньги</th>
                <th>Детали</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in visibleAllOrderRows" :key="row.id" :class="rowStateClass(row)">
                <td>
                  <div class="symbolika-costing-cell-stack">
                    <a class="symbolika-costing-order" :href="orderUrl(row)" @click.prevent="openDetail('all_orders', row)">{{ row.order_number }}</a>
                    <span class="symbolika-costing-cell-meta">{{ formatDate(row.date) }}</span>
                    <input
                      class="symbolika-costing-table-date"
                      :class="[savingWorkClass('orders', row, 'deadline'), deadlineClass(row.deadline)]"
                      type="date"
                      :value="dateInput(row.deadline)"
                      @change="saveOrderField(row, 'deadline', $event.target.value)"
                    />
                  </div>
                </td>
                <td>
                  <div class="symbolika-costing-cell-stack">
                    <a v-if="customerUrl(row)" class="symbolika-costing-entity-link" :href="customerUrl(row)" @click.prevent="openEntityDetail('customer', row)">{{ detailCustomerName(row) }}</a>
                    <span v-else class="symbolika-costing-cell-main">{{ detailCustomerName(row) }}</span>
                    <a v-if="companyUrl(row)" class="symbolika-costing-entity-link symbolika-costing-entity-link-muted" :href="companyUrl(row)" @click.prevent="openEntityDetail('company', row)">{{ detailCompanyName(row) }}</a>
                    <span v-else class="symbolika-costing-cell-meta">{{ detailCompanyName(row) !== '-' ? detailCompanyName(row) : 'Лично' }}</span>
                  </div>
                </td>
                <td>
                  <a v-if="managerUrl(row)" class="symbolika-costing-entity-link" :href="managerUrl(row)" @click.prevent="openEntityDetail('manager', row)">{{ row.manager_name || '-' }}</a>
                  <span v-else class="symbolika-costing-cell-main">{{ row.manager_name || '-' }}</span>
                </td>
                <td>
                  <div class="symbolika-costing-status-stack">
                    <select
                      class="symbolika-costing-table-select"
                      :class="[savingWorkClass('orders', row, 'order_status'), statusToneClass(row.order_status_name)]"
                      :value="row.order_status"
                      @change="saveOrderField(row, 'order_status', $event.target.value)"
                    >
                      <option v-for="status in orderStatuses" :key="status.id" :value="status.id">
                        {{ status.name }}
                      </option>
                    </select>
                    <select
                      class="symbolika-costing-table-select"
                      :class="[savingWorkClass('orders', row, 'office_status'), officeSelectClass(row.office_status)]"
                      :value="row.office_status"
                      @change="saveOrderField(row, 'office_status', $event.target.value)"
                    >
                      <option v-for="status in officeStatusChoices" :key="status.value" :value="status.value">
                        {{ status.text }}
                      </option>
                    </select>
                  </div>
                </td>
                <td>{{ row.shipping_method_name || '-' }}</td>
                <td class="symbolika-costing-num">
                  <div class="symbolika-costing-cell-money">
                    <span>Сумма <strong>{{ formatMoney(row.order_sum) }}</strong></span>
                    <span>Оплачено <strong>{{ formatMoney(row.paid_amount) }}</strong></span>
                    <span>Остаток <strong><span class="symbolika-costing-pill" :class="paymentBadgeClass(row.payment_due)">{{ formatMoney(row.payment_due) }}</span></strong></span>
                  </div>
                </td>
                <td>
                  <button type="button" class="symbolika-costing-mini-button" @click="openDetail('all_orders', row)">
                    <v-icon name="info" small />
                    Инфо
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
          <div v-if="!visibleAllOrderRows.length" class="symbolika-costing-empty">Нет заказов</div>
        </div>

        <div v-if="activeTab === 'deadlines'">
          <div class="symbolika-costing-segments">
            <button
              v-for="bucket in deadlineBucketTabs"
              :key="bucket.id"
              type="button"
              class="symbolika-costing-filter"
              :class="{ 'is-active': activeDeadlineBucket === bucket.id }"
              @click="setDeadlineBucket(bucket.id)"
            >
              {{ bucket.title }}
              <span class="symbolika-costing-segment-count">{{ bucket.count }}</span>
            </button>
          </div>

          <div class="symbolika-costing-table-wrap">
            <table class="symbolika-costing-table symbolika-costing-table-deadlines">
              <colgroup>
                <col style="width: 145px" />
                <col style="width: 190px" />
                <col style="width: 180px" />
                <col style="width: 170px" />
                <col style="width: 190px" />
                <col style="width: 80px" />
              </colgroup>
              <thead>
                <tr>
                  <th>Заказ</th>
                  <th>Клиент</th>
                  <th>Менеджер / статус</th>
                  <th>Отгрузка</th>
                  <th class="symbolika-costing-num">Деньги</th>
                  <th>Детали</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in visibleDeadlineRows" :key="row.id" :class="rowStateClass(row)">
                  <td>
                    <div class="symbolika-costing-cell-stack">
                      <a class="symbolika-costing-order" :href="orderUrl(row)" @click.prevent="openDetail('deadlines', row)">{{ row.order_number }}</a>
                      <span class="symbolika-costing-cell-meta">{{ formatDate(row.date) }}</span>
                      <input
                        class="symbolika-costing-table-date"
                        :class="[savingWorkClass('orders', row, 'deadline'), deadlineClass(row.deadline)]"
                        type="date"
                        :value="dateInput(row.deadline)"
                        @change="saveOrderField(row, 'deadline', $event.target.value)"
                      />
                    </div>
                  </td>
                  <td>
                    <a v-if="customerUrl(row)" class="symbolika-costing-entity-link" :href="customerUrl(row)" @click.prevent="openEntityDetail('customer', row)">{{ row.customer_display || '-' }}</a>
                    <span v-else class="symbolika-costing-cell-main">{{ row.customer_display || '-' }}</span>
                  </td>
                  <td>
                    <div class="symbolika-costing-cell-stack">
                      <a v-if="managerUrl(row)" class="symbolika-costing-entity-link" :href="managerUrl(row)" @click.prevent="openEntityDetail('manager', row)">{{ row.manager_name || '-' }}</a>
                      <span v-else class="symbolika-costing-cell-main">{{ row.manager_name || '-' }}</span>
                      <span class="symbolika-costing-pill" :class="statusBadgeClass(row.order_status_name)">{{ row.order_status_name || '-' }}</span>
                    </div>
                  </td>
                  <td>{{ row.shipping_method_name || '-' }}</td>
                  <td class="symbolika-costing-num">
                    <div class="symbolika-costing-cell-money">
                      <span>Сумма <strong>{{ formatMoney(row.order_sum) }}</strong></span>
                      <span>Оплачено <strong>{{ formatMoney(row.paid_amount) }}</strong></span>
                      <span>Остаток <strong><span class="symbolika-costing-pill" :class="paymentBadgeClass(row.payment_due)">{{ formatMoney(row.payment_due) }}</span></strong></span>
                    </div>
                  </td>
                  <td>
                    <button type="button" class="symbolika-costing-mini-button" @click="openDetail('deadlines', row)">
                      <v-icon name="info" small />
                      Инфо
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>

            <div v-if="!visibleDeadlineRows.length" class="symbolika-costing-empty">Нет заказов в выбранном периоде</div>
          </div>
        </div>

        <div v-if="activeTab === 'queue'" class="symbolika-costing-table-wrap">
          <table class="symbolika-costing-table">
            <colgroup>
              <col style="width: 150px" />
              <col style="width: 210px" />
              <col style="width: 145px" />
              <col style="width: 240px" />
              <col style="width: 92px" />
            </colgroup>
            <thead>
              <tr>
                <th>Задача</th>
                <th>Причина</th>
                <th>Заказ</th>
                <th>Клиент / позиция</th>
                <th>Детали</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="item in queueRows" :key="item.id" :class="rowStateClass(item.row)">
                <td><span class="symbolika-costing-pill" :class="item.filters.includes('overdue') ? 'symbolika-costing-pill-danger' : item.filters.includes('today') ? 'symbolika-costing-pill-orange' : 'symbolika-costing-pill-blue'">{{ item.section }}</span></td>
                <td>{{ item.reason }}</td>
                <td>
                  <div class="symbolika-costing-cell-stack">
                    <a class="symbolika-costing-order" :href="orderUrl(item.row)" @click.prevent="openDetail(item.type, item.row)">{{ item.order_number }}</a>
                    <span class="symbolika-costing-cell-meta">{{ formatDate(item.row?.date) }}</span>
                    <span class="symbolika-costing-date" :class="deadlineClass(item.deadline)"><v-icon :name="deadlineIcon(item.deadline)" small />{{ formatDate(item.deadline) }}</span>
                  </div>
                </td>
                <td>
                  <div class="symbolika-costing-cell-stack">
                    <span class="symbolika-costing-cell-main">{{ item.customer_name || '-' }}</span>
                    <span class="symbolika-costing-product">{{ item.product_name || '-' }}</span>
                    <span class="symbolika-costing-cell-meta">
                      {{ formatQuantity(item.quantity) }} шт. В·
                      <a v-if="managerUrl(item.row)" class="symbolika-costing-entity-link" :href="managerUrl(item.row)" @click.prevent="openEntityDetail('manager', item.row)">{{ item.manager_name || detailManagerName(item.row) }}</a>
                      <span v-else>{{ item.customer_company_name || item.manager_name || '-' }}</span>
                    </span>
                  </div>
                </td>
                <td>
                  <button type="button" class="symbolika-costing-mini-button" @click="openDetail(item.type, item.row)">
                    <v-icon name="open_in_new" small />
                    Открыть
                  </button>
                </td>
              </tr>
            </tbody>
          </table>

          <div v-if="!queueRows.length" class="symbolika-costing-empty">Сейчас нет задач по выбранному фильтру</div>
        </div>

        <div v-if="activeTab === 'costing'" class="symbolika-costing-table-wrap">
          <table class="symbolika-costing-table symbolika-costing-table-compact">
            <colgroup>
              <col style="width: 150px" />
              <col style="width: 230px" />
              <col style="width: 230px" />
              <col style="width: 230px" />
              <col v-if="canSeeCostingTotals" style="width: 170px" />
              <col style="width: 72px" />
            </colgroup>
            <thead>
              <tr>
                <th>Заказ</th>
                <th>Позиция</th>
                <th>Подрядчик 1</th>
                <th>Подрядчик 2</th>
                <th v-if="canSeeCostingTotals">Итог</th>
                <th>Детали</th>
              </tr>
            </thead>

            <tbody v-if="!loading && visibleRows.length">
              <tr v-for="row in visibleRows" :key="row.id">
                <td>
                  <a class="symbolika-costing-order" :href="orderUrl(row)" @click.prevent="openDetail('costing', row)">{{ row.order_number }}</a>
                  <div class="symbolika-costing-subtle">{{ formatDate(row.date) }}</div>
                  <div class="symbolika-costing-subtle">{{ relatedName(row.customer) || '-' }}</div>
                </td>
                <td>
                  <div class="symbolika-costing-product">{{ row.product_name }}</div>
                  <div class="symbolika-costing-subtle">
                    {{ formatQuantity(row.quantity) }} шт. В· {{ formatMoney(row.order_sum) }}
                  </div>
                  <div class="symbolika-costing-subtle">
                    <a v-if="managerUrl(row)" class="symbolika-costing-entity-link" :href="managerUrl(row)" @click.prevent="openEntityDetail('manager', row)">{{ relatedName(row.manager_employee, 'full_name') || detailManagerName(row) }}</a>
                    <span v-else>{{ relatedName(row.manager_employee, 'full_name') || '-' }}</span>
                  </div>
                </td>
                <td>
                  <select
                    class="symbolika-costing-select"
                    :class="savingClass(row, 'contractor_1')"
                    :value="contractorId(row.contractor_1)"
                    @change="saveField(row, 'contractor_1', $event.target.value)"
                  >
                    <option value="">Не выбран</option>
                    <option v-for="contractor in contractors" :key="contractor.id" :value="contractor.id">
                      {{ contractor.name }}
                    </option>
                  </select>
                  <input
                    class="symbolika-costing-input symbolika-costing-num symbolika-costing-stacked-input"
                    :class="savingClass(row, 'contractor_1_cost')"
                    inputmode="decimal"
                    :value="row.contractor_1_cost"
                    @change="saveField(row, 'contractor_1_cost', $event.target.value)"
                  />
                </td>
                <td>
                  <select
                    class="symbolika-costing-select"
                    :class="savingClass(row, 'contractor_2')"
                    :value="contractorId(row.contractor_2)"
                    @change="saveField(row, 'contractor_2', $event.target.value)"
                  >
                    <option value="">Не выбран</option>
                    <option v-for="contractor in contractors" :key="contractor.id" :value="contractor.id">
                      {{ contractor.name }}
                    </option>
                  </select>
                  <input
                    class="symbolika-costing-input symbolika-costing-num symbolika-costing-stacked-input"
                    :class="savingClass(row, 'contractor_2_cost')"
                    inputmode="decimal"
                    :value="row.contractor_2_cost"
                    @change="saveField(row, 'contractor_2_cost', $event.target.value)"
                  />
                </td>
                <td v-if="canSeeCostingTotals">
                  <div class="symbolika-costing-money-stack">
                    <span>Себест. <strong>{{ formatMoney(row.total_cost) }}</strong></span>
                    <span>Прибыль <strong>{{ formatMoney(row.profit_sum) }}</strong></span>
                    <span>Маржа <strong>{{ formatMoney(row.margin_percent) }}%</strong></span>
                  </div>
                </td>
                <td>
                  <button type="button" class="symbolika-costing-mini-button" @click="openDetail('costing', row)">
                    <v-icon name="info" small />
                    Инфо
                  </button>
                </td>
              </tr>
            </tbody>
          </table>

          <div v-if="loading" class="symbolika-costing-empty">Загрузка...</div>
          <div v-else-if="!visibleRows.length" class="symbolika-costing-empty">Нет позиций для заполнения</div>
        </div>

        <div v-if="activeTab === 'payroll'" class="symbolika-costing-expenses">
          <div class="symbolika-costing-subtoolbar">
            <div class="symbolika-costing-segments">
              <button type="button" class="symbolika-costing-filter is-active">Текущий месяц</button>
            </div>
            <button type="button" class="symbolika-costing-button" @click="openExpenseDialog('salary_payment')">
              <v-icon name="payments" small />
              Добавить выплату
            </button>
          </div>
          <div class="symbolika-costing-dashboard symbolika-costing-dashboard-tight">
            <div class="symbolika-costing-card blue">
              <div class="symbolika-costing-card-title">Сумма заказов</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(salaryRows.reduce((sum, row) => sum + parseMoney(row.orders_sum), 0)) }}</div>
              <div class="symbolika-costing-card-note">по менеджерам за месяц</div>
            </div>
            <div class="symbolika-costing-card green">
              <div class="symbolika-costing-card-title">Оплачено</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(salaryRows.reduce((sum, row) => sum + parseMoney(row.paid_orders_sum), 0)) }}</div>
              <div class="symbolika-costing-card-note">база для процентов</div>
            </div>
            <div class="symbolika-costing-card danger">
              <div class="symbolika-costing-card-title">Не оплачено</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(salaryRows.reduce((sum, row) => sum + parseMoney(row.unpaid_orders_sum), 0)) }}</div>
              <div class="symbolika-costing-card-note">не участвует в процентах</div>
            </div>
            <div class="symbolika-costing-card orange">
              <div class="symbolika-costing-card-title">Долг по ЗП</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(salaryRows.reduce((sum, row) => sum + Math.max(parseMoney(row.salary_debt), 0), 0)) }}</div>
              <div class="symbolika-costing-card-note">начислено минус выплаты</div>
            </div>
          </div>

          <div class="symbolika-costing-table-wrap">
            <table class="symbolika-costing-table symbolika-costing-table-compact">
              <colgroup>
                <col style="width: 210px" />
                <col style="width: 100px" />
                <col style="width: 100px" />
                <col style="width: 120px" />
                <col style="width: 120px" />
                <col style="width: 120px" />
                <col style="width: 120px" />
                <col style="width: 120px" />
                <col style="width: 120px" />
                <col style="width: 120px" />
                <col style="width: 110px" />
              </colgroup>
              <thead>
                <tr>
                  <th>Сотрудник</th>
                  <th class="symbolika-costing-num">Оклад</th>
                  <th class="symbolika-costing-num">%</th>
                  <th class="symbolika-costing-num">Заказы</th>
                  <th class="symbolika-costing-num">Оплачено</th>
                  <th class="symbolika-costing-num">Не оплачено</th>
                  <th class="symbolika-costing-num">Проценты</th>
                  <th class="symbolika-costing-num">Начислено</th>
                  <th class="symbolika-costing-num">Выплачено</th>
                  <th class="symbolika-costing-num">Долг</th>
                  <th>Действие</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in visibleSalaryRows" :key="row.id">
                  <td>
                    <div class="symbolika-costing-product">{{ row.employee_name }}</div>
                    <div class="symbolika-costing-subtle">{{ row.position_name || '-' }}</div>
                  </td>
                  <td class="symbolika-costing-num">{{ formatMoney(row.salary_fixed) }}</td>
                  <td class="symbolika-costing-num">{{ formatMoney(row.order_percent) }}%</td>
                  <td class="symbolika-costing-num">{{ formatMoney(row.orders_sum) }}</td>
                  <td class="symbolika-costing-num">{{ formatMoney(row.paid_orders_sum) }}</td>
                  <td class="symbolika-costing-num">{{ formatMoney(row.unpaid_orders_sum) }}</td>
                  <td class="symbolika-costing-num">{{ formatMoney(row.commission_accrued) }}</td>
                  <td class="symbolika-costing-num">{{ formatMoney(row.salary_accrued) }}</td>
                  <td class="symbolika-costing-num">{{ formatMoney(parseMoney(row.salary_paid) + parseMoney(row.advances_paid)) }}</td>
                  <td class="symbolika-costing-num">
                    <span class="symbolika-costing-pill" :class="parseMoney(row.salary_debt) > 0 ? 'symbolika-costing-pill-orange' : 'symbolika-costing-pill-green'">
                      {{ formatMoney(row.salary_debt) }}
                    </span>
                  </td>
                  <td>
                    <button type="button" class="symbolika-costing-mini-button" @click="openExpenseDialog('salary_payment', row.employee)">
                      <v-icon name="payments" small />
                      Выплата
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
            <div v-if="!visibleSalaryRows.length" class="symbolika-costing-empty">Нет сотрудников для расчета</div>
          </div>

          <div class="symbolika-costing-section-title">Выплаты и авансы</div>
          <div class="symbolika-costing-table-wrap">
            <table class="symbolika-costing-table symbolika-costing-table-finance">
              <colgroup>
                <col style="width: 110px" />
                <col style="width: 180px" />
                <col style="width: 120px" />
                <col style="width: 190px" />
                <col style="width: 150px" />
                <col style="width: 260px" />
              </colgroup>
              <thead>
                <tr>
                  <th>Дата</th>
                  <th>Тип</th>
                  <th class="symbolika-costing-num">Сумма</th>
                  <th>Сотрудник</th>
                  <th>Оплата</th>
                  <th>Комментарий</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in visiblePayrollExpenseRows" :key="row.id">
                  <td>{{ formatDate(row.expense_date) }}</td>
                  <td>{{ expenseTypeName(row.expense_type) }}</td>
                  <td class="symbolika-costing-num">{{ formatMoney(row.amount) }}</td>
                  <td>{{ relatedName(row.employee, 'full_name') || '-' }}</td>
                  <td>{{ relatedName(row.payment_type) || '-' }}</td>
                  <td><div class="symbolika-costing-text">{{ row.comment || '-' }}</div></td>
                </tr>
              </tbody>
            </table>
            <div v-if="!visiblePayrollExpenseRows.length" class="symbolika-costing-empty">Выплат и авансов пока нет</div>
          </div>
        </div>

        <div v-if="activeTab === 'expenses'" class="symbolika-costing-expenses">
          <div class="symbolika-costing-subtoolbar">
            <div class="symbolika-costing-segments">
              <button type="button" class="symbolika-costing-filter is-active">Операционные расходы</button>
            </div>
            <button type="button" class="symbolika-costing-button" @click="openExpenseDialog('other')">
              <v-icon name="add_card" small />
              Добавить расход
            </button>
          </div>

          <div class="symbolika-costing-dashboard symbolika-costing-dashboard-tight">
            <div class="symbolika-costing-card orange">
              <div class="symbolika-costing-card-title">Расходы</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(visibleExpenseRows.reduce((sum, row) => sum + parseMoney(row.amount), 0)) }}</div>
              <div class="symbolika-costing-card-note">аренда, доставка, прочее</div>
            </div>
          </div>

          <div class="symbolika-costing-section-title">Журнал операционных расходов</div>
          <div class="symbolika-costing-table-wrap">
            <table class="symbolika-costing-table symbolika-costing-table-finance">
              <colgroup>
                <col style="width: 110px" />
                <col style="width: 180px" />
                <col style="width: 120px" />
                <col style="width: 150px" />
                <col style="width: 320px" />
              </colgroup>
              <thead>
                <tr>
                  <th>Дата</th>
                  <th>Тип</th>
                  <th class="symbolika-costing-num">Сумма</th>
                  <th>Оплата</th>
                  <th>Комментарий</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in visibleExpenseRows" :key="row.id">
                  <td>{{ formatDate(row.expense_date) }}</td>
                  <td>{{ expenseTypeName(row.expense_type) }}</td>
                  <td class="symbolika-costing-num">{{ formatMoney(row.amount) }}</td>
                  <td>{{ relatedName(row.payment_type) || '-' }}</td>
                  <td><div class="symbolika-costing-text">{{ row.comment || '-' }}</div></td>
                </tr>
              </tbody>
            </table>
            <div v-if="!visibleExpenseRows.length" class="symbolika-costing-empty">Операционных расходов пока нет</div>
          </div>
        </div>

        <div v-if="activeTab === 'clients'" class="symbolika-costing-table-wrap">
          <table class="symbolika-costing-table symbolika-costing-table-compact symbolika-costing-table-clients">
            <colgroup>
              <col style="width: 44px" />
              <col style="width: 260px" />
              <col style="width: 220px" />
              <col style="width: 190px" />
              <col style="width: 260px" />
            </colgroup>
            <thead>
              <tr>
                <th></th>
                <th>Клиент</th>
                <th>Компания</th>
                <th>Менеджер</th>
                <th>Деньги</th>
              </tr>
            </thead>
            <tbody>
              <template v-for="row in visibleCustomerDirectoryRows" :key="row.key">
                <tr>
                  <td>
                    <button type="button" class="symbolika-costing-expand" @click="toggleClientRow(row)">
                      <v-icon :name="isClientRowExpanded(row) ? 'remove' : 'add'" small />
                    </button>
                  </td>
                  <td>
                    <button type="button" class="symbolika-costing-link-button" @click="openEntityDetail('customer', { customer: row.id, customer_name: row.name })">
                      {{ row.name || '-' }}
                    </button>
                    <div class="symbolika-costing-subtle">{{ row.orders_count }} {{ pluralRu(row.orders_count, 'заказ', 'заказа', 'заказов') }}</div>
                    <div class="symbolika-costing-subtle">{{ [row.phone, row.email].filter(Boolean).join(' В· ') || '-' }}</div>
                  </td>
                  <td>
                    <button
                      v-if="row.company"
                      type="button"
                      class="symbolika-costing-link-button"
                      @click="openEntityDetail('company', { customer_company: entityId(row.company), customer_company_name: relatedName(row.company) })"
                    >
                      {{ relatedName(row.company) }}
                    </button>
                    <span v-else>Лично</span>
                  </td>
                  <td>
                    <span>{{ customerManagerName(row) }}</span>
                  </td>
                  <td>
                    <div class="symbolika-costing-money-stack">
                      <span>Сумма <strong>{{ formatMoney(row.orders_total_sum) }}</strong></span>
                      <span>Оплачено <strong>{{ formatMoney(row.payments_total_in) }}</strong></span>
                      <span>Баланс <strong><span class="symbolika-costing-pill" :class="balanceBadgeClass(row.balance)">{{ formatMoney(row.balance) }}</span></strong></span>
                    </div>
                  </td>
                </tr>
                <tr v-if="isClientRowExpanded(row)" class="symbolika-costing-expanded-row">
                  <td></td>
                  <td colspan="4">
                    <div v-if="row.orders.length" class="symbolika-costing-client-orders">
                      <button
                        v-for="order in row.orders"
                        :key="order.id"
                        type="button"
                        class="symbolika-costing-client-order"
                        @click="openDetail('finance', order)"
                      >
                        <span class="symbolika-costing-client-order-title">
                          <strong>{{ order.order_number }}</strong>
                          <span>{{ formatDate(order.date) }} В· {{ order.order_status_name || '-' }}</span>
                        </span>
                        <span class="symbolika-costing-cell-money">
                          <span>Сумма <strong>{{ formatMoney(order.order_sum) }}</strong></span>
                          <span>Оплачено <strong>{{ formatMoney(order.paid_amount) }}</strong></span>
                          <span>Остаток <strong>{{ formatMoney(order.payment_due) }}</strong></span>
                        </span>
                      </button>
                    </div>
                    <div v-else class="symbolika-costing-empty symbolika-costing-empty-inline">Заказов пока нет</div>
                  </td>
                </tr>
              </template>
            </tbody>
          </table>
          <div v-if="!visibleCustomerDirectoryRows.length" class="symbolika-costing-empty">Клиентов по текущему доступу пока нет</div>
        </div>

        <div v-if="activeTab === 'companies'" class="symbolika-costing-table-wrap">
          <table class="symbolika-costing-table symbolika-costing-table-compact symbolika-costing-table-clients">
            <colgroup>
              <col style="width: 44px" />
              <col style="width: 280px" />
              <col style="width: 280px" />
              <col style="width: 160px" />
              <col style="width: 260px" />
            </colgroup>
            <thead>
              <tr>
                <th></th>
                <th>Компания</th>
                <th>Клиенты компании</th>
                <th>Заказы</th>
                <th>Деньги</th>
              </tr>
            </thead>
            <tbody>
              <template v-for="row in visibleCompanyDirectoryRows" :key="row.key">
                <tr>
                  <td>
                    <button type="button" class="symbolika-costing-expand" @click="toggleClientRow(row)">
                      <v-icon :name="isClientRowExpanded(row) ? 'remove' : 'add'" small />
                    </button>
                  </td>
                  <td>
                    <button type="button" class="symbolika-costing-link-button" @click="openEntityDetail('company', { customer_company: row.id, customer_company_name: row.name })">
                      {{ row.name || '-' }}
                    </button>
                    <div class="symbolika-costing-subtle">{{ [row.phone, row.email].filter(Boolean).join(' В· ') || '-' }}</div>
                  </td>
                  <td>
                    <div v-if="row.customers.length" class="symbolika-costing-inline-list">
                      <button
                        v-for="customer in row.customers"
                        :key="customer.id"
                        type="button"
                        class="symbolika-costing-link-button"
                        @click="openEntityDetail('customer', { customer: customer.id, customer_name: customer.name })"
                      >
                        {{ customer.name }}
                      </button>
                    </div>
                    <span v-else>-</span>
                  </td>
                  <td>{{ row.orders_count }} {{ pluralRu(row.orders_count, 'заказ', 'заказа', 'заказов') }}</td>
                  <td>
                    <div class="symbolika-costing-money-stack">
                      <span>Сумма <strong>{{ formatMoney(row.orders_total_sum) }}</strong></span>
                      <span>Оплачено <strong>{{ formatMoney(row.payments_total_in) }}</strong></span>
                      <span>Баланс <strong><span class="symbolika-costing-pill" :class="balanceBadgeClass(row.balance)">{{ formatMoney(row.balance) }}</span></strong></span>
                    </div>
                  </td>
                </tr>
                <tr v-if="isClientRowExpanded(row)" class="symbolika-costing-expanded-row">
                  <td></td>
                  <td colspan="4">
                    <div v-if="row.orders.length" class="symbolika-costing-client-orders">
                      <button
                        v-for="order in row.orders"
                        :key="order.id"
                        type="button"
                        class="symbolika-costing-client-order"
                        @click="openDetail('finance', order)"
                      >
                        <span class="symbolika-costing-client-order-title">
                          <strong>{{ order.order_number }}</strong>
                          <span>{{ formatDate(order.date) }} В· {{ order.customer_name || '-' }}</span>
                        </span>
                        <span class="symbolika-costing-cell-money">
                          <span>Сумма <strong>{{ formatMoney(order.order_sum) }}</strong></span>
                          <span>Оплачено <strong>{{ formatMoney(order.paid_amount) }}</strong></span>
                          <span>Остаток <strong>{{ formatMoney(order.payment_due) }}</strong></span>
                        </span>
                      </button>
                    </div>
                    <div v-else class="symbolika-costing-empty symbolika-costing-empty-inline">Заказов пока нет</div>
                  </td>
                </tr>
              </template>
            </tbody>
          </table>
          <div v-if="!visibleCompanyDirectoryRows.length" class="symbolika-costing-empty">Компаний по текущему доступу пока нет</div>
        </div>

        <div v-if="activeTab === 'finance' && moduleSection === 'clients'" class="symbolika-costing-reconciliation">
          <div class="symbolika-costing-subtoolbar symbolika-costing-reconciliation-toolbar">
            <div class="symbolika-costing-reconciliation-filters">
              <select v-model="financeCustomerFilter" class="symbolika-costing-select">
                <option value="">Все клиенты</option>
                <option v-for="customer in customers" :key="customer.id" :value="customer.id">
                  {{ customer.name }}{{ customer.phone ? ' В· ' + customer.phone : '' }}
                </option>
              </select>
              <select v-model="financeCompanyFilter" class="symbolika-costing-select">
                <option value="">Все компании</option>
                <option v-for="company in companies" :key="company.id" :value="company.id">
                  {{ company.name }}
                </option>
              </select>
              <input v-model="financeDateFrom" class="symbolika-costing-input" type="date" title="Дата заказа от" />
              <input v-model="financeDateTo" class="symbolika-costing-input" type="date" title="Дата заказа до" />
              <button type="button" class="symbolika-costing-mini-button" @click="clearFinanceEntityFilters">
                <v-icon name="filter_alt_off" small />
                Сбросить
              </button>
            </div>
          </div>

          <div class="symbolika-costing-dashboard symbolika-costing-dashboard-tight">
            <div class="symbolika-costing-card blue">
              <div class="symbolika-costing-card-title">Заказчики</div>
              <div class="symbolika-costing-card-value">{{ visibleClientRows.length }}</div>
              <div class="symbolika-costing-card-note">клиенты и компании</div>
            </div>
            <div class="symbolika-costing-card green">
              <div class="symbolika-costing-card-title">Оплачено</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(financeSummary.paid_amount) }}</div>
              <div class="symbolika-costing-card-note">поступило</div>
            </div>
            <div class="symbolika-costing-card danger">
              <div class="symbolika-costing-card-title">Остаток</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(financeSummary.payment_due) }}</div>
              <div class="symbolika-costing-card-note">нам должны</div>
            </div>
            <div class="symbolika-costing-card orange">
              <div class="symbolika-costing-card-title">Переплата</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(financeSummary.overpayment) }}</div>
              <div class="symbolika-costing-card-note">к возврату / зачету</div>
            </div>
          </div>

          <div>
            <div class="symbolika-costing-client-grid">
              <article
                v-for="row in visibleClientRows"
                :key="row.key"
                class="symbolika-costing-client-card"
                :class="{ 'has-debt': parseMoney(row.payment_due) > 0 }"
              >
                <div class="symbolika-costing-client-card-head">
                  <div class="symbolika-costing-client-card-title">
                    <div class="symbolika-costing-client-card-kicker">{{ row.customer_company_name ? 'Компания + контакт' : 'Частный клиент' }}</div>
                    <h3>
                      <a v-if="customerUrl(row)" class="symbolika-costing-entity-link" :href="customerUrl(row)" @click.prevent="openEntityDetail('customer', row)">
                        {{ row.customer_name || '-' }}
                      </a>
                      <span v-else>{{ row.customer_name || '-' }}</span>
                    </h3>
                  </div>
                  <span class="symbolika-costing-pill" :class="paymentBadgeClass(row.payment_due)">
                    {{ formatMoney(clientBalance(row)) }}
                  </span>
                </div>

                <div class="symbolika-costing-client-card-meta">
                  <span>
                    <v-icon name="business" small />
                    <a v-if="companyUrl(row)" :href="companyUrl(row)" @click.prevent="openEntityDetail('company', row)">
                      {{ row.customer_company_name || 'Лично' }}
                    </a>
                    <span v-else>{{ row.customer_company_name || 'Лично' }}</span>
                  </span>
                  <span>
                    <v-icon name="person" small />
                    <a v-if="managerUrl(row)" :href="managerUrl(row)" @click.prevent="openEntityDetail('manager', row)">
                      {{ row.manager_name || '-' }}
                    </a>
                    <span v-else>{{ row.manager_name || '-' }}</span>
                  </span>
                  <span>
                    <v-icon name="receipt_long" small />
                    {{ row.orders.length }} {{ pluralRu(row.orders.length, 'заказ', 'заказа', 'заказов') }}
                  </span>
                </div>

                <div class="symbolika-costing-client-card-money">
                  <span>
                    <em>Сумма заказов</em>
                    <strong>{{ formatMoney(row.order_sum) }}</strong>
                  </span>
                  <span>
                    <em>Оплачено</em>
                    <strong>{{ formatMoney(row.paid_amount) }}</strong>
                  </span>
                  <span>
                    <em>Баланс</em>
                    <strong :class="paymentBadgeClass(row.payment_due)">{{ formatMoney(clientBalance(row)) }}</strong>
                  </span>
                </div>

                <div class="symbolika-costing-client-card-actions">
                  <button type="button" class="symbolika-costing-mini-button" @click="toggleClientRow(row)">
                    <v-icon :name="isClientRowExpanded(row) ? 'expand_less' : 'expand_more'" small />
                    {{ isClientRowExpanded(row) ? 'Скрыть заказы' : 'Показать заказы' }}
                  </button>
                  <button type="button" class="symbolika-costing-mini-button" @click="openEntityDetail(row.customer_company_name ? 'company' : 'customer', row)">
                    <v-icon name="account_balance_wallet" small />
                    Сверка
                  </button>
                </div>

                <div v-if="isClientRowExpanded(row)" class="symbolika-costing-client-card-orders">
                  <div
                    v-for="order in row.orders"
                    :key="order.id"
                    class="symbolika-costing-client-order"
                    role="button"
                    tabindex="0"
                    @click="openDetail('finance', order)"
                    @keydown.enter="openDetail('finance', order)"
                  >
                    <span class="symbolika-costing-client-order-title">
                      <a class="symbolika-costing-order" :href="orderUrl(order)" @click.stop.prevent="openDetail('finance', order)">{{ order.order_number }}</a>
                      <span class="symbolika-costing-cell-meta">{{ formatDate(order.date) }} В· {{ order.order_status_name || '-' }}</span>
                    </span>
                    <span class="symbolika-costing-cell-money">
                      <span>Сумма <strong>{{ formatMoney(order.order_sum) }}</strong></span>
                      <span>Остаток <strong>{{ formatMoney(order.payment_due) }}</strong></span>
                    </span>
                  </div>
                </div>
              </article>
            </div>
            <div v-if="!visibleClientRows.length" class="symbolika-costing-empty">Нет клиентов по выбранным фильтрам</div>
          </div>
        </div>

        <div v-if="activeTab === 'finance' && moduleSection !== 'clients'" class="symbolika-costing-reconciliation">
          <div v-if="currentRoleName === 'Менеджер'" class="symbolika-costing-dashboard symbolika-costing-dashboard-tight">
            <div class="symbolika-costing-card blue">
              <div class="symbolika-costing-card-title">Моя выручка</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(managerFinanceStats.orders_sum) }}</div>
              <div class="symbolika-costing-card-note">{{ managerFinanceStats.orders_count }} {{ pluralRu(managerFinanceStats.orders_count, 'заказ', 'заказа', 'заказов') }}</div>
            </div>
            <div class="symbolika-costing-card green">
              <div class="symbolika-costing-card-title">Оплачено</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(managerFinanceStats.paid_orders_sum) }}</div>
              <div class="symbolika-costing-card-note">{{ managerFinanceStats.paid_ratio }}% от выручки</div>
            </div>
            <div class="symbolika-costing-card danger">
              <div class="symbolika-costing-card-title">Не оплачено</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(managerFinanceStats.unpaid_orders_sum) }}</div>
              <div class="symbolika-costing-card-note">деньги еще в работе</div>
            </div>
            <div class="symbolika-costing-card orange">
              <div class="symbolika-costing-card-title">Мой процент</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(managerFinanceStats.commission_total) }}</div>
              <div class="symbolika-costing-card-note">{{ managerFinanceStats.order_percent }}% со всех заказов</div>
            </div>
            <div class="symbolika-costing-card green">
              <div class="symbolika-costing-card-title">Начислено</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(managerFinanceStats.commission_accrued) }}</div>
              <div class="symbolika-costing-card-note">по оплаченным заказам</div>
            </div>
            <div class="symbolika-costing-card blue">
              <div class="symbolika-costing-card-title">Ожидается</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(managerFinanceStats.commission_expected) }}</div>
              <div class="symbolika-costing-card-note">после оплат клиентов</div>
            </div>
            <div class="symbolika-costing-card orange">
              <div class="symbolika-costing-card-title">Выплачено</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(managerFinanceStats.commission_paid) }}</div>
              <div class="symbolika-costing-card-note">зарплата и авансы</div>
            </div>
            <div class="symbolika-costing-card danger">
              <div class="symbolika-costing-card-title">К выплате</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(managerFinanceStats.commission_to_pay) }}</div>
              <div class="symbolika-costing-card-note">{{ managerFinanceMotivation }}</div>
            </div>
          </div>

          <div class="symbolika-costing-subtoolbar symbolika-costing-reconciliation-toolbar">
            <div class="symbolika-costing-segments">
              <button type="button" class="symbolika-costing-filter" :class="{ 'is-active': financeLevel === 'orders' }" @click="setFinanceLevel('orders')">
                По заказам
              </button>
              <button type="button" class="symbolika-costing-filter" :class="{ 'is-active': financeLevel === 'items' }" @click="setFinanceLevel('items')">
                По позициям
              </button>
            </div>

            <div class="symbolika-costing-reconciliation-filters">
              <select v-model="financeCustomerFilter" class="symbolika-costing-select">
                <option value="">Все клиенты</option>
                <option v-for="customer in customers" :key="customer.id" :value="customer.id">
                  {{ customer.name }}{{ customer.phone ? ' В· ' + customer.phone : '' }}
                </option>
              </select>
              <select v-model="financeCompanyFilter" class="symbolika-costing-select">
                <option value="">Все компании</option>
                <option v-for="company in companies" :key="company.id" :value="company.id">
                  {{ company.name }}
                </option>
              </select>
              <input v-model="financeDateFrom" class="symbolika-costing-input" type="date" title="Дата заказа от" />
              <input v-model="financeDateTo" class="symbolika-costing-input" type="date" title="Дата заказа до" />
              <button type="button" class="symbolika-costing-mini-button" @click="clearFinanceEntityFilters">
                <v-icon name="filter_alt_off" small />
                Сбросить
              </button>
            </div>
          </div>

          <div class="symbolika-costing-dashboard symbolika-costing-dashboard-tight">
            <div class="symbolika-costing-card blue">
              <div class="symbolika-costing-card-title">Сумма заказов</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(financeSummary.order_sum) }}</div>
              <div class="symbolika-costing-card-note">
                {{ financeLevel === 'items'
                  ? visibleFinanceItemRowsAllocated.length + ' ' + pluralRu(visibleFinanceItemRowsAllocated.length, 'позиция', 'позиции', 'позиций')
                  : visibleFinanceRows.length + ' ' + pluralRu(visibleFinanceRows.length, 'заказ', 'заказа', 'заказов') }}
              </div>
            </div>
            <div class="symbolika-costing-card green">
              <div class="symbolika-costing-card-title">Оплачено</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(financeSummary.paid_amount) }}</div>
              <div class="symbolika-costing-card-note">поступило от клиента</div>
            </div>
            <div class="symbolika-costing-card danger">
              <div class="symbolika-costing-card-title">Остаток</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(financeSummary.payment_due) }}</div>
              <div class="symbolika-costing-card-note">к оплате</div>
            </div>
            <div class="symbolika-costing-card orange">
              <div class="symbolika-costing-card-title">Переплата</div>
              <div class="symbolika-costing-card-value">{{ formatMoney(financeSummary.overpayment) }}</div>
              <div class="symbolika-costing-card-note">к возврату / зачету</div>
            </div>
          </div>

          <div v-if="financeLevel === 'orders'" class="symbolika-costing-table-wrap">
            <table class="symbolika-costing-table symbolika-costing-table-compact symbolika-costing-table-finance">
              <colgroup>
                <col style="width: 105px" />
                <col style="width: 190px" />
                <col style="width: 145px" />
                <col style="width: 180px" />
                <col style="width: 140px" />
              </colgroup>
              <thead>
                <tr>
                  <th>Заказ</th>
                  <th>Заказчик</th>
                  <th>Менеджер / статус</th>
                  <th>Деньги</th>
                  <th>Итог сверки</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in visibleFinanceRows" :key="row.id" :class="rowStateClass(row)">
                  <td>
                    <a class="symbolika-costing-order" :href="orderUrl(row)" @click.prevent="openDetail('finance', row)">{{ row.order_number }}</a>
                    <div class="symbolika-costing-subtle">{{ formatDate(row.date) }}</div>
                    <span class="symbolika-costing-date" :class="deadlineClass(row.deadline)"><v-icon :name="deadlineIcon(row.deadline)" small />{{ formatDate(row.deadline) }}</span>
                  </td>
                  <td>
                    <div>{{ row.counterparty_name || row.customer_name || '-' }}</div>
                    <div class="symbolika-costing-subtle">
                      {{ [row.customer_name, row.customer_company_name].filter(Boolean).join(' В· ') || '-' }}
                    </div>
                  </td>
                  <td>
                    <div>
                      <a v-if="managerUrl(row)" class="symbolika-costing-entity-link" :href="managerUrl(row)" @click.prevent="openEntityDetail('manager', row)">{{ row.manager_name || '-' }}</a>
                      <span v-else>{{ row.manager_name || '-' }}</span>
                    </div>
                    <span class="symbolika-costing-pill" :class="statusBadgeClass(row.order_status_name)">{{ row.order_status_name || '-' }}</span>
                  </td>
                  <td>
                    <div class="symbolika-costing-money-stack">
                      <span>Сумма <strong>{{ formatMoney(row.order_sum) }}</strong></span>
                      <span>Оплачено <strong>{{ formatMoney(row.paid_amount) }}</strong></span>
                      <span>Остаток <strong><span class="symbolika-costing-pill" :class="paymentBadgeClass(row.payment_due)">{{ formatMoney(row.payment_due) }}</span></strong></span>
                      <span>Переплата <strong>{{ formatMoney(row.overpayment) }}</strong></span>
                    </div>
                  </td>
                  <td>
                    <span class="symbolika-costing-pill" :class="paymentBadgeClass(row.payment_due)">{{ row.reconciliation_result || '-' }}</span>
                  </td>
                </tr>
              </tbody>
            </table>
            <div v-if="!visibleFinanceRows.length" class="symbolika-costing-empty">Нет строк сверки</div>
          </div>

          <div v-if="financeLevel === 'items'" class="symbolika-costing-table-wrap">
            <table class="symbolika-costing-table symbolika-costing-table-compact symbolika-costing-table-finance-items">
              <colgroup>
                <col style="width: 105px" />
                <col style="width: 175px" />
                <col style="width: 210px" />
                <col style="width: 70px" />
                <col style="width: 90px" />
                <col style="width: 105px" />
                <col style="width: 175px" />
              </colgroup>
              <thead>
                <tr>
                  <th>Заказ</th>
                  <th>Заказчик</th>
                  <th>Позиция</th>
                  <th class="symbolika-costing-num">Кол-во</th>
                  <th class="symbolika-costing-num">Цена</th>
                  <th class="symbolika-costing-num">Сумма позиции</th>
                  <th>Оплата заказа</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in visibleFinanceItemRowsAllocated" :key="row.id" :class="rowStateClass(row)">
                  <td>
                    <a class="symbolika-costing-order" :href="orderUrl(row)" @click.prevent="openDetail('finance', row)">{{ row.order_number }}</a>
                    <div class="symbolika-costing-subtle">{{ formatDate(row.date) }}</div>
                    <span class="symbolika-costing-date" :class="deadlineClass(row.deadline)"><v-icon :name="deadlineIcon(row.deadline)" small />{{ formatDate(row.deadline) }}</span>
                  </td>
                  <td>
                    <div>{{ row.counterparty_name || row.customer_name || '-' }}</div>
                    <div class="symbolika-costing-subtle">
                      {{ [row.customer_name, row.customer_company_name].filter(Boolean).join(' В· ') || '-' }}
                    </div>
                  </td>
                  <td>
                    <div class="symbolika-costing-product">{{ row.product_name || '-' }}</div>
                    <div class="symbolika-costing-subtle">
                      <a v-if="managerUrl(row)" class="symbolika-costing-entity-link" :href="managerUrl(row)" @click.prevent="openEntityDetail('manager', row)">{{ row.manager_name || '-' }}</a>
                      <span v-else>{{ row.manager_name || '-' }}</span>
                    </div>
                    <span class="symbolika-costing-pill" :class="statusBadgeClass(row.order_status_name)">{{ row.order_status_name || '-' }}</span>
                  </td>
                  <td class="symbolika-costing-num">{{ formatQuantity(row.quantity) }}</td>
                  <td class="symbolika-costing-num">{{ formatMoney(row.price_per_unit) }}</td>
                  <td class="symbolika-costing-num">{{ formatMoney(row.item_sum) }}</td>
                  <td>
                    <div class="symbolika-costing-money-stack">
                      <span>Заказ <strong>{{ formatMoney(row.order_sum) }}</strong></span>
                      <span>Оплачено <strong>{{ formatMoney(row.paid_amount) }}</strong></span>
                      <span>Остаток <strong><span class="symbolika-costing-pill" :class="paymentBadgeClass(row.payment_due)">{{ formatMoney(row.payment_due) }}</span></strong></span>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
            <div v-if="!visibleFinanceItemRowsAllocated.length" class="symbolika-costing-empty">Нет позиций для сверки</div>
          </div>
        </div>

        <div v-if="isAdminDictionaryTab" class="symbolika-costing-admin">
          <div class="symbolika-costing-admin-head">
            <div>
              <div class="symbolika-costing-subtle">Админка</div>
              <h2>{{ activeAdminConfig?.title }}</h2>
              <p>
                Управление справочником без перехода в системные коллекции Directus.
              </p>
            </div>
            <button
              v-if="!activeAdminConfig?.createDisabled"
              type="button"
              class="symbolika-costing-button symbolika-costing-button-compact"
              @click="startAdminCreate"
            >
              <v-icon name="add" small />
              Добавить
            </button>
          </div>

          <div v-if="adminEditing" class="symbolika-costing-admin-form">
            <label
              v-for="column in activeAdminConfig.columns"
              :key="column.key"
              class="symbolika-costing-label"
              :class="{ 'symbolika-costing-label-wide': column.wide }"
            >
              {{ column.label }}{{ column.required ? ' *' : '' }}
              <input
                v-if="['text', 'number', 'money'].includes(column.type)"
                v-model="adminForm[column.key]"
                class="symbolika-costing-input"
                :type="adminFieldInputType(column)"
                :step="column.type === 'money' ? '0.01' : '1'"
                :disabled="column.readonly"
              />
              <select
                v-else-if="column.type === 'relation'"
                v-model="adminForm[column.key]"
                class="symbolika-costing-select"
                :disabled="column.readonly"
              >
                <option value="">Не выбрано</option>
                <option v-for="option in adminOptions(column.options)" :key="option.id" :value="option.id">
                  {{ adminOptionLabel(option) }}
                </option>
              </select>
              <select
                v-else-if="column.type === 'select'"
                v-model="adminForm[column.key]"
                class="symbolika-costing-select"
                :disabled="column.readonly"
              >
                <option value="">Не выбрано</option>
                <option v-for="choice in column.choices" :key="choice.value" :value="choice.value">
                  {{ choice.text }}
                </option>
              </select>
              <span v-else-if="column.type === 'boolean'" class="symbolika-costing-checkbox-line">
                <input v-model="adminForm[column.key]" type="checkbox" />
                <span>{{ adminForm[column.key] ? 'Да' : 'Нет' }}</span>
              </span>
            </label>

            <div class="symbolika-costing-admin-actions">
              <button type="button" class="symbolika-costing-mini-button" @click="cancelAdminEdit">
                Отмена
              </button>
              <button type="button" class="symbolika-costing-button symbolika-costing-button-compact" :disabled="adminSaving" @click="saveAdminForm">
                {{ adminSaving ? 'Сохраняю...' : 'Сохранить' }}
              </button>
            </div>
          </div>

          <div class="symbolika-costing-table-wrap">
            <table class="symbolika-costing-table symbolika-costing-table-compact symbolika-costing-admin-table">
              <thead>
                <tr>
                  <th v-for="column in activeAdminConfig.columns" :key="column.key">{{ column.label }}</th>
                  <th>Действия</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in activeAdminRows" :key="row.id">
                  <td v-for="column in activeAdminConfig.columns" :key="column.key">
                    <span
                      v-if="column.type === 'boolean'"
                      class="symbolika-costing-pill"
                      :class="row[column.key] ? 'symbolika-costing-pill-green' : ''"
                    >
                      {{ adminDisplayValue(row, column) }}
                    </span>
                    <span v-else>{{ adminDisplayValue(row, column) }}</span>
                  </td>
                  <td>
                    <div class="symbolika-costing-row-actions">
                      <button type="button" class="symbolika-costing-mini-button" @click="startAdminEdit(row)">
                        <v-icon name="edit" small />
                        Изменить
                      </button>
                      <button
                        v-if="activeAdminConfig.columns.some((column) => column.key === 'is_active') && row.is_active !== false"
                        type="button"
                        class="symbolika-costing-mini-button muted"
                        :disabled="adminSaving"
                        @click="archiveAdminRow(row)"
                      >
                        <v-icon name="visibility_off" small />
                        Скрыть
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
            <div v-if="!activeAdminRows.length" class="symbolika-costing-empty">Нет записей в справочнике</div>
          </div>
        </div>

        <div v-if="activeTab === 'contractors' && moduleSection !== 'admin'" class="symbolika-costing-table-wrap">
          <table class="symbolika-costing-table symbolika-costing-table-compact">
            <colgroup>
              <col style="width: 260px" />
              <col style="width: 260px" />
              <col style="width: 220px" />
              <col style="width: 140px" />
            </colgroup>
            <thead>
              <tr>
                <th>Контрагент</th>
                <th>Контакты</th>
                <th>Взаиморасчеты</th>
                <th>Представление</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in visibleContractorRows" :key="row.id">
                <td><strong>{{ row.name }}</strong></td>
                <td>
                  <div>{{ row.contact_name || '-' }}</div>
                  <div class="symbolika-costing-subtle">{{ [row.phone, row.email].filter(Boolean).join(' В· ') || '-' }}</div>
                </td>
                <td>
                  <div class="symbolika-costing-money-stack">
                    <span>Работ <strong>{{ formatMoney(row.items_total_cost) }}</strong></span>
                    <span>Оплачено <strong>{{ formatMoney(row.payments_total_out) }}</strong></span>
                    <span>Баланс <strong>{{ formatMoney(row.balance) }}</strong></span>
                    <span>Мы должны <strong>{{ formatMoney(row.debt_to_contractor) }}</strong></span>
                    <span>Нам должны <strong>{{ formatMoney(row.contractor_debt_to_us) }}</strong></span>
                  </div>
                </td>
                <td>
                  <span class="symbolika-costing-pill" :class="row.has_own_view ? 'symbolika-costing-pill-green' : ''">
                    {{ row.has_own_view ? 'Включено' : 'Нет' }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>

          <div v-if="!visibleContractorRows.length" class="symbolika-costing-empty">Нет контрагентов</div>
        </div>

        <div v-if="activeTab === 'production' || activeTab === 'screen'" class="symbolika-costing-table-wrap">
          <div
            v-if="selectedFor(activeTab).length"
            class="symbolika-costing-bulk"
          >
            <strong>Выбрано: {{ selectedFor(activeTab).length }}</strong>
            <select
              class="symbolika-costing-select"
              style="max-width: 260px"
              @change="bulkSetProductionStatus(activeTab === 'production' ? 'production_work' : 'screen_printing_work', activeTab, $event.target.value)"
            >
              <option value="">Поставить статус...</option>
              <option v-for="status in productionStatuses" :key="status.id" :value="status.id">
                {{ status.name }}
              </option>
            </select>
            <button type="button" class="symbolika-costing-mini-button" @click="clearSelection">
                <v-icon name="playlist_remove" small />
              Снять выбор
            </button>
          </div>
          <table class="symbolika-costing-table symbolika-costing-table-work">
            <colgroup>
              <col style="width: 42px" />
              <col style="width: 140px" />
              <col style="width: 230px" />
              <col style="width: 180px" />
              <col style="width: 190px" />
            </colgroup>
            <thead>
              <tr>
                <th></th>
                <th>Заказ</th>
                <th>Позиция</th>
                <th>ТЗ / макет</th>
                <th>Статус / комментарий</th>
                <th>Детали</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in activeTab === 'production' ? visibleProductionRows : visibleScreenRows"
                :key="row.id"
                :class="rowStateClass(row)"
              >
                <td>
                  <input
                    class="symbolika-costing-check"
                    type="checkbox"
                    :checked="isSelected(activeTab, row)"
                    @change="toggleSelected(activeTab, row, $event.target.checked)"
                  />
                </td>
                <td>
                  <a class="symbolika-costing-order" :href="orderUrl(row)" @click.prevent="openDetail(activeTab, row)">{{ orderNumber(row) }}</a>
                  <div class="symbolika-costing-subtle">{{ formatDate(row.date) }}</div>
                  <span class="symbolika-costing-date" :class="deadlineClass(row.deadline)"><v-icon :name="deadlineIcon(row.deadline)" small />{{ formatDate(row.deadline) }}</span>
                </td>
                <td>
                  <div>{{ relatedName(row.customer) || '-' }}</div>
                  <div class="symbolika-costing-subtle">{{ relatedName(row.customer_company) }}</div>
                  <div class="symbolika-costing-product">{{ row.product_name }}</div>
                  <div class="symbolika-costing-subtle">
                    {{ formatQuantity(row.quantity) }} шт. В·
                    <a v-if="managerUrl(row)" class="symbolika-costing-entity-link" :href="managerUrl(row)" @click.prevent="openEntityDetail('manager', row)">{{ relatedName(row.manager_employee, 'full_name') || detailManagerName(row) }}</a>
                    <span v-else>{{ relatedName(row.manager_employee, 'full_name') || '-' }}</span>
                  </div>
                </td>
                <td>
                  <div class="symbolika-costing-text">{{ row.technical_task_text || '-' }}</div>
                  <a v-if="row.url" class="symbolika-costing-link symbolika-costing-link-inline" :href="row.url" target="_blank" rel="noreferrer">Макет</a>
                  <span v-else class="symbolika-costing-subtle">Макет не указан</span>
                </td>
                <td>
                  <select
                    class="symbolika-costing-select"
                    :class="[savingWorkClass(activeTab === 'production' ? 'production_work' : 'screen_printing_work', row, 'production_status'), statusToneClass(row.production_status)]"
                    :value="contractorId(row.production_status)"
                    @change="saveWorkField(activeTab === 'production' ? 'production_work' : 'screen_printing_work', row, 'production_status', $event.target.value)"
                  >
                    <option value="">Не выбран</option>
                    <option v-for="status in productionStatuses" :key="status.id" :value="status.id">
                      {{ status.name }}
                    </option>
                  </select>
                  <textarea
                    class="symbolika-costing-comment"
                    :class="savingWorkClass(activeTab === 'production' ? 'production_work' : 'screen_printing_work', row, 'production_comment')"
                    :value="row.production_comment"
                    @change="saveWorkField(activeTab === 'production' ? 'production_work' : 'screen_printing_work', row, 'production_comment', $event.target.value)"
                  ></textarea>
                </td>
                <td>
                  <button type="button" class="symbolika-costing-mini-button" @click="openDetail(activeTab, row)">
                    <v-icon name="info" small />
                    Инфо
                  </button>
                </td>
              </tr>
            </tbody>
          </table>

          <div
            v-if="!(activeTab === 'production' ? visibleProductionRows : visibleScreenRows).length"
            class="symbolika-costing-empty"
          >
            Нет позиций
          </div>
        </div>

        <div v-if="activeTab === 'office'" class="symbolika-costing-table-wrap">
            <div class="symbolika-costing-subtoolbar">
              <div class="symbolika-costing-segments">
                <button
                  v-for="bucket in officeBuckets"
                  :key="bucket.id"
                  type="button"
                  class="symbolika-costing-filter"
                  :class="{ 'is-active': officeBucket === bucket.id }"
                  @click="setOfficeBucket(bucket.id)"
                >
                  {{ bucket.title }}
                  <span class="symbolika-costing-segment-count">
                    {{
                      bucket.id === 'issued'
                        ? officeArchiveRows.length
                        : officeIssueRows.filter((row) => bucket.id === 'in_office'
                          ? row.office_status === 'in_office'
                          : row.office_status !== 'in_office' && row.office_status !== 'issued').length
                    }}
                  </span>
                </button>
              </div>

              <label class="symbolika-costing-sort">
                Сортировка
                <select v-model="officeSort" class="symbolika-costing-select">
                  <option v-for="sort in officeSortOptions" :key="sort.id" :value="sort.id">
                    {{ sort.title }}
                  </option>
                </select>
              </label>
            </div>

            <table class="symbolika-costing-table symbolika-costing-table-office">
              <colgroup>
                <col style="width: 42px" />
                <col style="width: 96px" />
                <col style="width: 235px" />
                <col style="width: 150px" />
                <col style="width: 180px" />
                <col style="width: 96px" />
              </colgroup>
              <thead>
                <tr>
                  <th></th>
                  <th>Заказ</th>
                  <th>Клиент / менеджер</th>
                  <th>Статус офиса</th>
                  <th>Финансы</th>
                  <th>Оплата</th>
                </tr>
              </thead>
              <tbody>
                <template v-for="row in visibleOfficeIssueRows" :key="row.id">
                <tr :class="rowStateClass(row)">
                  <td>
                    <button type="button" class="symbolika-costing-expand" @click="toggleOfficeOrder(row)">
                      {{ isOfficeOrderExpanded(row) ? 'в€’' : '+' }}
                    </button>
                  </td>
                  <td><a class="symbolika-costing-order" :href="orderUrl(row)" @click.prevent="openDetail('office', row)">{{ row.order_number }}</a></td>
                  <td>
                    <div>{{ row.customer_name || '-' }}</div>
                    <div class="symbolika-costing-subtle">
                      {{ [row.customer_company_name, row.customer_phone].filter(Boolean).join(' В· ') || '-' }}
                    </div>
                    <div class="symbolika-costing-subtle">
                      <a v-if="managerUrl(row)" class="symbolika-costing-entity-link" :href="managerUrl(row)" @click.prevent="openEntityDetail('manager', row)">{{ row.manager_name || '-' }}</a>
                      <span v-else>{{ row.manager_name || '-' }}</span>
                    </div>
                  </td>
                  <td>
                    <select
                      v-if="officeBucket !== 'issued'"
                      class="symbolika-costing-select"
                      :class="[savingWorkClass('office_issue', row, 'office_status'), officeSelectClass(row.office_status)]"
                      :value="row.office_status"
                      @change="saveOfficeIssueField(row, 'office_status', $event.target.value)"
                    >
                      <option v-for="status in officeStatusChoices" :key="status.value" :value="status.value">
                        {{ status.text }}
                      </option>
                    </select>
                    <span v-else class="symbolika-costing-pill symbolika-costing-pill-green">
                      {{ officeStatusName(row.office_status) }}
                    </span>
                  </td>
                  <td>
                    <div class="symbolika-costing-money-stack">
                      <span>Сумма <strong>{{ formatMoney(row.order_sum) }}</strong></span>
                      <span>Оплачено <strong>{{ formatMoney(row.paid_amount) }}</strong></span>
                      <span>Остаток <strong><span class="symbolika-costing-pill" :class="paymentBadgeClass(row.office_payment_due ?? row.payment_due)">{{ formatMoney(row.office_payment_due ?? row.payment_due) }}</span></strong></span>
                    </div>
                  </td>
                  <td>
                    <button v-if="officeBucket !== 'issued'" type="button" class="symbolika-costing-button symbolika-costing-button-compact" @click="openPaymentDialog(row)">
                      <v-icon name="payments" small />
                      Принять
                    </button>
                    <span v-else class="symbolika-costing-subtle">Архив</span>
                  </td>
                </tr>
                <tr v-if="isOfficeOrderExpanded(row)">
                  <td colspan="6" class="symbolika-costing-position-panel">
                    <div class="symbolika-costing-position-list">
                      <div
                        v-for="item in officePositions(row)"
                        :key="item.id"
                        class="symbolika-costing-position-row"
                      >
                        <div>
                          <div class="symbolika-costing-product">{{ item.product_name }}</div>
                        </div>
                        <div class="symbolika-costing-position-qty">{{ formatQuantity(item.quantity) }} шт.</div>
                        <select
                          v-if="officeBucket !== 'issued'"
                          class="symbolika-costing-select"
                          :class="[savingWorkClass('office_items_in_office', item, 'office_status'), officeSelectClass(item.office_status)]"
                          :value="item.office_status"
                          @change="saveOfficeField(item, $event.target.value)"
                        >
                          <option v-for="status in officeStatusChoices" :key="status.value" :value="status.value">
                            {{ status.text }}
                          </option>
                        </select>
                        <span v-else class="symbolika-costing-pill symbolika-costing-pill-green">
                          {{ officeStatusName(item.office_status) }}
                        </span>
                      </div>
                      <div v-if="!officePositions(row).length" class="symbolika-costing-empty">
                        Нет позиций в заказе
                      </div>
                    </div>
                  </td>
                </tr>
                </template>
            </tbody>
          </table>

          <div v-if="!visibleOfficeIssueRows.length" class="symbolika-costing-empty">Нет заказов в выбранном разделе</div>
        </div>

        <div v-if="expenseDialog" class="symbolika-costing-modal-backdrop" @click.self="closeExpenseDialog">
          <div class="symbolika-costing-modal">
            <div class="symbolika-costing-modal-head">
              <div>
                <div class="symbolika-costing-subtle">Финансы</div>
                <h2>Добавить расход</h2>
              </div>
              <button type="button" class="symbolika-costing-detail-close" @click="closeExpenseDialog">Г—</button>
            </div>
            <div class="symbolika-costing-modal-grid">
              <label class="symbolika-costing-label">
                Дата
                <input v-model="expenseDialog.expense_date" class="symbolika-costing-input" type="date" />
              </label>
              <label class="symbolika-costing-label">
                Тип расхода
                <select v-model="expenseDialog.expense_type" class="symbolika-costing-select">
                  <option v-for="type in expenseTypes" :key="type.value" :value="type.value">
                    {{ type.text }}
                  </option>
                </select>
              </label>
              <label class="symbolika-costing-label">
                Сумма
                <input v-model="expenseDialog.amount" class="symbolika-costing-input symbolika-costing-num" inputmode="decimal" />
              </label>
              <label class="symbolika-costing-label">
                Сотрудник
                <select v-model="expenseDialog.employee" class="symbolika-costing-select">
                  <option value="">Не выбран</option>
                  <option v-for="employee in employees" :key="employee.id" :value="employee.id">
                    {{ employee.full_name }}
                  </option>
                </select>
              </label>
              <label class="symbolika-costing-label">
                Тип оплаты
                <select v-model="expenseDialog.payment_type" class="symbolika-costing-select">
                  <option value="">Не выбран</option>
                  <option v-for="type in paymentTypes" :key="type.id" :value="type.id">
                    {{ type.name }}
                  </option>
                </select>
              </label>
              <label class="symbolika-costing-label">
                Комментарий
                <textarea v-model="expenseDialog.comment" class="symbolika-costing-comment"></textarea>
              </label>
            </div>
            <div class="symbolika-costing-modal-actions">
              <button type="button" class="symbolika-costing-mini-button" @click="closeExpenseDialog">
                Отмена
              </button>
              <button type="button" class="symbolika-costing-button" :disabled="expenseDialog.saving" @click="saveExpense">
                {{ expenseDialog.saving ? 'Сохраняю...' : 'Сохранить расход' }}
              </button>
            </div>
          </div>
        </div>

        <div v-if="newOrderDialog" class="symbolika-costing-modal-backdrop" @click.self="closeNewOrderDialog">
          <div class="symbolika-costing-modal symbolika-costing-order-modal">
            <div class="symbolika-costing-modal-head">
              <div>
                <div class="symbolika-costing-subtle">Рабочий центр</div>
                <h2>Новый заказ</h2>
              </div>
              <button type="button" class="symbolika-costing-detail-close" @click="closeNewOrderDialog">Г—</button>
            </div>

            <div class="symbolika-costing-new-order-grid">
              <label class="symbolika-costing-label">
                Клиент *
                <div class="symbolika-costing-field-with-action">
                  <select v-model="newOrderDialog.customer" class="symbolika-costing-select" :disabled="newOrderDialog.create_customer" @change="syncNewOrderCustomer">
                    <option value="">Выберите клиента</option>
                    <option v-for="customer in customers" :key="customer.id" :value="customer.id">
                      {{ customer.name }}{{ customer.phone ? ' В· ' + customer.phone : '' }}
                    </option>
                  </select>
                  <button type="button" class="symbolika-costing-inline-button" @click="toggleNewOrderCustomer">
                    {{ newOrderDialog.create_customer ? 'Выбрать' : 'Новый' }}
                  </button>
                </div>
              </label>

              <label class="symbolika-costing-label">
                Компания
                <div class="symbolika-costing-field-with-action">
                <select v-model="newOrderDialog.customer_company" class="symbolika-costing-select" :disabled="newOrderDialog.create_company">
                  <option value="">Без компании</option>
                  <option v-for="company in companies" :key="company.id" :value="company.id">
                    {{ company.name }}
                  </option>
                </select>
                <button type="button" class="symbolika-costing-inline-button" @click="toggleNewOrderCompany">
                  {{ newOrderDialog.create_company ? 'Выбрать' : 'Новая' }}
                </button>
                </div>
              </label>

              <label v-if="newOrderDialog.create_company" class="symbolika-costing-label">
                Новая компания *
                <input v-model.trim="newOrderDialog.new_company_name" class="symbolika-costing-input" placeholder="Название компании" />
              </label>

              <label v-if="newOrderDialog.create_company" class="symbolika-costing-label">
                Телефон компании
                <input v-model.trim="newOrderDialog.new_company_phone" class="symbolika-costing-input" placeholder="+7..." />
              </label>

              <label v-if="newOrderDialog.create_company" class="symbolika-costing-label">
                Email компании
                <input v-model.trim="newOrderDialog.new_company_email" class="symbolika-costing-input" placeholder="mail@example.ru" />
              </label>

              <label v-if="newOrderDialog.create_customer" class="symbolika-costing-label">
                Новый клиент *
                <input v-model.trim="newOrderDialog.new_customer_name" class="symbolika-costing-input" placeholder="Имя клиента" />
              </label>

              <label v-if="newOrderDialog.create_customer" class="symbolika-costing-label">
                Телефон
                <input v-model.trim="newOrderDialog.new_customer_phone" class="symbolika-costing-input" placeholder="+7..." />
              </label>

              <label v-if="newOrderDialog.create_customer" class="symbolika-costing-label">
                Email
                <input v-model.trim="newOrderDialog.new_customer_email" class="symbolika-costing-input" placeholder="mail@example.ru" />
              </label>

              <label class="symbolika-costing-label">
                Дата
                <input v-model="newOrderDialog.date" class="symbolika-costing-input" type="date" />
              </label>

              <label class="symbolika-costing-label">
                Срок
                <input v-model="newOrderDialog.deadline" class="symbolika-costing-input" type="date" @change="syncNewOrderDeadline" />
              </label>

              <label class="symbolika-costing-label">
                Способ отгрузки
                <select v-model="newOrderDialog.shipping_method" class="symbolika-costing-select">
                  <option v-for="method in shippingMethodChoices" :key="method.value" :value="method.value">
                    {{ method.text }}
                  </option>
                </select>
              </label>

              <label class="symbolika-costing-label">
                Тип оплаты
                <select v-model="newOrderDialog.payment_type" class="symbolika-costing-select">
                  <option value="">Не выбран</option>
                  <option v-for="type in paymentTypes" :key="type.id" :value="type.id">
                    {{ type.name }}
                  </option>
                </select>
              </label>

              <label class="symbolika-costing-checkbox">
                <input v-model="newOrderDialog.payment_on_receipt" type="checkbox" />
                Оплата при получении
              </label>

              <label class="symbolika-costing-label symbolika-costing-new-order-wide">
                Комментарий к заказу
                <textarea v-model="newOrderDialog.comment" class="symbolika-costing-comment"></textarea>
              </label>
            </div>

            <div class="symbolika-costing-new-order-items-head">
              <h3>Позиции</h3>
              <button type="button" class="symbolika-costing-mini-button" @click="addNewOrderItem">
                <v-icon name="add" small />
                Добавить позицию
              </button>
            </div>

            <div class="symbolika-costing-new-order-items">
              <div
                v-for="(item, index) in newOrderDialog.items"
                :key="index"
                class="symbolika-costing-new-order-item"
              >
                <label class="symbolika-costing-label symbolika-costing-new-order-name">
                  Наименование *
                  <input v-model="item.product_name" class="symbolika-costing-input" />
                </label>

                <label class="symbolika-costing-label">
                  Кол-во *
                  <input v-model="item.quantity" class="symbolika-costing-input symbolika-costing-num" inputmode="decimal" placeholder="0" @focus="clearZeroInput(item, 'quantity')" />
                </label>

                <label class="symbolika-costing-label">
                  Цена
                  <input v-model="item.price_per_unit" class="symbolika-costing-input symbolika-costing-num" inputmode="decimal" placeholder="0" @focus="clearZeroInput(item, 'price_per_unit')" />
                </label>

                <label class="symbolika-costing-label">
                  Срок позиции
                  <input v-model="item.deadline" class="symbolika-costing-input" type="date" />
                </label>

                <label class="symbolika-costing-label">
                  Категория
                  <select v-model="item.product_category" class="symbolika-costing-select" @change="clearNewOrderItemDetails(item)">
                    <option value="">Не выбрана</option>
                    <option v-for="category in productCategories" :key="category.id" :value="category.id">
                      {{ category.name }}
                    </option>
                  </select>
                </label>

                <label class="symbolika-costing-label">
                  Подкатегория
                  <select v-model="item.product_subcategory" class="symbolika-costing-select" :disabled="!filteredSubcategories(item.product_category).length">
                    <option value="">Не выбрана</option>
                    <option v-for="subcategory in filteredSubcategories(item.product_category)" :key="subcategory.id" :value="subcategory.id">
                      {{ subcategory.name }}
                    </option>
                  </select>
                </label>

                <label class="symbolika-costing-label">
                  Вид нанесения
                  <select v-model="item.application_method" class="symbolika-costing-select" :disabled="!filteredApplicationMethods(item.product_category).length">
                    <option value="">Не выбран</option>
                    <option v-for="method in filteredApplicationMethods(item.product_category)" :key="method.id" :value="method.id">
                      {{ method.name }}
                    </option>
                  </select>
                </label>

                <label class="symbolika-costing-label symbolika-costing-new-order-task">
                  ТЗ
                  <textarea v-model="item.technical_task_text" class="symbolika-costing-comment"></textarea>
                </label>

                <label class="symbolika-costing-label symbolika-costing-new-order-url">
                  Макет
                  <input v-model="item.url" class="symbolika-costing-input" placeholder="Ссылка на макет" />
                </label>

                <button
                  type="button"
                  class="symbolika-costing-mini-button symbolika-costing-new-order-remove"
                  :disabled="newOrderDialog.items.length <= 1"
                  @click="removeNewOrderItem(index)"
                >
                  <v-icon name="delete" small />
                  Убрать
                </button>
              </div>
            </div>

            <div class="symbolika-costing-modal-actions">
              <button type="button" class="symbolika-costing-mini-button" @click="closeNewOrderDialog">
                Отмена
              </button>
              <button type="button" class="symbolika-costing-button" :disabled="newOrderDialog.saving" @click="createOrderWithItems">
                <v-icon name="save" small />
                {{ newOrderDialog.saving ? 'Создаем...' : 'Создать заказ' }}
              </button>
            </div>
          </div>
        </div>

        <div v-if="paymentDialog" class="symbolika-costing-modal-backdrop" @click.self="closePaymentDialog">
          <div class="symbolika-costing-modal">
            <h2>Принять оплату</h2>
            <div class="symbolika-costing-modal-grid">
              <div class="symbolika-costing-detail-field">
                <div class="symbolika-costing-detail-label">Заказ</div>
                <div class="symbolika-costing-detail-value">{{ paymentDialog.row.order_number }}</div>
              </div>
              <div class="symbolika-costing-detail-field">
                <div class="symbolika-costing-detail-label">Остаток</div>
                <div class="symbolika-costing-detail-value">{{ formatMoney(paymentDialog.row.office_payment_due ?? paymentDialog.row.payment_due) }}</div>
              </div>
              <label class="symbolika-costing-label">
                Сумма оплаты
                <input
                  v-model="paymentDialog.amount"
                  class="symbolika-costing-input symbolika-costing-num"
                  inputmode="decimal"
                />
              </label>
              <label class="symbolika-costing-label">
                Тип оплаты
                <select v-model="paymentDialog.paymentType" class="symbolika-costing-select">
                  <option value="">Не выбран</option>
                  <option v-for="type in paymentTypes" :key="type.id" :value="type.id">
                    {{ type.name }}
                  </option>
                </select>
              </label>
              <label class="symbolika-costing-label">
                Комментарий
                <textarea v-model="paymentDialog.comment" class="symbolika-costing-comment"></textarea>
              </label>
            </div>
            <div class="symbolika-costing-modal-actions">
              <button type="button" class="symbolika-costing-mini-button" @click="closePaymentDialog">
                Отмена
              </button>
              <button type="button" class="symbolika-costing-button" @click="saveOfficePayment">
                <v-icon name="payments" small />
                Сохранить оплату
              </button>
            </div>
          </div>
        </div>

        <aside v-if="entityDetail" class="symbolika-costing-detail symbolika-costing-entity-detail">
          <div class="symbolika-costing-detail-head">
            <div>
              <div class="symbolika-costing-subtle">{{ entityDetailSubtitle() }}</div>
              <h2>{{ entityDetailTitle() }}</h2>
            </div>
            <button type="button" class="symbolika-costing-detail-close" @click="closeEntityDetail">Г—</button>
          </div>

          <div class="symbolika-costing-detail-grid">
            <div
              v-for="field in entityDetailFields()"
              :key="field.label"
              class="symbolika-costing-detail-field"
              :class="{ 'symbolika-costing-detail-wide': field.value && String(field.value).length > 32 }"
            >
              <div class="symbolika-costing-detail-label">{{ field.label }}</div>
              <div class="symbolika-costing-detail-value">{{ field.value || '-' }}</div>
            </div>
          </div>
        </aside>

        <aside v-if="detail" class="symbolika-costing-detail">
          <div class="symbolika-costing-detail-head">
            <div>
              <div class="symbolika-costing-subtle">Быстрый просмотр</div>
              <h2>{{ orderNumber(detail.row) }}</h2>
            </div>
            <button type="button" class="symbolika-costing-detail-close" @click="closeDetail">Г—</button>
          </div>

          <div v-if="detailIsOrder(detail.row)" class="symbolika-costing-detail-grid">
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Клиент</div>
              <div class="symbolika-costing-detail-value">
                <a v-if="customerUrl(detail.row)" class="symbolika-costing-entity-link" :href="customerUrl(detail.row)" @click.prevent="openEntityDetail('customer', detail.row)">
                  {{ detailCustomerName(detail.row) }}
                </a>
                <span v-else>{{ detailCustomerName(detail.row) }}</span>
              </div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Компания</div>
              <div class="symbolika-costing-detail-value">
                <a v-if="companyUrl(detail.row)" class="symbolika-costing-entity-link" :href="companyUrl(detail.row)" @click.prevent="openEntityDetail('company', detail.row)">
                  {{ detailCompanyName(detail.row) }}
                </a>
                <span v-else>{{ detailCompanyName(detail.row) }}</span>
              </div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Менеджер</div>
              <div class="symbolika-costing-detail-value">
                <a v-if="managerUrl(detail.row)" class="symbolika-costing-entity-link" :href="managerUrl(detail.row)" @click.prevent="openEntityDetail('manager', detail.row)">
                  {{ detailManagerName(detail.row) }}
                </a>
                <span v-else>{{ detailManagerName(detail.row) }}</span>
              </div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Статус заказа</div>
              <div class="symbolika-costing-detail-value">
                <select
                  class="symbolika-costing-table-select"
                  :class="[savingWorkClass('orders', detail.row, 'order_status'), statusToneClass(detailOrderStatus(detail.row))]"
                  :value="detail.row.order_status"
                  @change="saveOrderField(detail.row, 'order_status', $event.target.value)"
                >
                  <option v-for="status in orderStatuses" :key="status.id" :value="status.id">
                    {{ status.name }}
                  </option>
                </select>
              </div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Статус офиса</div>
              <div class="symbolika-costing-detail-value">
                <select
                  class="symbolika-costing-table-select"
                  :class="[savingWorkClass('orders', detail.row, 'office_status'), officeSelectClass(detailOfficeStatus(detail.row))]"
                  :value="detailOfficeStatus(detail.row)"
                  @change="saveOrderField(detail.row, 'office_status', $event.target.value)"
                >
                  <option v-for="status in officeStatusChoices" :key="status.value" :value="status.value">
                    {{ status.text }}
                  </option>
                </select>
              </div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Дата</div>
              <div class="symbolika-costing-detail-value">{{ formatDate(detail.row.date) }}</div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Срок</div>
              <div class="symbolika-costing-detail-value">
                <input
                  class="symbolika-costing-table-date"
                  :class="[savingWorkClass('orders', detail.row, 'deadline'), deadlineClass(detail.row.deadline)]"
                  type="date"
                  :value="dateInput(detail.row.deadline)"
                  @change="saveOrderField(detail.row, 'deadline', $event.target.value)"
                />
              </div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Сумма</div>
              <div class="symbolika-costing-detail-value">{{ formatMoney(detail.row.order_sum) }}</div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Остаток</div>
              <div class="symbolika-costing-detail-value">{{ formatMoney(detail.row.office_payment_due ?? detail.row.payment_due) }}</div>
            </div>
            <div class="symbolika-costing-detail-field symbolika-costing-detail-wide">
              <div class="symbolika-costing-detail-label">Позиции</div>
              <div class="symbolika-costing-detail-value">
                <div v-if="detailPositions(detail.row).length" class="symbolika-costing-detail-items">
                  <div v-for="item in detailPositions(detail.row)" :key="(entityId(item.order_item) || item.id || item.product_name) + ':' + item.product_name" class="symbolika-costing-detail-item">
                    <strong>{{ item.product_name || '-' }}</strong>
                    <div class="symbolika-costing-detail-item-meta">
                      <span>{{ formatQuantity(item.quantity) }} шт.</span>
                      <input
                        class="symbolika-costing-table-date"
                        :class="[savingWorkClass('orders_items', item, 'deadline'), deadlineClass(item.deadline)]"
                        type="date"
                        :value="dateInput(item.deadline)"
                        @change="saveOrderItemField(item, 'deadline', $event.target.value)"
                      />
                      <select
                        class="symbolika-costing-table-select"
                        :class="[savingWorkClass('orders_items', item, 'item_status'), statusToneClass(itemStatusName(item.item_status))]"
                        :value="item.item_status"
                        @change="saveOrderItemField(item, 'item_status', $event.target.value)"
                      >
                        <option v-for="status in itemStatusChoices" :key="status.value" :value="status.value">
                          {{ status.text }}
                        </option>
                      </select>
                      <select
                        class="symbolika-costing-table-select"
                        :class="[savingWorkClass('orders_items', item, 'production_status'), statusToneClass(detailProductionStatus(item))]"
                        :value="entityId(item.production_status)"
                        @change="saveOrderItemField(item, 'production_status', $event.target.value)"
                      >
                        <option value="">Не выбран</option>
                        <option v-for="status in productionStatuses" :key="status.id" :value="status.id">
                          {{ status.name }}
                        </option>
                      </select>
                      <select
                        class="symbolika-costing-table-select"
                        :class="[savingWorkClass('orders_items', item, 'office_status'), officeSelectClass(item.office_status)]"
                        :value="item.office_status"
                        @change="saveOrderItemField(item, 'office_status', $event.target.value)"
                      >
                        <option v-for="status in officeStatusChoices" :key="status.value" :value="status.value">
                          {{ status.text }}
                        </option>
                      </select>
                    </div>
                  </div>
                </div>
                <span v-else>-</span>
              </div>
            </div>
          </div>

          <div v-else class="symbolika-costing-detail-grid">
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Клиент</div>
              <div class="symbolika-costing-detail-value">
                <a v-if="customerUrl(detail.row)" class="symbolika-costing-entity-link" :href="customerUrl(detail.row)" @click.prevent="openEntityDetail('customer', detail.row)">
                  {{ detailCustomerName(detail.row) }}
                </a>
                <span v-else>{{ detailCustomerName(detail.row) }}</span>
              </div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Компания</div>
              <div class="symbolika-costing-detail-value">
                <a v-if="companyUrl(detail.row)" class="symbolika-costing-entity-link" :href="companyUrl(detail.row)" @click.prevent="openEntityDetail('company', detail.row)">
                  {{ detailCompanyName(detail.row) }}
                </a>
                <span v-else>{{ detailCompanyName(detail.row) }}</span>
              </div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Менеджер</div>
              <div class="symbolika-costing-detail-value">
                <a v-if="managerUrl(detail.row)" class="symbolika-costing-entity-link" :href="managerUrl(detail.row)" @click.prevent="openEntityDetail('manager', detail.row)">
                  {{ detailManagerName(detail.row) }}
                </a>
                <span v-else>{{ detailManagerName(detail.row) }}</span>
              </div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Количество</div>
              <div class="symbolika-costing-detail-value">{{ formatQuantity(detail.row.quantity) }} шт.</div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Статус производства</div>
              <div class="symbolika-costing-detail-value">
                <select
                  class="symbolika-costing-table-select"
                  :class="[savingWorkClass('orders_items', detail.row, 'production_status'), statusToneClass(detailProductionStatus(detail.row))]"
                  :value="entityId(detail.row.production_status)"
                  @change="saveOrderItemField(detail.row, 'production_status', $event.target.value)"
                >
                  <option value="">Не выбран</option>
                  <option v-for="status in productionStatuses" :key="status.id" :value="status.id">
                    {{ status.name }}
                  </option>
                </select>
              </div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Статус позиции</div>
              <div class="symbolika-costing-detail-value">
                <select
                  class="symbolika-costing-table-select"
                  :class="[savingWorkClass('orders_items', detail.row, 'item_status'), statusToneClass(itemStatusName(detail.row.item_status))]"
                  :value="detail.row.item_status"
                  @change="saveOrderItemField(detail.row, 'item_status', $event.target.value)"
                >
                  <option v-for="status in itemStatusChoices" :key="status.value" :value="status.value">
                    {{ status.text }}
                  </option>
                </select>
              </div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Статус офиса</div>
              <div class="symbolika-costing-detail-value">
                <select
                  class="symbolika-costing-table-select"
                  :class="[savingWorkClass('orders_items', detail.row, 'office_status'), officeSelectClass(detail.row.office_status)]"
                  :value="detail.row.office_status"
                  @change="saveOrderItemField(detail.row, 'office_status', $event.target.value)"
                >
                  <option v-for="status in officeStatusChoices" :key="status.value" :value="status.value">
                    {{ status.text }}
                  </option>
                </select>
              </div>
            </div>
            <div class="symbolika-costing-detail-field symbolika-costing-detail-wide">
              <div class="symbolika-costing-detail-label">Позиция</div>
              <div class="symbolika-costing-detail-value">{{ detail.row.product_name || '-' }}</div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Дата</div>
              <div class="symbolika-costing-detail-value">{{ formatDate(detail.row.date) }}</div>
            </div>
            <div class="symbolika-costing-detail-field">
              <div class="symbolika-costing-detail-label">Срок</div>
              <div class="symbolika-costing-detail-value">
                <input
                  class="symbolika-costing-table-date"
                  :class="[savingWorkClass('orders_items', detail.row, 'deadline'), deadlineClass(detail.row.deadline)]"
                  type="date"
                  :value="dateInput(detail.row.deadline)"
                  @change="saveOrderItemField(detail.row, 'deadline', $event.target.value)"
                />
              </div>
            </div>
            <div class="symbolika-costing-detail-field symbolika-costing-detail-wide">
              <div class="symbolika-costing-detail-label">ТЗ</div>
              <div class="symbolika-costing-detail-value">{{ detail.row.technical_task_text || '-' }}</div>
            </div>
            <div class="symbolika-costing-detail-field symbolika-costing-detail-wide">
              <div class="symbolika-costing-detail-label">Комментарий производства</div>
              <div class="symbolika-costing-detail-value">{{ detail.row.production_comment || '-' }}</div>
            </div>
            <button type="button" class="symbolika-costing-button symbolika-costing-detail-wide" @click="openParentOrderDetail(detail.row)">
              <v-icon name="open_in_new" small />
              Показать заказ
            </button>
            <a
              v-if="detail.row.url"
              class="symbolika-costing-link symbolika-costing-detail-wide"
              :href="detail.row.url"
              target="_blank"
              rel="noreferrer"
            >
              <v-icon name="attachment" small />
              Открыть макет
            </a>
          </div>
        </aside>
          </main>
        </div>
      </div>
    </private-view>
  `,
};

export function createSymbolikaSectionModule(section) {
  return {
    ...CostingModule,
    data() {
      return {
        ...CostingModule.data(),
        moduleSection: section,
      };
    },
  };
}

export default {
  id: 'symbolika-orders',
  name: 'Заказы',
  icon: 'assignment',
  color: '#F97316',
  routes: [
    {
      path: '',
      component: createSymbolikaSectionModule('orders'),
    },
  ],
};






