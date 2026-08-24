(function () {
  const symbolikaDocumentTitle = '\u0423\u0447\u0435\u0442\u043d\u0430\u044f \u0441\u0438\u0441\u0442\u0435\u043c\u0430 \u0421\u0438\u043c\u0432\u043e\u043b\u0438\u043a\u0438';
  const exactCountPattern = /^\s*(\d+)\s+(?:Elements?|[\u042d\u044d]\u043b\u0435\u043c\u0435\u043d\u0442(?:\u044b|\u043e\u0432)?)\s*$/i;
  const longRussianDatePattern = /(\d{1,2})\s+(\u044f\u043d\u0432\u0430\u0440\u044f|\u0444\u0435\u0432\u0440\u0430\u043b\u044f|\u043c\u0430\u0440\u0442\u0430|\u0430\u043f\u0440\u0435\u043b\u044f|\u043c\u0430\u044f|\u0438\u044e\u043d\u044f|\u0438\u044e\u043b\u044f|\u0430\u0432\u0433\u0443\u0441\u0442\u0430|\u0441\u0435\u043d\u0442\u044f\u0431\u0440\u044f|\u043e\u043a\u0442\u044f\u0431\u0440\u044f|\u043d\u043e\u044f\u0431\u0440\u044f|\u0434\u0435\u043a\u0430\u0431\u0440\u044f)\s+(\d{4})\s*\u0433\.?(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?/gi;
  const monthNumbers = {
    '\u044f\u043d\u0432\u0430\u0440\u044f': '01',
    '\u0444\u0435\u0432\u0440\u0430\u043b\u044f': '02',
    '\u043c\u0430\u0440\u0442\u0430': '03',
    '\u0430\u043f\u0440\u0435\u043b\u044f': '04',
    '\u043c\u0430\u044f': '05',
    '\u0438\u044e\u043d\u044f': '06',
    '\u0438\u044e\u043b\u044f': '07',
    '\u0430\u0432\u0433\u0443\u0441\u0442\u0430': '08',
    '\u0441\u0435\u043d\u0442\u044f\u0431\u0440\u044f': '09',
    '\u043e\u043a\u0442\u044f\u0431\u0440\u044f': '10',
    '\u043d\u043e\u044f\u0431\u0440\u044f': '11',
    '\u0434\u0435\u043a\u0430\u0431\u0440\u044f': '12',
  };
  const calendarTextMap = new Map([
    ['January', '\u042f\u043d\u0432\u0430\u0440\u044c'],
    ['February', '\u0424\u0435\u0432\u0440\u0430\u043b\u044c'],
    ['March', '\u041c\u0430\u0440\u0442'],
    ['April', '\u0410\u043f\u0440\u0435\u043b\u044c'],
    ['May', '\u041c\u0430\u0439'],
    ['June', '\u0418\u044e\u043d\u044c'],
    ['July', '\u0418\u044e\u043b\u044c'],
    ['August', '\u0410\u0432\u0433\u0443\u0441\u0442'],
    ['September', '\u0421\u0435\u043d\u0442\u044f\u0431\u0440\u044c'],
    ['October', '\u041e\u043a\u0442\u044f\u0431\u0440\u044c'],
    ['November', '\u041d\u043e\u044f\u0431\u0440\u044c'],
    ['December', '\u0414\u0435\u043a\u0430\u0431\u0440\u044c'],
    ['Jan', '\u044f\u043d\u0432'],
    ['Feb', '\u0444\u0435\u0432'],
    ['Mar', '\u043c\u0430\u0440'],
    ['Apr', '\u0430\u043f\u0440'],
    ['Jun', '\u0438\u044e\u043d'],
    ['Jul', '\u0438\u044e\u043b'],
    ['Aug', '\u0430\u0432\u0433'],
    ['Sep', '\u0441\u0435\u043d'],
    ['Oct', '\u043e\u043a\u0442'],
    ['Nov', '\u043d\u043e\u044f'],
    ['Dec', '\u0434\u0435\u043a'],
    ['Sunday', '\u0412\u043e\u0441\u043a\u0440\u0435\u0441\u0435\u043d\u044c\u0435'],
    ['Monday', '\u041f\u043e\u043d\u0435\u0434\u0435\u043b\u044c\u043d\u0438\u043a'],
    ['Tuesday', '\u0412\u0442\u043e\u0440\u043d\u0438\u043a'],
    ['Wednesday', '\u0421\u0440\u0435\u0434\u0430'],
    ['Thursday', '\u0427\u0435\u0442\u0432\u0435\u0440\u0433'],
    ['Friday', '\u041f\u044f\u0442\u043d\u0438\u0446\u0430'],
    ['Saturday', '\u0421\u0443\u0431\u0431\u043e\u0442\u0430'],
    ['Sun', '\u0412\u0441'],
    ['Mon', '\u041f\u043d'],
    ['Tue', '\u0412\u0442'],
    ['Wed', '\u0421\u0440'],
    ['Thu', '\u0427\u0442'],
    ['Fri', '\u041f\u0442'],
    ['Sat', '\u0421\u0431'],
  ]);
  const processedNodes = new WeakSet();
  const serviceNavigationCollections = new Set([
    'service_directory',
    'contractors',
    'product_categories',
    'product_subcategories',
    'product_application_methods',
    'product_routing_rules',
    'order_statuses',
    'production_statuses',
    'employees',
    'employee_positions',
    'payment_types',
    'customer_company_links',
    'contractor_payments',
    'business_expenses',
    'inventory_items',
    'inventory_movements',
    'procurement_requests',
  ]);
  const serviceNavigationRoles = new Set([
    'Administrator',
    '\u0423\u043f\u0440\u0430\u0432\u043b\u044f\u044e\u0449\u0438\u0439',
  ]);
  const standardContentRoles = new Set([
    'Administrator',
  ]);
  const hiddenSystemModulePaths = [
    '/admin/insights',
    '/admin/docs',
    '/admin/documentation',
    '/admin/help',
    '/admin/users',
    '/admin/user-directory',
  ];
  const sharedEmployeeModulePaths = [
    '/admin/symbolika-orders',
    '/admin/symbolika-tasks',
    '/admin/symbolika-mail-module',
    '/admin/symbolika-news-module',
    '/admin/symbolika-profile-module',
  ];
  const roleModulePaths = new Map([
    ['Administrator', new Set([
      ...sharedEmployeeModulePaths,
      '/admin/symbolika-production',
      '/admin/symbolika-procurement',
      '/admin/symbolika-management',
      '/admin/symbolika-admin',
    ])],
    ['\u0423\u043f\u0440\u0430\u0432\u043b\u044f\u044e\u0449\u0438\u0439', new Set([
      ...sharedEmployeeModulePaths,
      '/admin/symbolika-production',
      '/admin/symbolika-procurement',
      '/admin/symbolika-management',
    ])],
    ['\u041c\u0435\u043d\u0435\u0434\u0436\u0435\u0440', new Set([
      ...sharedEmployeeModulePaths,
      '/admin/symbolika-procurement',
    ])],
    ['\u041e\u0444\u0438\u0441-\u043c\u0435\u043d\u0435\u0434\u0436\u0435\u0440', new Set([
      ...sharedEmployeeModulePaths,
      '/admin/symbolika-procurement',
    ])],
    ['\u041f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u043e', new Set([
      ...sharedEmployeeModulePaths,
      '/admin/symbolika-production',
      '/admin/symbolika-procurement',
    ])],
    ['\u0428\u0435\u043b\u043a\u043e\u0433\u0440\u0430\u0444\u0438\u044f', new Set([
      ...sharedEmployeeModulePaths,
      '/admin/symbolika-production',
      '/admin/symbolika-procurement',
    ])],
    ['\u0414\u0438\u0437\u0430\u0439\u043d\u0435\u0440', new Set([
      ...sharedEmployeeModulePaths,
      '/admin/symbolika-procurement',
    ])],
    ['\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442', new Set([
      '/admin/symbolika-profile-module',
    ])],
  ]);
  const mobileModuleCatalog = [
    { path: '/admin/symbolika-orders', label: '\u0417\u0430\u043a\u0430\u0437\u044b', icon: 'orders' },
    { path: '/admin/symbolika-tasks', label: '\u0417\u0430\u0434\u0430\u0447\u0438', icon: 'tasks' },
    { path: '/admin/symbolika-production', label: '\u041f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u043e', icon: 'production' },
    { path: '/admin/symbolika-procurement', label: '\u0417\u0430\u043a\u0443\u043f\u043a\u0438', icon: 'procurement' },
    { path: '/admin/symbolika-mail-module', label: '\u041f\u043e\u0447\u0442\u0430', icon: 'mail' },
    { path: '/admin/symbolika-news-module', label: '\u041d\u043e\u0432\u043e\u0441\u0442\u0438', icon: 'news' },
    { path: '/admin/symbolika-management', label: '\u0423\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u0438\u0435', icon: 'management' },
    { path: '/admin/symbolika-admin', label: '\u0410\u0434\u043c\u0438\u043d\u043a\u0430', icon: 'admin' },
    { path: '/admin/symbolika-profile-module', label: '\u041a\u0430\u0431\u0438\u043d\u0435\u0442', icon: 'profile' },
  ];
  const mobileNavigationState = {
    root: null,
    roleName: null,
    signature: '',
    open: false,
  };
  const symbolikaDefaultModulePath = '/admin/symbolika-orders';
  const serviceNavigationState = {
    roleName: null,
    userId: null,
    loading: false,
    pending: null,
  };
  const contentNavigationState = {
    installed: false,
    redirecting: false,
  };
  const tableState = {
    byCollection: new Map(),
    collectionMeta: new Map(),
    loadingMeta: new Set(),
    overrides: new Map(),
    editCell: null,
  };
  const tableInlineEditingEnabled = false;
  const symbolikaAppearanceThemes = new Set(['graphite', 'espresso', 'pearl', 'frost']);

  function applySymbolikaTheme(value) {
    const theme = symbolikaAppearanceThemes.has(value) ? value : 'graphite';
    const isLight = theme === 'pearl' || theme === 'frost';
    document.documentElement.dataset.symbolikaTheme = theme;
    document.documentElement.style.colorScheme = isLight ? 'light' : 'dark';
    if (document.body) document.body.dataset.symbolikaTheme = theme;
    return theme;
  }

  function applyStoredSymbolikaTheme() {
    let theme = 'graphite';
    try {
      theme = localStorage.getItem('symbolika-theme') || theme;
    } catch {}
    return applySymbolikaTheme(theme);
  }

  function symbolikaDefaultPathForRole(roleName) {
    if (roleName === '\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442') return '/admin/symbolika-contractor';
    if (roleName === '\u041f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u043e' || roleName === '\u0428\u0435\u043b\u043a\u043e\u0433\u0440\u0430\u0444\u0438\u044f') return '/admin/symbolika-production';
    return symbolikaDefaultModulePath;
  }

  function applyDocumentLocale() {
    document.documentElement.lang = 'ru-RU';
    document.documentElement.setAttribute('translate', 'no');
    if (document.body) {
      document.body.setAttribute('translate', 'no');
    }
  }

  async function loadCurrentRoleName(force = false) {
    if (!force && serviceNavigationState.roleName) return serviceNavigationState.roleName;
    if (serviceNavigationState.loading && serviceNavigationState.pending) return serviceNavigationState.pending;
    serviceNavigationState.loading = true;
    serviceNavigationState.pending = (async () => {
      try {
        const response = await fetch('/users/me?fields=id,role.name', { credentials: 'include' });
        if (!response.ok) return null;
        const payload = await response.json();
        serviceNavigationState.userId = payload?.data?.id || null;
        serviceNavigationState.roleName = payload?.data?.role?.name || null;
        return serviceNavigationState.roleName;
      } catch (error) {
        console.warn('[Symbolika service navigation]', error);
        return null;
      } finally {
        serviceNavigationState.loading = false;
        serviceNavigationState.pending = null;
      }
    })();
    return serviceNavigationState.pending;
  }

  function mobileNavigationIcon(name) {
    const paths = {
      orders: '<path d="M7 3h10v3h3v15H4V6h3V3Zm2 3h6V5H9v1Zm-3 2v11h12V8H6Zm3 3h6v2H9v-2Zm0 4h6v2H9v-2Z"/>',
      tasks: '<path d="m9 11 2 2 4-5 1.6 1.2-5.4 6.8L7.5 12.4 9 11ZM5 4h14v3h-2V6H7v12h10v-1h2v3H5V4Z"/>',
      production: '<path d="M4 4h6v6H4V4Zm2 2v2h2V6H6Zm8-2h6v6h-6V4Zm2 2v2h2V6h-2ZM4 14h6v6H4v-6Zm2 2v2h2v-2H6Zm9-3h4v2h-4v4h-2v-4h2v-2Zm2 4h3v3h-3v-3Z"/>',
      procurement: '<path d="M7 4h2l1 3h10l-2 8H9L7 6H4V4h3Zm3.7 5 .8 4h5l1-4h-6.8ZM10 17a2 2 0 1 1 0 4 2 2 0 0 1 0-4Zm7 0a2 2 0 1 1 0 4 2 2 0 0 1 0-4Z"/>',
      mail: '<path d="M3 5h18v14H3V5Zm2 2v.4l7 4.7 7-4.7V7H5Zm14 10V9.8l-7 4.7-7-4.7V17h14Z"/>',
      news: '<path d="M4 4h16v16H4V4Zm2 2v12h12V6H6Zm2 2h8v2H8V8Zm0 4h5v2H8v-2Zm0 4h8v1H8v-1Zm7-4h1v2h-1v-2Z"/>',
      management: '<path d="M4 19h16v2H4v-2Zm2-2V9h3v8H6Zm5 0V3h3v14h-3Zm5 0v-6h3v6h-3Z"/>',
      admin: '<path d="M12 2 4 5v6c0 5 3.4 9.7 8 11 4.6-1.3 8-6 8-11V5l-8-3Zm0 2.2L18 6.5V11c0 3.8-2.4 7.6-6 8.8-3.6-1.2-6-5-6-8.8V6.5l6-2.3Zm0 3.3a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5Zm-4 8.8c.8-1.8 2.2-2.8 4-2.8s3.2 1 4 2.8c-1 1-2.4 1.8-4 2.3-1.6-.5-3-1.3-4-2.3Z"/>',
      profile: '<path d="M12 2a5 5 0 1 1 0 10 5 5 0 0 1 0-10Zm0 2a3 3 0 1 0 0 6 3 3 0 0 0 0-6ZM4 22v-3c0-3.3 3.6-5 8-5s8 1.7 8 5v3h-2v-3c0-1.7-2.7-3-6-3s-6 1.3-6 3v3H4Z"/>',
      notifications: '<path d="M12 22a2.4 2.4 0 0 0 2.3-2h-4.6a2.4 2.4 0 0 0 2.3 2Zm7-5-2-2v-4a5 5 0 0 0-4-4.9V4h-2v2.1A5 5 0 0 0 7 11v4l-2 2v1h14v-1Zm-10-.9V11a3 3 0 0 1 6 0v5.1H9Z"/>',
      more: '<path d="M5 10a2 2 0 1 1 0 4 2 2 0 0 1 0-4Zm7 0a2 2 0 1 1 0 4 2 2 0 0 1 0-4Zm7 0a2 2 0 1 1 0 4 2 2 0 0 1 0-4Z"/>',
      close: '<path d="m6.4 5 5.6 5.6L17.6 5 19 6.4 13.4 12l5.6 5.6-1.4 1.4-5.6-5.6L6.4 19 5 17.6l5.6-5.6L5 6.4 6.4 5Z"/>',
    };
    return `<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">${paths[name] || paths.more}</svg>`;
  }

  function mobileNavigationPathIsActive(pathname, route) {
    return pathname === route || pathname.startsWith(`${route}/`);
  }

  function closeMobileAppNavigation() {
    mobileNavigationState.open = false;
    mobileNavigationState.root?.classList.remove('is-open');
    document.documentElement.classList.remove('symbolika-mobile-app-menu-open');
  }

  function openMobileAppNavigation() {
    mobileNavigationState.open = true;
    mobileNavigationState.root?.classList.add('is-open');
    document.documentElement.classList.add('symbolika-mobile-app-menu-open');
  }

  function installMobileAppNavigationEvents(root) {
    root.addEventListener('click', (event) => {
      const routeButton = event.target.closest('[data-symbolika-mobile-route]');
      if (routeButton) {
        const route = routeButton.dataset.symbolikaMobileRoute;
        closeMobileAppNavigation();
        if (route && !mobileNavigationPathIsActive(window.location.pathname, route)) window.location.assign(route);
        return;
      }
      if (event.target.closest('[data-symbolika-mobile-more]')) {
        openMobileAppNavigation();
        return;
      }
      if (event.target.closest('[data-symbolika-mobile-close]') || event.target.classList.contains('symbolika-mobile-app-nav-backdrop')) {
        closeMobileAppNavigation();
      }
    });
  }

  async function applyMobileAppNavigation() {
    if (isAdminLoginPath() || !window.location.pathname.startsWith('/admin/')) {
      mobileNavigationState.root?.remove();
      mobileNavigationState.root = null;
      return;
    }
    const roleName = serviceNavigationState.roleName || await loadCurrentRoleName();
    if (!roleName) return;
    const allowedPaths = roleModulePaths.get(roleName) || new Set(['/admin/symbolika-profile-module']);
    const allowedModules = mobileModuleCatalog.filter((item) => allowedPaths.has(item.path));
    const defaultPath = symbolikaDefaultPathForRole(roleName);
    const preferredPaths = [defaultPath, '/admin/symbolika-tasks', '/admin/symbolika-mail-module'];
    const primaryModules = preferredPaths
      .map((path) => allowedModules.find((item) => item.path === path))
      .filter((item, index, rows) => item && rows.findIndex((row) => row.path === item.path) === index)
      .slice(0, 3);
    const pathname = window.location.pathname;
    const signature = `${roleName}|${pathname}|${allowedModules.map((item) => item.path).join(',')}`;
    if (mobileNavigationState.root && !mobileNavigationState.root.isConnected) {
      mobileNavigationState.root = null;
      mobileNavigationState.signature = '';
    }
    if (!mobileNavigationState.root) {
      const root = document.createElement('div');
      root.className = 'symbolika-mobile-app-nav';
      root.setAttribute('aria-label', '\u041e\u0441\u043d\u043e\u0432\u043d\u0430\u044f \u043c\u043e\u0431\u0438\u043b\u044c\u043d\u0430\u044f \u043d\u0430\u0432\u0438\u0433\u0430\u0446\u0438\u044f');
      document.body.appendChild(root);
      installMobileAppNavigationEvents(root);
      mobileNavigationState.root = root;
    }
    if (mobileNavigationState.signature === signature) return;
    mobileNavigationState.signature = signature;
    mobileNavigationState.roleName = roleName;
    const secondaryActive = allowedModules.some((item) => mobileNavigationPathIsActive(pathname, item.path))
      && !primaryModules.some((item) => mobileNavigationPathIsActive(pathname, item.path));
    const dockItems = primaryModules.map((item) => `
      <button type="button" class="symbolika-mobile-app-nav-item${mobileNavigationPathIsActive(pathname, item.path) ? ' is-active' : ''}" data-symbolika-mobile-route="${item.path}">
        <span class="symbolika-mobile-app-nav-icon">${mobileNavigationIcon(item.icon)}</span><span>${item.label}</span>
      </button>`).join('');
    const sheetItems = allowedModules.map((item) => `
      <button type="button" class="symbolika-mobile-app-menu-item${mobileNavigationPathIsActive(pathname, item.path) ? ' is-active' : ''}" data-symbolika-mobile-route="${item.path}">
        <span class="symbolika-mobile-app-menu-icon">${mobileNavigationIcon(item.icon)}</span>
        <span><strong>${item.label}</strong><small>${mobileNavigationPathIsActive(pathname, item.path) ? '\u041e\u0442\u043a\u0440\u044b\u0442\u043e \u0441\u0435\u0439\u0447\u0430\u0441' : '\u041f\u0435\u0440\u0435\u0439\u0442\u0438 \u0432 \u0440\u0430\u0437\u0434\u0435\u043b'}</small></span>
      </button>`).join('');
    mobileNavigationState.root.innerHTML = `
      <div class="symbolika-mobile-app-nav-backdrop" aria-hidden="true">
        <section class="symbolika-mobile-app-menu" role="dialog" aria-modal="true" aria-label="\u0412\u0441\u0435 \u0440\u0430\u0437\u0434\u0435\u043b\u044b">
          <header><span><small>\u0423\u0447\u0435\u0442\u043d\u0430\u044f \u0441\u0438\u0441\u0442\u0435\u043c\u0430</small><strong>\u0412\u0441\u0435 \u0440\u0430\u0437\u0434\u0435\u043b\u044b</strong></span><button type="button" data-symbolika-mobile-close aria-label="\u0417\u0430\u043a\u0440\u044b\u0442\u044c">${mobileNavigationIcon('close')}</button></header>
          <button type="button" class="symbolika-mobile-app-notifications${mobileNavigationPathIsActive(pathname, '/admin/symbolika-notifications') ? ' is-active' : ''}" data-symbolika-mobile-route="/admin/symbolika-notifications">${mobileNavigationIcon('notifications')}<span><strong>\u0423\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f</strong><small>\u0412\u0441\u0435 \u0441\u043e\u0431\u044b\u0442\u0438\u044f \u0438 \u043d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438 \u043a\u0430\u043d\u0430\u043b\u043e\u0432</small></span></button>
          <div class="symbolika-mobile-app-menu-grid">${sheetItems}</div>
        </section>
      </div>
      <nav class="symbolika-mobile-app-nav-dock">${dockItems}
        <button type="button" class="symbolika-mobile-app-nav-item${secondaryActive || mobileNavigationPathIsActive(pathname, '/admin/symbolika-notifications') ? ' is-active' : ''}" data-symbolika-mobile-more>
          <span class="symbolika-mobile-app-nav-icon">${mobileNavigationIcon('more')}</span><span>\u0415\u0449\u0451</span>
        </button>
      </nav>`;
    if (mobileNavigationState.open) mobileNavigationState.root.classList.add('is-open');
  }

  function getNavigationCollectionFromLink(link) {
    const href = link?.getAttribute?.('href') || '';
    const match = href.match(/\/admin\/content\/([^/?#]+)/);
    return match ? match[1] : null;
  }

  function getNavigationItem(link) {
    return link.closest('.v-list-item, .navigation-item, li, a') || link;
  }

  function isAdminLoginPath(pathname = window.location.pathname) {
    return pathname.includes('/admin/login');
  }

  function isStandardContentPath(pathname = window.location.pathname) {
    return /^\/admin\/content(?:\/|$)/.test(pathname);
  }

  function isContentModuleLink(link) {
    const href = link?.getAttribute?.('href') || '';
    if (!href) return false;
    try {
      const url = new URL(href, window.location.origin);
      return url.pathname === '/admin/content';
    } catch (error) {
      return href === '/admin/content' || href.endsWith('/admin/content');
    }
  }

  function isHiddenSystemModuleLink(link) {
    const href = link?.getAttribute?.('href') || '';
    const isSystemModuleBarItem = Boolean(link?.closest?.('.module-bar'));
    const label = [
      link?.getAttribute?.('aria-label'),
      link?.getAttribute?.('title'),
      link?.textContent,
      link?.innerText,
    ].filter(Boolean).join(' ').toLowerCase();
    const isHiddenByLabel = [
      'insights',
      'analytics',
      '\u0430\u043d\u0430\u043b\u0438\u0442\u0438\u043a\u0430',
      '\u0434\u043e\u043a\u0443\u043c\u0435\u043d\u0442\u0430\u0446\u0438\u044f',
      'аналитика',
      'документация',
      'documentation',
      'docs',
      'help',
      '\u043f\u043e\u043c\u043e\u0449\u044c',
      '\u0441\u043f\u0440\u0430\u0432\u043a\u0430',
      'user directory',
      '\u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u0438',
    ].some((part) => label.includes(part));
    const systemIcon = link?.querySelector?.('[data-icon]')?.getAttribute?.('data-icon') || '';
    const isHiddenHelpIcon = isSystemModuleBarItem && [
      'help',
      'help_outline',
      'question_mark',
      'contact_support',
      'live_help',
    ].includes(systemIcon.toLowerCase());
    // Подписи вроде «Пользователи» используются и внутри рабочих модулей.
    // По тексту скрываем только пункты первого системного меню Directus;
    // остальные ссылки проверяем исключительно по системному URL.
    if (!href) return isHiddenHelpIcon || (isSystemModuleBarItem && isHiddenByLabel);
    try {
      const url = new URL(href, window.location.origin);
      return hiddenSystemModulePaths.some((path) => url.pathname === path || url.pathname.startsWith(`${path}/`))
        || isHiddenHelpIcon
        || (isSystemModuleBarItem && isHiddenByLabel);
    } catch (error) {
      return hiddenSystemModulePaths.some((path) => href === path || href.includes(path))
        || isHiddenHelpIcon
        || (isSystemModuleBarItem && isHiddenByLabel);
    }
  }

  function applyHiddenSystemModules() {
    for (const link of document.querySelectorAll('a[href], button[aria-label], [role="link"], [role="button"], .module-bar a, .module-bar button, nav a, nav button')) {
      if (!isHiddenSystemModuleLink(link)) continue;
      const item = getNavigationItem(link);
      item.dataset.symbolikaSystemNavigation = 'hidden';
      item.style.display = 'none';
    }
  }

  async function applyRoleModuleVisibility() {
    if (isAdminLoginPath()) return;
    const roleName = serviceNavigationState.roleName || await loadCurrentRoleName();
    if (!roleName) return;

    const allowedPaths = roleModulePaths.get(roleName) || new Set(['/admin/symbolika-profile-module']);
    for (const link of document.querySelectorAll('.module-bar a[href], .modules a[href]')) {
      const href = link.getAttribute('href') || '';
      let pathname = href;
      try {
        pathname = new URL(href, window.location.origin).pathname;
      } catch {}
      if (!pathname.startsWith('/admin/symbolika-')) continue;
      const allowedForRole = [...allowedPaths].some((path) => pathname === path || pathname.startsWith(`${path}/`));
      const item = getNavigationItem(link);
      const wasHiddenForRole = item.dataset.symbolikaRoleModule === 'hidden';
      item.dataset.symbolikaRoleModule = allowedForRole ? 'visible' : 'hidden';
      if (!allowedForRole) item.style.display = 'none';
      else if (wasHiddenForRole) item.style.display = '';
    }
  }

  function applyNotificationCenterShortcut() {
    if (isAdminLoginPath()) return;
    for (const button of document.querySelectorAll('.module-bar button')) {
      if (!button.querySelector('[data-icon="notifications"]')) continue;
      button.dataset.symbolikaNotificationCenter = 'true';
      button.setAttribute('aria-label', '\u0426\u0435\u043d\u0442\u0440 \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u0439');
      button.setAttribute('title', '\u0426\u0435\u043d\u0442\u0440 \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u0439');
    }
  }

  function onNotificationCenterShortcutClick(event) {
    const button = event.target?.closest?.('.module-bar button[data-symbolika-notification-center="true"]');
    if (!button) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (window.location.pathname !== '/admin/symbolika-notifications') {
      window.location.assign('/admin/symbolika-notifications');
    }
  }

  async function applyStandardContentVisibility() {
    if (isAdminLoginPath()) return;
    const roleName = serviceNavigationState.roleName || await loadCurrentRoleName();
    if (!roleName) return;
    const canUseStandardContent = standardContentRoles.has(roleName);
    document.documentElement.dataset.symbolikaStandardContent = canUseStandardContent ? 'visible' : 'hidden';

    for (const link of document.querySelectorAll('a[href]')) {
      if (!isContentModuleLink(link)) continue;
      const item = getNavigationItem(link);
      item.dataset.symbolikaStandardContentNavigation = canUseStandardContent ? 'visible' : 'hidden';
      item.style.display = canUseStandardContent ? '' : 'none';
    }

    if (!canUseStandardContent && isStandardContentPath() && !contentNavigationState.redirecting) {
      contentNavigationState.redirecting = true;
      window.location.assign(symbolikaDefaultPathForRole(roleName));
      window.setTimeout(() => {
        contentNavigationState.redirecting = false;
      }, 1200);
    }
  }

  function installStandardContentRouteGuard() {
    if (contentNavigationState.installed) return;
    contentNavigationState.installed = true;

    const schedule = () => {
      window.setTimeout(() => {
        loadCurrentRoleName(true).then(() => {
          applyServiceNavigationVisibility();
          applyStandardContentVisibility();
          applyRoleModuleVisibility();
        });
      }, 0);
    };

    const originalPushState = history.pushState;
    const originalReplaceState = history.replaceState;
    history.pushState = function (...args) {
      const result = originalPushState.apply(this, args);
      schedule();
      return result;
    };
    history.replaceState = function (...args) {
      const result = originalReplaceState.apply(this, args);
      schedule();
      return result;
    };
    window.addEventListener('popstate', schedule);
  }

  async function applyServiceNavigationVisibility() {
    if (isAdminLoginPath()) return;
    const roleName = serviceNavigationState.roleName || await loadCurrentRoleName();
    if (!roleName) return;
    const canSeeServiceNavigation = serviceNavigationRoles.has(roleName);

    for (const link of document.querySelectorAll('a[href*="/admin/content/"]')) {
      const collection = getNavigationCollectionFromLink(link);
      if (!collection || !serviceNavigationCollections.has(collection)) continue;
      const item = getNavigationItem(link);
      item.dataset.symbolikaServiceNavigation = canSeeServiceNavigation ? 'visible' : 'hidden';
      item.style.display = canSeeServiceNavigation ? '' : 'none';
    }
  }

  const tableEditText = {
    hint: '\u041a\u043b\u0438\u043a\u043d\u0438\u0442\u0435, \u0447\u0442\u043e\u0431\u044b \u0438\u0437\u043c\u0435\u043d\u0438\u0442\u044c',
  };
  const choiceSets = {
    office_status: [
      { text: '\u041d\u0435 \u0432 \u043e\u0444\u0438\u0441\u0435', value: 'not_in_office' },
      { text: '\u0412 \u043e\u0444\u0438\u0441\u0435', value: 'in_office' },
      { text: '\u0412\u044b\u0434\u0430\u043d', value: 'issued' },
    ],
    item_status: [
      { text: '\u0416\u0434\u0435\u043c \u043c\u0430\u043a\u0435\u0442', value: 'waiting_layout' },
      { text: '\u0421\u043e\u0433\u043b\u0430\u0441\u043e\u0432\u0430\u043d\u0438\u0435', value: 'approval' },
      { text: '\u0414\u043e\u0440\u0430\u0431\u043e\u0442\u043a\u0430 \u043c\u0430\u043a\u0435\u0442\u0430', value: 'layout_revision' },
      { text: '\u041e\u0442\u043f\u0440\u0430\u0432\u0438\u0442\u044c \u0432 \u0440\u0430\u0431\u043e\u0442\u0443', value: 'send_to_work' },
      { text: '\u041e\u0442\u043f\u0440\u0430\u0432\u043b\u0435\u043d \u0432 \u0440\u0430\u0431\u043e\u0442\u0443', value: 'sent_to_work' },
      { text: '\u0413\u043e\u0442\u043e\u0432', value: 'ready' },
      { text: '\u0414\u043e\u0441\u0442\u0430\u0432\u043b\u0435\u043d', value: '\u0414\u043e\u0441\u0442\u0430\u0432\u043b\u0435\u043d' },
      { text: '\u041e\u0442\u043c\u0435\u043d\u0435\u043d', value: 'cancelled' },
    ],
    order_status: [
      { text: '\u041d\u043e\u0432\u044b\u0439', value: 1 },
      { text: '\u0412 \u0440\u0430\u0431\u043e\u0442\u0435', value: 3 },
      { text: '\u0413\u043e\u0442\u043e\u0432', value: 4 },
      { text: '\u0414\u043e\u0441\u0442\u0430\u0432\u043b\u0435\u043d', value: 5 },
      { text: '\u041e\u0442\u043c\u0435\u043d\u0435\u043d', value: 6 },
      { text: '\u0421\u043e\u0433\u043b\u0430\u0441\u043e\u0432\u0430\u043d\u0438\u0435 \u043c\u0430\u043a\u0435\u0442\u0430', value: 7 },
    ],
    production_status: [
      { text: '\u0412 \u0440\u0430\u0431\u043e\u0442\u0435', value: 4 },
      { text: '\u0413\u043e\u0442\u043e\u0432', value: 5 },
      { text: '\u041e\u0442\u043c\u0435\u043d\u0435\u043d', value: 6 },
      { text: '\u041d\u0435 \u0432 \u0440\u0430\u0431\u043e\u0442\u0435', value: 7 },
      { text: '\u0414\u043e\u0440\u0430\u0431\u043e\u0442\u043a\u0430 \u043c\u0430\u043a\u0435\u0442\u0430', value: 8 },
    ],
    shipping_method: [
      { text: '\u0412\u044b\u0434\u0430\u0447\u0430 \u0432 \u043e\u0444\u0438\u0441\u0435', value: 'office_pickup' },
      { text: '\u0414\u043e\u0441\u0442\u0430\u0432\u043a\u0430 \u043a\u043b\u0438\u0435\u043d\u0442\u0443', value: 'client_delivery' },
      { text: '\u0422\u0440\u0430\u043d\u0441\u043f\u043e\u0440\u0442\u043d\u0430\u044f \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u044f', value: 'transport_company' },
    ],
  };
  const editableTables = {
    orders_items: {
      product_name: { type: 'text', labels: ['\u041d\u0430\u0438\u043c\u0435\u043d\u043e\u0432\u0430\u043d\u0438\u0435'] },
      quantity: { type: 'number', labels: ['\u041a\u043e\u043b\u0438\u0447\u0435\u0441\u0442\u0432\u043e'] },
      unit_price: { type: 'number', labels: ['\u0426\u0435\u043d\u0430 \u0437\u0430 \u0435\u0434\u0438\u043d\u0438\u0446\u0443', '\u0426\u0435\u043d\u0430 \u0437\u0430...'] },
      item_status: { type: 'select', choices: choiceSets.item_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u043f\u043e\u0437\u0438\u0446\u0438\u0438'] },
      production_status: { type: 'select', choices: choiceSets.production_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u043f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u0430'] },
      office_status: { type: 'select', choices: choiceSets.office_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u041e\u0444\u0438\u0441\u0430'] },
      shipping_method: { type: 'select', choices: choiceSets.shipping_method, labels: ['\u0421\u043f\u043e\u0441\u043e\u0431 \u043e\u0442\u0433\u0440\u0443\u0437\u043a\u0438'] },
      technical_spec: { type: 'text', labels: ['\u0422\u0417'] },
    },
    orders: {
      order_status: { type: 'select', choices: choiceSets.order_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u0437\u0430\u043a\u0430\u0437\u0430'] },
      office_status: { type: 'select', choices: choiceSets.office_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u041e\u0444\u0438\u0441\u0430'] },
      shipping_method: { type: 'select', choices: choiceSets.shipping_method, labels: ['\u0421\u043f\u043e\u0441\u043e\u0431 \u043e\u0442\u0433\u0440\u0443\u0437\u043a\u0438'] },
      comment: { type: 'text', labels: ['\u041a\u043e\u043c\u043c\u0435\u043d\u0442\u0430\u0440\u0438\u0439'] },
    },
    office_issue: {
      office_status: { type: 'select', choices: choiceSets.office_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u041e\u0444\u0438\u0441\u0430'] },
      add_payment: { type: 'number', labels: ['\u0414\u043e\u0431\u0430\u0432\u0438\u0442\u044c \u043e\u043f\u043b\u0430\u0442\u0443'] },
    },
    office_orders: {
      office_status: { type: 'select', choices: choiceSets.office_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u041e\u0444\u0438\u0441\u0430'] },
    },
    office_items_in_office: {
      office_status: { type: 'select', choices: choiceSets.office_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u041e\u0444\u0438\u0441\u0430'] },
    },
    office_issue_items: {
      office_status: { type: 'select', choices: choiceSets.office_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u041e\u0444\u0438\u0441\u0430'] },
    },
    production_work: {
      item_status: { type: 'select', choices: choiceSets.item_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u043f\u043e\u0437\u0438\u0446\u0438\u0438'] },
      production_status: { type: 'select', choices: choiceSets.production_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u043f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u0430'] },
    },
    screen_printing_work: {
      item_status: { type: 'select', choices: choiceSets.item_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u043f\u043e\u0437\u0438\u0446\u0438\u0438'] },
      production_status: { type: 'select', choices: choiceSets.production_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u043f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u0430'] },
    },
    contractor_work: {
      item_status: { type: 'select', choices: choiceSets.item_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u043f\u043e\u0437\u0438\u0446\u0438\u0438'] },
      production_status: { type: 'select', choices: choiceSets.production_status, labels: ['\u0421\u0442\u0430\u0442\u0443\u0441 \u043f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u0430'] },
    },
  };
  const inlineWriteTargets = {
    my_orders_in_work: 'orders',
    my_orders_completed: 'orders',
    my_orders_unpaid: 'orders',
    office_issue: 'orders',
    office_issue_items: 'orders_items',
    office_items_in_office: 'orders_items',
    production_work: 'orders_items',
    screen_printing_work: 'orders_items',
    contractor_work: 'orders_items',
  };
  const inlineReadOnlyCollections = new Set([
    'orders_overview',
    'orders_due_today',
    'orders_due_this_week',
    'orders_due_next_week',
    'orders_due_this_month',
    'orders_due_next_month',
    'office_issue_archive',
    'office_issue_archive_items',
  ]);

  function getInlineWriteTarget(collection, field) {
    if (isStatusLikeField(field)) return inlineWriteTargets[collection] || collection;
    return collection;
  }

  function getCollectionConfig(collection) {
    return {
      ...(editableTables[collection] || {}),
      ...(tableState.collectionMeta.get(collection) || {}),
    };
  }

  function isEditableTableCollection(collection) {
    return Boolean(
      tableInlineEditingEnabled
      && collection
      && !collection.startsWith('directus_')
      && !inlineReadOnlyCollections.has(collection)
    );
  }

  function isStatusLikeField(field) {
    return /(^|_)status($|_)/i.test(field || '') || field === 'shipping_method';
  }

  function normalizeChoice(choice) {
    if (!choice || typeof choice !== 'object') return null;
    const value = Object.prototype.hasOwnProperty.call(choice, 'value') ? choice.value : choice.id;
    const text = choice.text ?? choice.name ?? choice.label ?? choice.title ?? String(value ?? '');
    if (value === undefined || value === null || text === '') return null;
    return { text: String(text), value };
  }

  function getFieldLabels(fieldDef) {
    const labels = [fieldDef.field];
    const translations = fieldDef.meta?.translations;
    if (Array.isArray(translations)) {
      for (const translation of translations) {
        if (translation?.translation) labels.push(translation.translation);
      }
    }
    return labels;
  }

  async function loadM2OChoices(table) {
    if (!table) return [];
    try {
      const response = await fetch(`/items/${table}?limit=-1&fields=id,name`, { credentials: 'include' });
      if (!response.ok) return [];
      const payload = await response.json();
      return (payload?.data || []).map((row) => normalizeChoice(row)).filter(Boolean);
    } catch (error) {
      console.warn('[Symbolika status choices]', error);
      return [];
    }
  }

  async function loadCollectionMeta(collection) {
    if (!isEditableTableCollection(collection)) return;
    if (tableState.collectionMeta.has(collection) || tableState.loadingMeta.has(collection)) return;

    tableState.loadingMeta.add(collection);
    try {
      const response = await fetch(`/fields/${collection}`, { credentials: 'include' });
      if (!response.ok) return;
      const payload = await response.json();
      const config = {};

      for (const fieldDef of payload?.data || []) {
        const field = fieldDef.field;
        const meta = fieldDef.meta || {};
        if (!isStatusLikeField(field)) continue;

        const optionChoices = Array.isArray(meta.options?.choices)
          ? meta.options.choices.map((choice) => normalizeChoice(choice)).filter(Boolean)
          : [];

        if (optionChoices.length) {
          config[field] = { type: 'select', choices: optionChoices, labels: getFieldLabels(fieldDef) };
          continue;
        }

        const special = Array.isArray(meta.special) ? meta.special : [];
        if (meta.interface === 'select-dropdown-m2o' || special.includes('m2o')) {
          const choices = await loadM2OChoices(fieldDef.schema?.foreign_key_table);
          if (choices.length) config[field] = { type: 'select', choices, labels: getFieldLabels(fieldDef) };
        }
      }

      tableState.collectionMeta.set(collection, config);
      window.requestAnimationFrame(enhanceInlineTables);
    } catch (error) {
      console.warn('[Symbolika collection meta]', error);
    } finally {
      tableState.loadingMeta.delete(collection);
    }
  }

  function installTableFetchCapture() {
    if (window.__symbolikaTableFetchCaptureInstalled) return;
    window.__symbolikaTableFetchCaptureInstalled = true;
    const originalFetch = window.fetch.bind(window);

    window.fetch = async (...args) => {
      const response = await originalFetch(...args);
      try {
        const requestUrl = typeof args[0] === 'string' ? args[0] : args[0]?.url;
        const patchedResponse = await patchTableResponse(requestUrl, response);
        captureTableResponse(requestUrl, patchedResponse);
        return patchedResponse;
      } catch (error) {
        console.warn('[Symbolika table capture]', error);
      }
      return response;
    };
  }

  async function patchTableResponse(requestUrl, response) {
    if (!requestUrl || !response?.ok) return response;

    const url = new URL(requestUrl, window.location.origin);
    const match = url.pathname.match(/^\/items\/([^/]+)$/);
    if (!match) return response;

    const collection = match[1];
    if (!isEditableTableCollection(collection)) return response;
    if (!url.searchParams.has('limit') || !url.searchParams.has('fields')) return response;
    if (url.searchParams.has('aggregate[countDistinct]')) return response;

    const payload = await response.clone().json().catch(() => null);
    if (!Array.isArray(payload?.data)) return response;

    const patchedPayload = {
      ...payload,
      data: applyInlineOverrides(collection, payload.data),
    };

    return new Response(JSON.stringify(patchedPayload), {
      status: response.status,
      statusText: response.statusText,
      headers: response.headers,
    });
  }

  function getOverrideKey(collection, primaryKey, field) {
    return `${collection}:${primaryKey}:${field}`;
  }

  function setInlineOverride(collection, primaryKey, field, value) {
    tableState.overrides.set(getOverrideKey(collection, primaryKey, field), {
      value,
      expiresAt: Date.now() + 120000,
    });
  }

  function clearInlineOverride(collection, primaryKey, field) {
    tableState.overrides.delete(getOverrideKey(collection, primaryKey, field));
  }

  function getInlineOverride(collection, primaryKey, field) {
    const key = getOverrideKey(collection, primaryKey, field);
    const override = tableState.overrides.get(key);
    if (!override) return undefined;
    if (override.expiresAt < Date.now()) {
      tableState.overrides.delete(key);
      return undefined;
    }
    return override.value;
  }

  function applyInlineOverrides(collection, rows) {
    return rows.map((row) => {
      if (!row?.id) return row;
      const next = { ...row };
      for (const field of Object.keys(getCollectionConfig(collection))) {
        const override = getInlineOverride(collection, row.id, field);
        if (override !== undefined) next[field] = override;
      }
      return next;
    });
  }

  function applyVisibleInlineOverrides() {
    for (const cell of document.querySelectorAll('.symbolika-inline-editable-cell')) {
      if (cell.classList.contains('is-editing')) continue;

      const collection = cell.dataset.symbolikaCollection;
      const field = cell.dataset.symbolikaField;
      const primaryKey = cell.dataset.symbolikaPrimaryKey;
      const meta = collection && field ? getCollectionConfig(collection)[field] : null;
      if (!collection || !field || !primaryKey || !meta) continue;

      const override = getInlineOverride(collection, primaryKey, field);
      if (override !== undefined) updateCellDisplay(cell, meta, override);
    }
  }

  function repeatInlineOverride() {
    [0, 120, 350, 800, 1600, 3200].forEach((delay) => {
      window.setTimeout(() => {
        enhanceInlineTables();
        applyVisibleInlineOverrides();
      }, delay);
    });
  }

  async function captureTableResponse(requestUrl, response) {
    if (!requestUrl || !response?.ok) return;
    const url = new URL(requestUrl, window.location.origin);
    const match = url.pathname.match(/^\/items\/([^/]+)$/);
    if (!match) return;
    const collection = match[1];
    if (!isEditableTableCollection(collection)) return;
    loadCollectionMeta(collection);
    if (!url.searchParams.has('limit') || !url.searchParams.has('fields')) return;
    if (url.searchParams.has('aggregate[countDistinct]')) return;

    const payload = await response.clone().json();
    if (!Array.isArray(payload?.data)) return;
    tableState.byCollection.set(collection, {
      url: url.toString(),
      rows: applyInlineOverrides(collection, payload.data),
      capturedAt: Date.now(),
    });
    window.requestAnimationFrame(enhanceInlineTables);
  }

  function pluralPosition(count) {
    const abs = Math.abs(Number(count));
    const mod10 = abs % 10;
    const mod100 = abs % 100;

    if (mod10 === 1 && mod100 !== 11) return '\u043f\u043e\u0437\u0438\u0446\u0438\u044f';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return '\u043f\u043e\u0437\u0438\u0446\u0438\u0438';
    return '\u043f\u043e\u0437\u0438\u0446\u0438\u0439';
  }

  function updateTextNode(node) {
    if (!node.nodeValue) return;

    let nextText = node.nodeValue;
    nextText = translateCalendarText(nextText);
    const match = nextText.match(exactCountPattern);
    if (match) {
      const count = Number(match[1]);
      nextText = `${count} ${pluralPosition(count)}`;
    }

    nextText = formatVisibleDates(nextText);
    if (node.nodeValue !== nextText) node.nodeValue = nextText;
  }

  function translateCalendarText(text) {
    const raw = String(text || '');
    const trimmed = raw.trim();
    if (!trimmed) return text;

    const translated = calendarTextMap.get(trimmed);
    if (translated) return raw.replace(trimmed, translated);

    return raw.replace(/\b(January|February|March|April|May|June|July|August|September|October|November|December)\b/g, (match) => {
      return calendarTextMap.get(match) || match;
    });
  }

  function normalizeCalendarWeekdays(root) {
    if (!root || root.nodeType !== Node.ELEMENT_NODE) return;

    const sundayFirst = ['Sun', '\u0412\u0441', '\u0412\u0441.'];
    const weekdayValues = new Set([
      'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat',
      '\u0412\u0441', '\u041f\u043d', '\u0412\u0442', '\u0421\u0440', '\u0427\u0442', '\u041f\u0442', '\u0421\u0431',
      '\u0412\u0441.', '\u041f\u043d.', '\u0412\u0442.', '\u0421\u0440.', '\u0427\u0442.', '\u041f\u0442.', '\u0421\u0431.',
    ]);
    const labels = ['\u041f\u043d', '\u0412\u0442', '\u0421\u0440', '\u0427\u0442', '\u041f\u0442', '\u0421\u0431', '\u0412\u0441'];
    const weekdayParents = new Set();
    const dayParents = new Set();

    const calendarRoots = root.matches?.('.v-date-picker, [class*="date-picker"], [role="dialog"], .v-overlay-container')
      ? [root]
      : Array.from(root.querySelectorAll?.('.v-date-picker, [class*="date-picker"], [role="dialog"], .v-overlay-container') || []);

    for (const calendarRoot of calendarRoots) {
      const nodes = Array.from(calendarRoot.querySelectorAll?.('*') || []);
      for (const node of nodes) {
        const children = Array.from(node.children || []);
        if (children.length < 7) continue;

        const textChildren = children.filter((child) => child.textContent?.trim());
        for (let index = 0; index <= textChildren.length - 7; index += 1) {
          const group = textChildren.slice(index, index + 7);
          const values = group.map((child) => child.textContent.trim());
          if (values.every((value) => weekdayValues.has(value))) {
            weekdayParents.add(node);
            break;
          }
        }
      }
    }

    for (const node of Array.from(root.querySelectorAll?.('.v-date-picker-month__weekday, [class*="weekday"]') || [])) {
      const text = node.textContent?.trim();
      if (weekdayValues.has(text) && node.parentElement) weekdayParents.add(node.parentElement);
    }

    for (const parent of weekdayParents) {
      const nodes = Array.from(parent.children).filter((node) => node.textContent?.trim());
      if (nodes.length < 7) continue;
      const firstSeven = nodes.slice(0, 7);
      const raw = firstSeven.map((node) => node.textContent.trim());
      if (sundayFirst.includes(raw[0])) {
        parent.append(...firstSeven.slice(1), firstSeven[0]);
      }
      Array.from(parent.children).slice(0, 7).forEach((node, index) => {
        node.textContent = labels[index];
        node.setAttribute('aria-label', labels[index]);
      });
      parent.dataset.symbolikaMondayFirst = 'true';
    }

    for (const node of Array.from(root.querySelectorAll?.('.v-date-picker-month__day, [class*="date-picker-month"] button, [class*="date-picker"] [role="gridcell"]') || [])) {
      if (node.parentElement) dayParents.add(node.parentElement);
    }

    for (const parent of dayParents) {
      if (parent.dataset.symbolikaMondayFirst === 'true') continue;
      const days = Array.from(parent.children).filter((node) => {
        return node.classList?.contains('v-date-picker-month__day')
          || node.querySelector?.('button')
          || node.getAttribute?.('role') === 'gridcell'
          || node.matches?.('button');
      });
      if (days.length < 7 || days.length % 7 !== 0) continue;
      const reordered = [];
      for (let index = 0; index < days.length; index += 7) {
        const week = days.slice(index, index + 7);
        reordered.push(...week.slice(1), week[0]);
      }
      parent.append(...reordered);
      parent.dataset.symbolikaMondayFirst = 'true';
    }
  }

  function formatVisibleDates(text) {
    if (!text || !longRussianDatePattern.test(text)) {
      longRussianDatePattern.lastIndex = 0;
      return text;
    }

    longRussianDatePattern.lastIndex = 0;
    return text.replace(longRussianDatePattern, (_match, day, monthName, year) => {
      const month = monthNumbers[String(monthName).toLowerCase()];
      if (!month) return _match;
      return `${String(day).padStart(2, '0')}.${month}.${String(year).slice(-2)} \u0433.`;
    });
  }

  function updateDateInputs(root) {
    if (!root || root.nodeType !== Node.ELEMENT_NODE) return;

    const inputs = root.matches?.('input')
      ? [root]
      : Array.from(root.querySelectorAll?.('input') || []);

    for (const input of inputs) {
      if (input === document.activeElement) continue;
      if (input.type === 'hidden' || input.type === 'password' || input.type === 'search') continue;
      const field = input.closest('.field');
      const isReadOnlyDisplay = input.readOnly
        || input.disabled
        || Boolean(input.closest('.disabled, .readonly, .non-editable'))
        || field?.classList.contains('readonly')
        || field?.classList.contains('disabled');
      if (!isReadOnlyDisplay) continue;

      const nextValue = formatVisibleDates(input.value);
      if (nextValue && nextValue !== input.value) input.value = nextValue;
    }
  }

  function updateCountLabels(root) {
    if (!root || root.nodeType !== Node.ELEMENT_NODE) return;

    const labels = root.matches?.('span.label')
      ? [root]
      : Array.from(root.querySelectorAll?.('span.label') || []);

    for (const label of labels) {
      const match = label.textContent && label.textContent.match(exactCountPattern);
      if (!match) continue;

      const count = Number(match[1]);
      const nextText = `${count} ${pluralPosition(count)}`;
      if (label.textContent !== nextText) label.textContent = nextText;
    }
  }

  function walk(root) {
    if (!root || processedNodes.has(root)) return;

    if (root.nodeType === Node.TEXT_NODE) {
      updateTextNode(root);
      return;
    }

    if (root.nodeType !== Node.ELEMENT_NODE && root.nodeType !== Node.DOCUMENT_FRAGMENT_NODE) return;
    if (root.nodeType === Node.ELEMENT_NODE && root.closest('script, style, textarea, input')) return;

    updateCountLabels(root);
    updateDateInputs(root);
    normalizeCalendarWeekdays(root);

    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let node = walker.nextNode();
    while (node) {
      updateTextNode(node);
      node = walker.nextNode();
    }
  }

  function scan() {
    applySymbolikaBranding();
    applyStoredSymbolikaTheme();
    applyDocumentLocale();
    updateCountLabels(document.body);
    normalizeCalendarWeekdays(document.body);
    walk(document.body);
  }

  function applySymbolikaBranding() {
    if (document.title !== symbolikaDocumentTitle) document.title = symbolikaDocumentTitle;
    document.documentElement.setAttribute('data-symbolika-branding', 'ready');
  }

  function isContentItemPage() {
    const match = window.location.pathname.match(/^\/admin\/content\/([^/]+)\/([^/?#]+)/);
    return Boolean(match && match[2] && match[2] !== '+');
  }

  function getRouteItem() {
    const match = window.location.pathname.match(/^\/admin\/content\/([^/]+)\/([^/?#]+)/);
    if (!match) return {};
    return { collection: match[1], primaryKey: match[2] };
  }

  function getFieldControl(fieldElement) {
    if (!fieldElement) return null;
    return fieldElement.querySelector('[collection][field][primary-key], .v-select[collection], .v-input[collection]');
  }

  function isStaticReadonlyFieldTarget(target) {
    return target instanceof HTMLElement
      && Boolean(target.closest('[data-collection="orders_items"][data-field="production_status"]'));
  }

  function onStaticReadonlyFieldEvent(event) {
    if (!isStaticReadonlyFieldTarget(event.target)) return;
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
  }

  function getListCollection() {
    const match = window.location.pathname.match(/^\/admin\/content\/([^/?#]+)\/?$/);
    if (!match) return null;
    return match[1];
  }

  function normalizeText(text) {
    return String(text || '').replace(/\s+/g, ' ').trim();
  }

  function getHeaderLabels(table) {
    return Array.from(table.querySelectorAll('thead th')).map((th) => normalizeText(th.textContent));
  }

  function getFieldByHeader(collection, headerText) {
    const normalized = normalizeText(headerText);
    const config = getCollectionConfig(collection);
    for (const [field, meta] of Object.entries(config)) {
      if ((meta.labels || []).some((label) => normalized === normalizeText(label) || normalized.startsWith(normalizeText(label)))) {
        return field;
      }
    }
    return null;
  }

  function getCellField(collection, cell, headerText) {
    const marker = cell.querySelector(`[collection="${collection}"][field], [collection][field]`);
    const markerCollection = marker?.getAttribute('collection');
    const markerField = marker?.getAttribute('field');
    if (markerCollection === collection && getCollectionConfig(collection)[markerField]) return markerField;
    return getFieldByHeader(collection, headerText);
  }

  function getCellDisplayValue(cell) {
    const value = cell.querySelector('.value, .chip-content');
    return normalizeText(value ? value.textContent : cell.textContent).replace(/^--$/, '');
  }

  function getChoiceText(meta, value) {
    const choice = (meta.choices || []).find((item) => item.value === value || item.text === value);
    return choice ? choice.text : value;
  }

  function updateCellDisplay(cell, meta, value) {
    const text = meta.type === 'select' ? getChoiceText(meta, value) : value;
    const target = cell.querySelector('.value, .chip-content') || cell;
    target.textContent = text || '--';
  }

  function getCurrentRows(collection) {
    return tableState.byCollection.get(collection)?.rows || [];
  }

  function getVisibleFields(collection, table) {
    const fields = ['id'];
    const headers = getHeaderLabels(table);
    Array.from(table.querySelectorAll('tbody tr:first-child td')).forEach((cell, cellIndex) => {
      const field = getCellField(collection, cell, headers[cellIndex]);
      if (field && !fields.includes(field)) fields.push(field);
    });

    return fields;
  }

  async function loadTableRowsFallback(collection, table) {
    if (tableState.byCollection.get(collection)?.loading) return;
    tableState.byCollection.set(collection, { rows: [], loading: true, capturedAt: Date.now() });

    try {
      const fields = getVisibleFields(collection, table);
      const response = await fetch(`/items/${collection}?limit=25&fields=${encodeURIComponent(fields.join(','))}&sort[]=id&page=1`, {
        credentials: 'include',
      });
      if (!response.ok) throw new Error(`Inline table fallback failed: ${response.status}`);
      const payload = await response.json();
      tableState.byCollection.set(collection, {
        rows: Array.isArray(payload?.data) ? applyInlineOverrides(collection, payload.data) : [],
        capturedAt: Date.now(),
      });
      window.requestAnimationFrame(enhanceInlineTables);
    } catch (error) {
      console.warn('[Symbolika inline table fallback]', error);
      tableState.byCollection.delete(collection);
    }
  }

  function enhanceInlineTables() {
    const collection = getListCollection();
    if (!collection || !isEditableTableCollection(collection)) return;
    loadCollectionMeta(collection);

    const table = document.querySelector('.v-table table, table');
    if (!table) return;
    const rowsData = getCurrentRows(collection);
    if (!rowsData.length) {
      loadTableRowsFallback(collection, table);
      return;
    }
    const headers = getHeaderLabels(table);
    const bodyRows = Array.from(table.querySelectorAll('tbody tr.table-row, tbody tr')).filter((row) => row.querySelectorAll('td').length);

    bodyRows.forEach((row, rowIndex) => {
      const item = rowsData[rowIndex];
      if (!item?.id) return;

      Array.from(row.querySelectorAll('td')).forEach((cell, cellIndex) => {
        if (cell.classList.contains('select') || cell.classList.contains('spacer')) return;
        const field = getCellField(collection, cell, headers[cellIndex]);
        const meta = field && getCollectionConfig(collection)[field];
        if (!meta) return;

        cell.classList.add('symbolika-inline-editable-cell');
        cell.dataset.symbolikaCollection = collection;
        cell.dataset.symbolikaField = field;
        cell.dataset.symbolikaPrimaryKey = item.id;
        cell.dataset.symbolikaType = meta.type;
        cell.title = tableEditText.hint;

        const override = getInlineOverride(collection, item.id, field);
        if (override !== undefined && !cell.classList.contains('is-editing')) {
          updateCellDisplay(cell, meta, override);
        }
      });
    });
  }

  function closeInlineEditor(commit) {
    const state = tableState.editCell;
    if (!state) return;
    tableState.editCell = null;

    if (commit) saveInlineEditor(state);
    else {
      state.cell.classList.remove('is-editing');
      state.cell.innerHTML = state.originalHtml;
    }
  }

  async function saveInlineEditor(state) {
    const { cell, collection, field, primaryKey, meta, editor, originalHtml } = state;
    const writeCollection = getInlineWriteTarget(collection, field);
    const value = meta.type === 'number'
      ? (editor.value === '' ? null : Number(editor.value))
      : editor.value;

    cell.classList.remove('is-editing');
    cell.classList.add('is-saving');
    setInlineOverride(collection, primaryKey, field, value);
    repeatInlineOverride();

    try {
      const response = await fetch(`/items/${writeCollection}/${primaryKey}`, {
        method: 'PATCH',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ [field]: value }),
      });
      if (!response.ok) throw new Error(`Inline edit failed: ${response.status}`);
      const payload = await response.json().catch(() => null);
      const confirmedValue = payload?.data && Object.prototype.hasOwnProperty.call(payload.data, field)
        ? payload.data[field]
        : value;

      const rows = getCurrentRows(collection);
      const row = rows.find((item) => String(item.id) === String(primaryKey));
      if (row) row[field] = confirmedValue;
      setInlineOverride(collection, primaryKey, field, confirmedValue);

      cell.innerHTML = originalHtml;
      updateCellDisplay(cell, meta, confirmedValue);
      cell.classList.remove('is-saving');
      cell.classList.add('is-saved');
      removeFilteredInlineRowIfNeeded(cell, collection, field, confirmedValue);
      repeatInlineOverride();
      window.setTimeout(() => cell.classList.remove('is-saved'), 900);
    } catch (error) {
      console.warn('[Symbolika inline edit]', error);
      clearInlineOverride(collection, primaryKey, field);
      cell.innerHTML = originalHtml;
      cell.classList.remove('is-saving');
      cell.classList.add('is-error');
      window.setTimeout(() => cell.classList.remove('is-error'), 1400);
    }
  }

  function openInlineEditor(cell) {
    if (tableState.editCell?.cell === cell) return;
    closeInlineEditor(false);

    const collection = cell.dataset.symbolikaCollection;
    const field = cell.dataset.symbolikaField;
    const primaryKey = cell.dataset.symbolikaPrimaryKey;
    const meta = getCollectionConfig(collection)[field];
    if (!collection || !field || !primaryKey || !meta) return;

    const rows = getCurrentRows(collection);
    const row = rows.find((item) => String(item.id) === String(primaryKey));
    const currentValue = row && Object.prototype.hasOwnProperty.call(row, field)
      ? row[field]
      : getCellDisplayValue(cell);
    const originalHtml = cell.innerHTML;
    let editor;

    if (meta.type === 'select') {
      editor = document.createElement('select');
      for (const choice of meta.choices || []) {
        const option = document.createElement('option');
        option.value = choice.value;
        option.textContent = choice.text;
        if (choice.value === currentValue || choice.text === currentValue) option.selected = true;
        editor.appendChild(option);
      }
    } else {
      editor = document.createElement('input');
      editor.type = meta.type === 'number' ? 'number' : 'text';
      editor.value = currentValue ?? '';
      if (meta.type === 'number') editor.step = 'any';
    }

    editor.className = 'symbolika-inline-editor';
    cell.innerHTML = '';
    cell.appendChild(editor);
    cell.classList.add('is-editing');
    tableState.editCell = { cell, collection, field, primaryKey, meta, editor, originalHtml };

    editor.addEventListener('click', (event) => event.stopPropagation());
    editor.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        closeInlineEditor(true);
      }
      if (event.key === 'Escape') {
        event.preventDefault();
        closeInlineEditor(false);
      }
    });
    editor.addEventListener('change', () => closeInlineEditor(true));
    editor.addEventListener('blur', () => {
      window.setTimeout(() => {
        if (tableState.editCell?.editor === editor) closeInlineEditor(true);
      }, 120);
    });
    window.setTimeout(() => editor.focus(), 0);
  }

  function removeFilteredInlineRowIfNeeded(cell, collection, field, value) {
    const shouldRemove =
      (collection === 'office_items_in_office' && field === 'office_status' && value !== 'in_office')
      || (collection === 'office_issue' && field === 'office_status' && value === 'issued');

    if (!shouldRemove) return;

    const row = cell.closest('tr');
    if (!row) return;
    window.setTimeout(() => {
      row.style.transition = 'opacity 160ms ease';
      row.style.opacity = '0';
      window.setTimeout(() => row.remove(), 180);
    }, 450);
  }

  function onInlineTableClick(event) {
    if (!(event.target instanceof HTMLElement)) return;
    const cell = event.target.closest('.symbolika-inline-editable-cell');
    if (!cell) return;
    event.preventDefault();
    event.stopPropagation();
    openInlineEditor(cell);
  }

  const pushUi = {
    button: null,
    publicKey: null,
    isBusy: false,
    isReady: false,
    pollTimer: null,
    currentUserId: null,
    lastNotificationTime: localStorage.getItem('symbolika:lastNotificationTime') || '',
    seenNotificationIds: new Set(JSON.parse(localStorage.getItem('symbolika:seenNotificationIds') || '[]')),
  };

  function urlBase64ToUint8Array(value) {
    const padding = '='.repeat((4 - value.length % 4) % 4);
    const base64 = (value + padding).replace(/-/g, '+').replace(/_/g, '/');
    const raw = window.atob(base64);
    const output = new Uint8Array(raw.length);

    for (let i = 0; i < raw.length; i += 1) {
      output[i] = raw.charCodeAt(i);
    }

    return output;
  }

  function withPushTimeout(promise, timeoutMs, message) {
    let timer = null;
    const timeout = new Promise((_, reject) => {
      timer = window.setTimeout(() => reject(new Error(message)), timeoutMs);
    });

    return Promise.race([promise, timeout]).finally(() => {
      if (timer) window.clearTimeout(timer);
    });
  }

  function setPushButtonState(state, text) {
    if (state === 'enabled' || state === 'denied') {
      if (pushUi.button) {
        pushUi.button.remove();
        pushUi.button = null;
      }
      return;
    }

    if (!pushUi.button) return;
    pushUi.button.dataset.state = state;
    pushUi.button.disabled = state === 'busy' || state === 'unsupported' || state === 'denied';
    pushUi.button.textContent = text;
  }

  async function getPushPublicKey() {
    if (pushUi.publicKey) return pushUi.publicKey;

    const response = await fetch('/symbolika-push/public-key', { credentials: 'include' });
    if (!response.ok) throw new Error(`Push key failed: ${response.status}`);

    const payload = await response.json();
    if (!payload?.publicKey) throw new Error('Push public key is empty');

    pushUi.publicKey = payload.publicKey;
    return pushUi.publicKey;
  }

  async function savePushSubscription(subscription) {
    const response = await fetch('/symbolika-push/subscribe', {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ subscription: subscription.toJSON() }),
    });

    if (!response.ok) throw new Error(`Push subscribe failed: ${response.status}`);
  }

  function getNotificationTargetUrl(notification) {
    if (!notification?.collection || notification.item == null) return '/admin/symbolika-orders';
    if (notification.collection === 'production_work' || notification.collection === 'screen_printing_work') {
      return '/admin/symbolika-production';
    }
    if (notification.collection === 'contractor_work') {
      return '/admin/symbolika-contractor';
    }
    if (notification.collection === 'customers' || notification.collection === 'customer_companies') {
      return '/admin/symbolika-orders';
    }
    return '/admin/symbolika-orders';
  }

  function showForegroundNotification(notification) {
    if (!notification?.id || Notification.permission !== 'granted') return;
    const notificationId = String(notification.id);
    if (pushUi.seenNotificationIds.has(notificationId)) return;

    pushUi.seenNotificationIds.add(notificationId);
    localStorage.setItem('symbolika:seenNotificationIds', JSON.stringify([...pushUi.seenNotificationIds].slice(-100)));

    const browserNotification = new Notification(notification.subject || '\u0421\u0438\u043c\u0432\u043e\u043b\u0438\u043a\u0430', {
      body: notification.message || '',
      tag: `directus:${notification.id}`,
      icon: '/admin/favicon.ico',
      data: {
        url: getNotificationTargetUrl(notification),
      },
    });

    browserNotification.onclick = () => {
      window.focus();
      const url = browserNotification.data?.url;
      if (url) window.location.assign(url);
      browserNotification.close();
    };
  }

  async function getCurrentUserId() {
    if (pushUi.currentUserId) return pushUi.currentUserId;

    const response = await fetch('/users/me?fields=id', { credentials: 'include' });
    if (!response.ok) return null;

    const payload = await response.json();
    pushUi.currentUserId = payload?.data?.id || null;
    return pushUi.currentUserId;
  }

  async function pollDirectusNotifications() {
    if (Notification.permission !== 'granted') return;

    try {
      const userId = await getCurrentUserId();
      if (!userId) return;

      const filter = encodeURIComponent(JSON.stringify({
        _and: [
          { recipient: { _eq: userId } },
          { status: { _eq: 'inbox' } },
          pushUi.lastNotificationTime
            ? { timestamp: { _gt: pushUi.lastNotificationTime } }
            : {},
        ].filter((value) => Object.keys(value).length),
      }));

      const response = await fetch(`/notifications?limit=5&sort[]=timestamp&fields=id,subject,message,collection,item,timestamp&filter=${filter}`, {
        credentials: 'include',
      });
      if (!response.ok) return;

      const payload = await response.json();
      const notifications = Array.isArray(payload?.data) ? payload.data : [];

      const newestTimestamp = notifications.reduce((timestamp, notification) => (
        !timestamp || notification.timestamp > timestamp ? notification.timestamp : timestamp
      ), pushUi.lastNotificationTime);

      if (newestTimestamp && newestTimestamp !== pushUi.lastNotificationTime) {
        pushUi.lastNotificationTime = newestTimestamp;
        localStorage.setItem('symbolika:lastNotificationTime', pushUi.lastNotificationTime);
      }

      for (const notification of notifications) {
        showForegroundNotification(notification);
      }
    } catch (error) {
      console.warn('[Symbolika notification poll]', error);
    }
  }

  function startNotificationPolling() {
    // Browser push is already delivered by the service worker. Polling Directus
    // notifications and calling new Notification() here duplicates the same toast.
    return;
  }

  async function enablePushNotifications() {
    if (pushUi.isBusy) return;
    if (pushUi.isReady) {
      startNotificationPolling();
      return;
    }

    pushUi.isBusy = true;
    setPushButtonState('busy', '\u0412\u043a\u043b\u044e\u0447\u0430\u044e...');

    try {
      if (Notification.permission !== 'granted') {
        const permission = await withPushTimeout(
          Notification.requestPermission(),
          15000,
          'Push permission request timed out',
        );
        if (permission !== 'granted') {
          setPushButtonState(permission === 'denied' ? 'denied' : 'default', permission === 'denied'
            ? '\u0423\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f \u0437\u0430\u043f\u0440\u0435\u0449\u0435\u043d\u044b'
            : '\u0412\u043a\u043b\u044e\u0447\u0438\u0442\u044c \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f');
          return;
        }
      }

      const publicKey = await withPushTimeout(getPushPublicKey(), 10000, 'Push public key request timed out');
      const registration = await withPushTimeout(
        navigator.serviceWorker.register('/admin/symbolika-push-sw.js', { scope: '/admin/' }),
        15000,
        'Push service worker registration timed out',
      );
      await withPushTimeout(navigator.serviceWorker.ready, 15000, 'Push service worker ready timed out');

      const currentSubscription = await withPushTimeout(
        registration.pushManager.getSubscription(),
        10000,
        'Push subscription lookup timed out',
      );
      const subscription = currentSubscription || await withPushTimeout(
        registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(publicKey),
        }),
        15000,
        'Push subscription request timed out',
      );

      await withPushTimeout(savePushSubscription(subscription), 10000, 'Push subscription save timed out');
      pushUi.isReady = true;
      setPushButtonState('enabled', '\u0423\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f \u0432\u043a\u043b\u044e\u0447\u0435\u043d\u044b');
      startNotificationPolling();
    } catch (error) {
      console.warn('[Symbolika push]', error);
      setPushButtonState('error', '\u041f\u043e\u0432\u0442\u043e\u0440\u0438\u0442\u044c \u043f\u0443\u0448\u0438');
    } finally {
      pushUi.isBusy = false;
    }
  }

  function createPushButton() {
    for (const button of document.querySelectorAll('.symbolika-push-toggle')) button.remove();
    pushUi.button = null;
    if (window.location.pathname.includes('/admin/login')) return;
    if (!('Notification' in window) || !('serviceWorker' in navigator) || !('PushManager' in window)) return;

    if (Notification.permission === 'granted') {
      enablePushNotifications();
    }
  }

  const observer = new MutationObserver((mutations) => {
    window.requestAnimationFrame(() => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          walk(node);
        }
        if (mutation.type === 'characterData') updateTextNode(mutation.target);
      }
      enhanceInlineTables();
      applyVisibleInlineOverrides();
      applyServiceNavigationVisibility();
      applyStandardContentVisibility();
      applyHiddenSystemModules();
      applyRoleModuleVisibility();
      applyNotificationCenterShortcut();
      applyMobileAppNavigation();
      applySymbolikaBranding();
    });
  });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scan, { once: true });
  } else {
    scan();
  }

  applySymbolikaBranding();
  applyStoredSymbolikaTheme();
  window.addEventListener('symbolika-theme-change', (event) => applySymbolikaTheme(event?.detail?.theme));
  window.addEventListener('storage', (event) => {
    if (event.key === 'symbolika-theme') applySymbolikaTheme(event.newValue);
  });

  installTableFetchCapture();
  enhanceInlineTables();
  applyVisibleInlineOverrides();
  createPushButton();
  installStandardContentRouteGuard();
  applyServiceNavigationVisibility();
  applyStandardContentVisibility();
  applyHiddenSystemModules();
  applyRoleModuleVisibility();
  applyNotificationCenterShortcut();
  applyMobileAppNavigation();

  let attempts = 0;
  const interval = window.setInterval(() => {
    scan();
    enhanceInlineTables();
    createPushButton();
    applyServiceNavigationVisibility();
    applyStandardContentVisibility();
    applyRoleModuleVisibility();
    applyNotificationCenterShortcut();
    applyMobileAppNavigation();
    applySymbolikaBranding();
    attempts += 1;
    if (attempts >= 20) window.clearInterval(interval);
  }, 500);

  document.addEventListener('click', onInlineTableClick, true);
  document.addEventListener('click', onNotificationCenterShortcutClick, true);
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && mobileNavigationState.open) closeMobileAppNavigation();
  });
  document.addEventListener('pointerdown', onStaticReadonlyFieldEvent, true);
  document.addEventListener('click', onStaticReadonlyFieldEvent, true);

  observer.observe(document.documentElement, {
    childList: true,
    characterData: true,
    subtree: true,
  });
})();
