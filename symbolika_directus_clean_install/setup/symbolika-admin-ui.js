(function () {
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
  const autosave = {
    timer: null,
    lastSaveAt: 0,
    lastSuccessfulSaveAt: 0,
    statusNode: null,
    activeField: null,
    activeInput: null,
    saveDelay: 1100,
    minInterval: 1200,
    savedGraceMs: 45000,
  };
  const autosaveText = {
    saving: '\u0421\u043e\u0445\u0440\u0430\u043d\u044f\u044e...',
    saved: '\u0421\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u043e',
    fieldError: '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043e\u043f\u0440\u0435\u0434\u0435\u043b\u0438\u0442\u044c \u043f\u043e\u043b\u0435',
    saveError: '\u041e\u0448\u0438\u0431\u043a\u0430 \u0441\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u0438\u044f',
  };
  const formAutosaveEnabled = false;
  const tableState = {
    byCollection: new Map(),
    collectionMeta: new Map(),
    loadingMeta: new Set(),
    overrides: new Map(),
    editCell: null,
  };
  const tableInlineEditingEnabled = false;

  function applyDocumentLocale() {
    document.documentElement.lang = 'ru-RU';
    document.documentElement.setAttribute('translate', 'no');
    if (document.body) {
      document.body.setAttribute('translate', 'no');
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
    applyDocumentLocale();
    updateCountLabels(document.body);
    normalizeCalendarWeekdays(document.body);
    walk(document.body);
  }

  function isContentItemPage() {
    const match = window.location.pathname.match(/^\/admin\/content\/([^/]+)\/([^/?#]+)/);
    return Boolean(match && match[2] && match[2] !== '+');
  }

  function isAutosaveTarget(target) {
    if (!target || !isContentItemPage()) return false;
    if (!(target instanceof HTMLElement)) return false;
    if (target.closest('.symbolika-autosave-select')) return false;
    if (target.closest('[role="dialog"]')) return false;
    if (target.closest('.v-table, .interface-list-o2m, .v-list, .search-input')) return false;
    if (target.matches('[readonly], [disabled], [type="file"], [type="search"]')) return false;

    const tag = target.tagName.toLowerCase();
    if (['input', 'textarea', 'select'].includes(tag)) return true;
    if (target.closest('.v-select, .v-checkbox, .v-date-picker, .v-input, .v-textarea')) return true;
    return false;
  }

  function ensureAutosaveStatus() {
    if (autosave.statusNode && document.body.contains(autosave.statusNode)) return autosave.statusNode;

    const node = document.createElement('div');
    node.className = 'symbolika-autosave-status';
    node.setAttribute('aria-live', 'polite');
    document.body.appendChild(node);
    autosave.statusNode = node;
    return node;
  }

  function setAutosaveStatus(state, text) {
    if (!formAutosaveEnabled) return;
    const node = ensureAutosaveStatus();
    node.dataset.state = state;
    node.textContent = text;
    node.classList.add('is-visible');

    if (state === 'saved') {
      window.setTimeout(() => {
        if (node.dataset.state === 'saved') node.classList.remove('is-visible');
      }, 1500);
    }
  }

  function scheduleAutosave(delay) {
    window.clearTimeout(autosave.timer);
    autosave.timer = window.setTimeout(dispatchDirectusFieldSave, delay);
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

  function getActiveField() {
    if (autosave.activeField && document.body.contains(autosave.activeField)) return autosave.activeField;
    if (document.activeElement instanceof HTMLElement) {
      return document.activeElement.closest('[data-field], [collection][field][primary-key]');
    }
    return null;
  }

  function readOfficeStatusValue(fieldElement) {
    const text = fieldElement.querySelector('input')?.value || fieldElement.textContent || '';
    if (text.includes('\u041d\u0435 \u0432 \u043e\u0444\u0438\u0441\u0435')) return 'not_in_office';
    if (text.includes('\u0412\u044b\u0434\u0430\u043d')) return 'issued';
    if (text.includes('\u0412 \u043e\u0444\u0438\u0441\u0435')) return 'in_office';
    return undefined;
  }

  function readActiveFieldValue(fieldElement) {
    const field = fieldElement.dataset.field;
    const input = autosave.activeInput && fieldElement.contains(autosave.activeInput)
      ? autosave.activeInput
      : fieldElement.querySelector('textarea, input:not([type="hidden"]), select');

    if (field === 'office_status') return readOfficeStatusValue(fieldElement);
    if (!input) return undefined;
    if (input.matches('[type="checkbox"]')) return input.checked;
    if (input.matches('[readonly], [disabled], [type="file"], [type="search"]')) return undefined;
    return input.value;
  }

  async function dispatchDirectusFieldSave() {
    const now = Date.now();
    if (now - autosave.lastSaveAt < autosave.minInterval) {
      scheduleAutosave(autosave.minInterval);
      return;
    }

    autosave.lastSaveAt = now;

    const fieldElement = getActiveField();
    const control = getFieldControl(fieldElement) || fieldElement;
    const routeItem = getRouteItem();
    const collection = fieldElement?.dataset.collection || control?.getAttribute?.('collection') || routeItem.collection;
    const field = fieldElement?.dataset.field || control?.getAttribute?.('field');
    const primaryKey = fieldElement?.dataset.primaryKey || control?.getAttribute?.('primary-key') || routeItem.primaryKey;
    const value = fieldElement ? readActiveFieldValue(fieldElement) : undefined;

    if (!collection || !field || !primaryKey || primaryKey === '+' || value === undefined) {
      return;
    }

    setAutosaveStatus('saving', autosaveText.saving);

    try {
      const response = await fetch(`/items/${collection}/${primaryKey}`, {
        method: 'PATCH',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ [field]: value }),
      });

      if (!response.ok) throw new Error(`Autosave failed: ${response.status}`);
      autosave.lastSuccessfulSaveAt = Date.now();
      setAutosaveStatus('saved', autosaveText.saved);
    } catch (error) {
      console.warn('[Symbolika autosave]', error);
      if (String(error?.message || '').includes('Autosave failed: 403')) return;
      if (String(error?.message || '').includes('Autosave failed: 400')) return;
      setAutosaveStatus('error', autosaveText.saveError);
    }
  }

  function onAutosaveInput(event) {
    if (!isAutosaveTarget(event.target)) return;
    autosave.activeField = event.target.closest('[data-collection][data-field][data-primary-key]');
    autosave.activeInput = event.target;

    const tag = event.target.tagName?.toLowerCase();
    const type = event.target.getAttribute?.('type');
    const immediate = event.type === 'change' || tag === 'select' || ['checkbox', 'radio', 'date', 'datetime-local'].includes(type);

    scheduleAutosave(immediate ? 250 : autosave.saveDelay);
  }

  function onAutosavePointerDown(event) {
    if (!isContentItemPage()) return;
    const field = event.target instanceof HTMLElement ? event.target.closest('[data-field]') : null;
    if (!field || field.closest('.v-table, .interface-list-o2m, .v-list')) return;
    autosave.activeField = field;
    autosave.activeInput = event.target instanceof HTMLElement ? event.target : null;
  }

  function onAutosaveClick(event) {
    if (!isContentItemPage() || !autosave.activeField) return;
    if (!(event.target instanceof HTMLElement)) return;
    if (event.target.closest('.symbolika-autosave-select')) return;

    const clickedDirectusControl = event.target.closest(
      '.v-select, .v-checkbox, .v-input, .v-list-item, [role="option"], [role="checkbox"]'
    );

    if (!clickedDirectusControl) return;
    if (
      autosave.activeField.contains(clickedDirectusControl)
      && clickedDirectusControl.closest('.v-select, .v-input')
      && !clickedDirectusControl.closest('.v-checkbox, [role="checkbox"]')
    ) {
      return;
    }
    scheduleAutosave(550);
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

  function resolveAutosavedDirtyModal(root) {
    if (!root || Date.now() - autosave.lastSuccessfulSaveAt > autosave.savedGraceMs) return;
    const text = root.textContent || '';
    if (!text.includes('\u041d\u0435\u0441\u043e\u0445\u0440\u0430\u043d\u0451\u043d\u043d\u044b\u0435 \u0438\u0437\u043c\u0435\u043d\u0435\u043d\u0438\u044f')) return;

    const buttons = Array.from(root.querySelectorAll('button'));
    const discard = buttons.find((button) => button.textContent?.includes('\u041e\u0442\u043c\u0435\u043d\u0438\u0442\u044c \u0438\u0437\u043c\u0435\u043d\u0435\u043d\u0438\u044f'));
    if (discard) window.setTimeout(() => discard.click(), 50);
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
    setAutosaveStatus('saving', autosaveText.saving);

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
      setAutosaveStatus('saved', autosaveText.saved);
      repeatInlineOverride();
      window.setTimeout(() => cell.classList.remove('is-saved'), 900);
    } catch (error) {
      console.warn('[Symbolika inline edit]', error);
      clearInlineOverride(collection, primaryKey, field);
      cell.innerHTML = originalHtml;
      cell.classList.remove('is-saving');
      cell.classList.add('is-error');
      setAutosaveStatus('error', autosaveText.saveError);
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

  function setPushButtonState(state, text) {
    if (state === 'enabled') {
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
    if (!notification?.collection || notification.item == null) return '/admin';
    return `/admin/content/${notification.collection}/${notification.item}`;
  }

  function showForegroundNotification(notification) {
    if (!notification?.id || Notification.permission !== 'granted') return;

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

      for (const notification of notifications) {
        showForegroundNotification(notification);
        if (!pushUi.lastNotificationTime || notification.timestamp > pushUi.lastNotificationTime) {
          pushUi.lastNotificationTime = notification.timestamp;
          localStorage.setItem('symbolika:lastNotificationTime', pushUi.lastNotificationTime);
        }
      }
    } catch (error) {
      console.warn('[Symbolika notification poll]', error);
    }
  }

  function startNotificationPolling() {
    if (pushUi.pollTimer || Notification.permission !== 'granted') return;

    pollDirectusNotifications();
    pushUi.pollTimer = window.setInterval(pollDirectusNotifications, 12000);
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
        const permission = await Notification.requestPermission();
        if (permission !== 'granted') {
          setPushButtonState(permission === 'denied' ? 'denied' : 'default', permission === 'denied'
            ? '\u0423\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f \u0437\u0430\u043f\u0440\u0435\u0449\u0435\u043d\u044b'
            : '\u0412\u043a\u043b\u044e\u0447\u0438\u0442\u044c \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f');
          return;
        }
      }

      const publicKey = await getPushPublicKey();
      const registration = await navigator.serviceWorker.register('/admin/symbolika-push-sw.js', {
        scope: '/admin/',
      });
      await navigator.serviceWorker.ready;

      const subscription = await registration.pushManager.getSubscription()
        || await registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(publicKey),
        });

      await savePushSubscription(subscription);
      pushUi.isReady = true;
      setPushButtonState('enabled', '\u0423\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f \u0432\u043a\u043b\u044e\u0447\u0435\u043d\u044b');
      startNotificationPolling();
    } catch (error) {
      console.warn('[Symbolika push]', error);
      setPushButtonState('error', '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0432\u043a\u043b\u044e\u0447\u0438\u0442\u044c');
    } finally {
      pushUi.isBusy = false;
    }
  }

  function createPushButton() {
    if (window.location.pathname.includes('/admin/login')) return;
    if (!('Notification' in window) || !('serviceWorker' in navigator) || !('PushManager' in window)) return;

    if (Notification.permission === 'granted') {
      enablePushNotifications();
      return;
    }

    if (pushUi.button) return;

    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'symbolika-push-toggle';
    button.addEventListener('click', enablePushNotifications);
    document.body.appendChild(button);
    pushUi.button = button;

    if (Notification.permission === 'denied') {
      setPushButtonState('denied', '\u0423\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f \u0437\u0430\u043f\u0440\u0435\u0449\u0435\u043d\u044b');
    } else {
      setPushButtonState('default', '\u0412\u043a\u043b\u044e\u0447\u0438\u0442\u044c \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f');
    }
  }

  const observer = new MutationObserver((mutations) => {
    window.requestAnimationFrame(() => {
      resolveAutosavedDirtyModal(document.body);
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          walk(node);
          if (node.nodeType === Node.ELEMENT_NODE) resolveAutosavedDirtyModal(node);
        }
        if (mutation.type === 'characterData') updateTextNode(mutation.target);
      }
      enhanceInlineTables();
      applyVisibleInlineOverrides();
    });
  });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scan, { once: true });
  } else {
    scan();
  }

  installTableFetchCapture();
  enhanceInlineTables();
  applyVisibleInlineOverrides();
  createPushButton();

  let attempts = 0;
  const interval = window.setInterval(() => {
    scan();
    enhanceInlineTables();
    createPushButton();
    attempts += 1;
    if (attempts >= 20) window.clearInterval(interval);
  }, 500);

  document.addEventListener('click', onInlineTableClick, true);
  document.addEventListener('pointerdown', onStaticReadonlyFieldEvent, true);
  document.addEventListener('click', onStaticReadonlyFieldEvent, true);
  if (formAutosaveEnabled) {
    document.addEventListener('pointerdown', onAutosavePointerDown, true);
    document.addEventListener('click', onAutosaveClick, true);
    document.addEventListener('input', onAutosaveInput, true);
    document.addEventListener('change', onAutosaveInput, true);
    document.addEventListener('blur', onAutosaveInput, true);
  }

  observer.observe(document.documentElement, {
    childList: true,
    characterData: true,
    subtree: true,
  });
})();
