function escapeMailText(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function sanitizeMailMarkup(value) {
  const source = String(value ?? '').trim();
  if (!source || typeof DOMParser === 'undefined') return '';
  const documentNode = new DOMParser().parseFromString(source, 'text/html');
  documentNode.querySelectorAll('script, iframe, frame, frameset, object, embed, form, input, button, textarea, select, option, base, meta, link').forEach((node) => node.remove());
  documentNode.querySelectorAll('*').forEach((node) => {
    [...node.attributes].forEach((attribute) => {
      const name = attribute.name.toLowerCase();
      const valueText = String(attribute.value || '').trim();
      if (name.startsWith('on') || name === 'srcdoc' || name === 'formaction') {
        node.removeAttribute(attribute.name);
        return;
      }
      if (['href', 'src', 'background', 'poster', 'action'].includes(name)
        && /^(?:javascript|vbscript|data:text\/html)/i.test(valueText.replace(/\s+/g, ''))) {
        node.removeAttribute(attribute.name);
        return;
      }
      if (name === 'style' && /(?:expression\s*\(|javascript\s*:|vbscript\s*:|behavior\s*:|-moz-binding)/i.test(valueText)) {
        node.removeAttribute(attribute.name);
      }
    });
    if (node.tagName === 'A') {
      node.setAttribute('target', '_blank');
      node.setAttribute('rel', 'noopener noreferrer');
    }
    if (node.tagName === 'IMG') {
      node.setAttribute('loading', 'lazy');
      node.setAttribute('referrerpolicy', 'no-referrer');
    }
  });
  const embeddedStyles = [...documentNode.querySelectorAll('style')]
    .map((node) => String(node.textContent || '')
      .replace(/@import\s+[^;]+;?/gi, '')
      .replace(/(?:expression\s*\(|javascript\s*:|vbscript\s*:|behavior\s*:|-moz-binding)/gi, '')
      .replace(/<\/style/gi, ''))
    .filter(Boolean)
    .map((css) => `<style>${css}</style>`)
    .join('');
  documentNode.querySelectorAll('style').forEach((node) => node.remove());
  return `${embeddedStyles}${documentNode.body?.innerHTML || ''}`;
}

function mailBodyDocument(message) {
  const html = sanitizeMailMarkup(message?.body_html);
  const fallback = escapeMailText(message?.body_text || 'Письмо без текстовой части');
  const content = html || `<div class="plain-text">${fallback}</div>`;
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="light dark"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: cid: https: http:; style-src 'unsafe-inline'; font-src data: https:; form-action 'none'; base-uri 'none';"><base target="_blank"><style>
    :root{color-scheme:light dark}html,body{margin:0;padding:0;background:transparent;color:#e9edf2;font:14px/1.58 Arial,sans-serif;overflow-wrap:anywhere}body{padding:1px}p{margin:.3em 0 1em}h1,h2,h3,h4,h5,h6{margin:1em 0 .45em;line-height:1.25}ul,ol{margin:.55em 0 1em;padding-left:1.65em}li{margin:.25em 0}blockquote{margin:1em 0;padding:.25em 0 .25em 1em;border-left:3px solid #f97316;color:#aeb7c2}a{color:#fb923c;text-decoration:underline}table{max-width:100%;border-collapse:collapse}td,th{vertical-align:top}img{max-width:100%;height:auto}.plain-text{white-space:pre-wrap}@media(prefers-color-scheme:light){html,body{color:#20242a}blockquote{color:#626b76}}
  </style></head><body>${content}</body></html>`;
}

const MailWorkspace = {
  data() {
    return {
      loading: true,
      threadLoading: false,
      sending: false,
      syncing: false,
      error: '',
      errorTimer: null,
      notice: '',
      noticeTimer: null,
      mode: 'mock',
      configured: false,
      actor: null,
      folders: [],
      selectedFolderId: null,
      mailboxScope: 'folder',
      totalStarred: 0,
      threads: [],
      selectedThread: null,
      messages: [],
      search: '',
      threadScope: 'all',
      searchTimer: null,
      autoRefreshTimer: null,
      lastRefreshAt: null,
      showComposer: false,
      composer: {
        thread_id: null,
        folder_id: null,
        from_alias: '',
        to: '',
        subject: '',
        body: '',
        include_signature: true,
      },
      options: { customers: [], companies: [], orders: [], employees: [], folders: [] },
      optionsLoading: false,
      showLinkDialog: false,
      linkForm: { customer_id: null, company_id: null, order_id: null, tags_text: '', folder_id: null },
      showTaskDialog: false,
      taskForm: { title: '', assigned_to: null, due_date: '', priority: 'normal', description: '' },
      showPaymentDialog: false,
      paymentForm: { due_date: '', comment: '' },
      actionSaving: false,
      showSignatureDialog: false,
      signatureForm: '',
      signatureTargetEmployee: null,
      signatureSettings: {},
      signatureDefaults: {},
      signatureLinkVisible: false,
      signatureLinkForm: { text: '', url: 'https://' },
      signatureSelection: null,
      signatureSaving: false,
      showSettings: false,
      settingsLoading: false,
      settings: null,
      savingFolderId: null,
      creatingFolder: false,
      newFolder: { name: '', imap_name: '', alias_email: '', employee: null, is_shared: false },
      savingSignatureEmployeeId: null,
    };
  },

  computed: {
    selectedFolder() {
      if (this.mailboxScope === 'starred') return null;
      return this.folders.find((row) => Number(row.id) === Number(this.selectedFolderId)) || null;
    },
    currentSenderAlias() {
      return this.composer.from_alias || this.defaultSenderAlias;
    },
    defaultSenderAlias() {
      const personalFolder = this.folders.find((folder) => Number(folder.employee) === Number(this.actor?.employee_id) && folder.alias_email);
      return this.actor?.sender_alias
        || personalFolder?.alias_email
        || (/^[^\s@]+@symb62\.ru$/i.test(this.actor?.email || '') ? this.actor.email : '')
        || this.selectedFolder?.alias_email
        || 'start@symb62.ru';
    },
    totalUnread() {
      return this.folders.reduce((sum, row) => sum + Number(row.unread || 0), 0);
    },
    selectedParticipant() {
      return this.selectedThread?.participants?.[0] || {};
    },
    visibleThreads() {
      if (this.threadScope === 'unread') return this.threads.filter((thread) => thread.is_unread);
      if (this.threadScope === 'starred') return this.threads.filter((thread) => thread.is_starred);
      return this.threads;
    },
    unreadThreadCount() {
      return this.threads.filter((thread) => thread.is_unread).length;
    },
    starredThreadCount() {
      return this.threads.filter((thread) => thread.is_starred).length;
    },
    lastRefreshLabel() {
      if (!this.lastRefreshAt) return 'Еще не обновлялась';
      return `Обновлено в ${this.lastRefreshAt.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' })}`;
    },
  },

  watch: {
    notice(value) {
      window.clearTimeout(this.noticeTimer);
      if (!value) return;
      this.noticeTimer = window.setTimeout(() => {
        this.notice = '';
        this.noticeTimer = null;
      }, 5000);
    },
    error(value) {
      window.clearTimeout(this.errorTimer);
      if (!value) return;
      this.errorTimer = window.setTimeout(() => {
        this.error = '';
        this.errorTimer = null;
      }, 5000);
    },
    search() {
      window.clearTimeout(this.searchTimer);
      this.searchTimer = window.setTimeout(() => this.loadMailbox(false), 320);
    },
  },

  async mounted() {
    this.installStyles();
    await this.loadMailbox(true);
    await this.openLinkedThread();
    this.autoRefreshTimer = window.setInterval(() => this.autoRefreshMailbox(), 10000);
  },

  beforeUnmount() {
    window.clearTimeout(this.searchTimer);
    window.clearTimeout(this.errorTimer);
    window.clearTimeout(this.noticeTimer);
    window.clearInterval(this.autoRefreshTimer);
  },

  methods: {
    mailBodyDocument,
    resizeMailBody(event) {
      const frame = event?.target;
      if (!frame) return;
      const resize = () => {
        try {
          const documentNode = frame.contentDocument;
          const contentHeight = Math.max(
            Number(documentNode?.body?.scrollHeight || 0),
            Number(documentNode?.documentElement?.scrollHeight || 0),
            96,
          );
          frame.style.height = `${Math.min(contentHeight + 4, 900)}px`;
          frame.scrolling = contentHeight > 900 ? 'yes' : 'no';
          documentNode?.querySelectorAll('img').forEach((image) => {
            if (!image.dataset.symbolikaResizeBound) {
              image.dataset.symbolikaResizeBound = '1';
              image.addEventListener('load', resize, { once: true });
            }
          });
        } catch {
          frame.style.height = '320px';
        }
      };
      resize();
      window.setTimeout(resize, 180);
      window.setTimeout(resize, 900);
    },
    async request(path, options = {}) {
      const response = await fetch(path, {
        credentials: 'include',
        headers: { 'content-type': 'application/json', ...(options.headers || {}) },
        ...options,
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload?.errors?.[0]?.message || payload?.message || `HTTP ${response.status}`);
      return payload.data;
    },

    async loadMailbox(initial = false, preserveReader = false) {
      if (initial) this.loading = true;
      this.error = '';
      try {
        const params = new URLSearchParams();
        if (this.mailboxScope === 'starred') params.set('scope', 'starred');
        else if (this.selectedFolderId) params.set('folder', this.selectedFolderId);
        if (this.search.trim()) params.set('search', this.search.trim());
        const data = await this.request(`/symbolika-mail/bootstrap?${params.toString()}`);
        this.actor = data.actor;
        this.mode = data.mode;
        this.configured = data.configured;
        this.folders = data.folders || [];
        this.mailboxScope = data.scope === 'starred' ? 'starred' : 'folder';
        if (this.mailboxScope === 'folder') this.selectedFolderId = data.selected_folder;
        this.totalStarred = Number(data.starred_count || 0);
        this.threads = data.threads || [];
        if (this.selectedThread) {
          const freshThread = this.threads.find((row) => Number(row.id) === Number(this.selectedThread.id));
          if (!freshThread) {
            this.selectedThread = null;
            this.messages = [];
          } else {
            Object.assign(this.selectedThread, freshThread);
          }
        }
        this.lastRefreshAt = new Date();
      } catch (error) {
        this.error = error.message || 'Не удалось загрузить почту.';
      } finally {
        this.loading = false;
      }
    },

    async autoRefreshMailbox() {
      if (document.hidden || this.loading || this.threadLoading || this.sending || this.syncing || this.showComposer) return;
      await this.syncMailbox(true);
    },

    async openLinkedThread() {
      const threadId = Number(new URLSearchParams(window.location.search).get('thread') || 0);
      if (!threadId) return;
      try {
        const data = await this.request(`/symbolika-mail/threads/${threadId}`);
        this.selectedFolderId = data.thread.folder_id;
        await this.loadMailbox(false);
        const row = this.threads.find((thread) => Number(thread.id) === threadId) || data.thread;
        await this.openThread(row);
      } catch (error) {
        this.error = error.message;
      }
    },

    async loadOptions() {
      if (this.optionsLoading) return;
      this.optionsLoading = true;
      try {
        this.options = await this.request('/symbolika-mail/options');
      } catch (error) {
        this.error = error.message;
      } finally {
        this.optionsLoading = false;
      }
    },

    async openLinkDialog() {
      if (!this.selectedThread) return;
      await this.loadOptions();
      this.linkForm = {
        customer_id: this.selectedThread.customer_id || null,
        company_id: this.selectedThread.company_id || null,
        order_id: this.selectedThread.order_id || null,
        tags_text: (this.selectedThread.tags || []).join(', '),
        folder_id: this.selectedThread.folder_id || null,
      };
      this.showLinkDialog = true;
    },

    async saveThreadLinks() {
      if (!this.selectedThread || this.actionSaving) return;
      this.actionSaving = true;
      try {
        const threadId = this.selectedThread.id;
        const tags = String(this.linkForm.tags_text || '').split(',').map((value) => value.trim()).filter(Boolean);
        const saved = await this.patchThread(this.selectedThread, {
          customer_id: this.linkForm.customer_id || null,
          company_id: this.linkForm.company_id || null,
          order_id: this.linkForm.order_id || null,
          folder_id: this.linkForm.folder_id || this.selectedThread.folder_id,
          tags,
        });
        if (!saved) return;
        this.showLinkDialog = false;
        this.selectedFolderId = this.linkForm.folder_id || this.selectedFolderId;
        await this.loadMailbox(false);
        const thread = this.threads.find((row) => Number(row.id) === Number(threadId));
        if (thread) await this.openThread(thread);
        this.notice = 'Связи, папка и теги письма сохранены.';
      } finally {
        this.actionSaving = false;
      }
    },

    applyLinkOrder() {
      const order = this.options.orders.find((row) => Number(row.id) === Number(this.linkForm.order_id));
      if (!order) return;
      this.linkForm.customer_id = order.customer || null;
      this.linkForm.company_id = order.customer_company || null;
    },

    applyLinkCustomer() {
      const customer = this.options.customers.find((row) => Number(row.id) === Number(this.linkForm.customer_id));
      if (customer?.company) this.linkForm.company_id = customer.company;
    },

    async openTaskDialog() {
      if (!this.selectedThread) return;
      await this.loadOptions();
      this.taskForm = {
        title: `Письмо: ${this.selectedThread.subject}`,
        assigned_to: this.actor?.employee_id || null,
        due_date: '',
        priority: 'normal',
        description: '',
      };
      this.showTaskDialog = true;
    },

    async createTaskFromMail() {
      if (!this.selectedThread || this.actionSaving) return;
      this.actionSaving = true;
      try {
        const result = await this.request(`/symbolika-mail/threads/${this.selectedThread.id}/task`, {
          method: 'POST', body: JSON.stringify(this.taskForm),
        });
        this.selectedThread.task_id = result.task.id;
        this.selectedThread.task_title = result.task.title;
        this.showTaskDialog = false;
        this.notice = 'Задача из письма создана и назначена.';
      } catch (error) {
        this.error = error.message;
      } finally {
        this.actionSaving = false;
      }
    },

    openPaymentDialog() {
      if (!this.selectedThread) return;
      this.paymentForm = { due_date: '', comment: '' };
      this.showPaymentDialog = true;
    },

    async createPaymentTasks() {
      if (!this.selectedThread || this.actionSaving) return;
      this.actionSaving = true;
      try {
        const result = await this.request(`/symbolika-mail/threads/${this.selectedThread.id}/payment-tasks`, {
          method: 'POST', body: JSON.stringify(this.paymentForm),
        });
        this.showPaymentDialog = false;
        this.notice = `Счет отправлен в задачи администратору и управляющему (${result.tasks.length}).`;
        await this.openThread(this.selectedThread);
      } catch (error) {
        this.error = error.message;
      } finally {
        this.actionSaving = false;
      }
    },

    openForwardComposer(thread) {
      const lastMessage = this.messages[this.messages.length - 1] || {};
      const forwardedFiles = (lastMessage.attachments || []).map((file) => file.name).filter(Boolean);
      const attachmentNote = forwardedFiles.length ? `\nВложения исходного письма: ${forwardedFiles.join(', ')}` : '';
      this.composer = {
        thread_id: null,
        folder_id: thread?.folder_id || this.selectedFolderId,
        from_alias: this.defaultSenderAlias,
        to: '',
        subject: /^fwd:/i.test(thread?.subject || '') ? thread.subject : `Fwd: ${thread?.subject || ''}`,
        body: `\n\n---------- Пересланное письмо ----------\nОт: ${lastMessage.from_name || lastMessage.from_email || ''}\nДата: ${this.formatDate(lastMessage.sent_at, true)}\nТема: ${lastMessage.subject || thread?.subject || ''}${attachmentNote}\n\n${lastMessage.body_text || ''}`,
        include_signature: true,
        customer_id: thread?.customer_id || null,
        company_id: thread?.company_id || null,
        order_id: thread?.order_id || null,
      };
      this.showComposer = true;
    },

    openSignatureDialog(employee = null) {
      this.signatureTargetEmployee = employee || null;
      this.signatureForm = employee?.email_signature ?? this.actor?.signature_custom ?? '';
      this.signatureSettings = { ...(employee?.signature_settings || this.actor?.signature_settings || {}) };
      this.signatureDefaults = { ...(employee?.signature_defaults || this.actor?.signature_defaults || {}) };
      this.signatureLinkVisible = false;
      this.signatureLinkForm = { text: '', url: 'https://' };
      this.showSignatureDialog = true;
      this.$nextTick(() => {
        if (this.$refs.signatureEditor) this.$refs.signatureEditor.innerHTML = this.signatureForm;
      });
    },

    resetSignatureSettings() {
      this.signatureSettings = { ...this.signatureDefaults };
    },

    syncSignatureEditor(event) {
      this.signatureForm = event?.target?.innerHTML || '';
    },

    formatSignature(command, value = null) {
      this.$refs.signatureEditor?.focus();
      document.execCommand(command, false, value);
      this.signatureForm = this.$refs.signatureEditor?.innerHTML || '';
    },

    openSignatureLink() {
      const selection = window.getSelection();
      this.signatureSelection = selection?.rangeCount ? selection.getRangeAt(0).cloneRange() : null;
      this.signatureLinkForm = { text: selection?.toString() || '', url: 'https://' };
      this.signatureLinkVisible = true;
    },

    insertSignatureLink() {
      const url = String(this.signatureLinkForm.url || '').trim();
      if (!/^(https?:\/\/|mailto:|tel:)/i.test(url)) {
        this.error = 'Ссылка должна начинаться с https://, http://, mailto: или tel:';
        return;
      }
      const escape = (value) => String(value || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
      const editor = this.$refs.signatureEditor;
      editor?.focus();
      const selection = window.getSelection();
      if (this.signatureSelection && selection) {
        selection.removeAllRanges();
        selection.addRange(this.signatureSelection);
      }
      document.execCommand('insertHTML', false, `<a href="${escape(url)}" target="_blank" rel="noopener noreferrer">${escape(this.signatureLinkForm.text || url)}</a>`);
      this.signatureForm = editor?.innerHTML || '';
      this.signatureLinkVisible = false;
      this.signatureSelection = null;
    },

    async saveSignature() {
      if (this.signatureSaving) return;
      if (this.$refs.signatureEditor) this.signatureForm = this.$refs.signatureEditor.innerHTML;
      this.signatureSaving = true;
      try {
        const endpoint = this.signatureTargetEmployee
          ? `/symbolika-mail/employees/${this.signatureTargetEmployee.id}/signature`
          : '/symbolika-mail/signature';
        const result = await this.request(endpoint, {
          method: 'PATCH', body: JSON.stringify({ signature: this.signatureForm, settings: this.signatureSettings }),
        });
        if (this.signatureTargetEmployee) {
          this.signatureTargetEmployee.email_signature = result.signature;
          this.signatureTargetEmployee.signature_preview = result.signature_html;
          this.signatureTargetEmployee.signature_settings = result.signature_settings;
          this.signatureTargetEmployee.signature_defaults = result.signature_defaults;
          if (Number(this.signatureTargetEmployee.id) === Number(this.actor?.employee_id)) {
            this.actor.signature_custom = result.signature;
            this.actor.signature = result.signature_html;
            this.actor.signature_settings = result.signature_settings;
            this.actor.signature_defaults = result.signature_defaults;
          }
        } else {
          this.actor.signature_custom = result.signature;
          this.actor.signature = result.signature_html;
          this.actor.signature_settings = result.signature_settings;
          this.actor.signature_defaults = result.signature_defaults;
        }
        this.showSignatureDialog = false;
        this.notice = this.signatureTargetEmployee
          ? `Подпись сотрудника «${this.signatureTargetEmployee.full_name}» сохранена.`
          : 'Подпись для исходящих писем сохранена.';
      } catch (error) {
        this.error = error.message;
      } finally {
        this.signatureSaving = false;
      }
    },

    async selectFolder(folder) {
      this.mailboxScope = 'folder';
      this.selectedFolderId = folder.id;
      this.selectedThread = null;
      this.messages = [];
      this.threadScope = 'all';
      await this.loadMailbox(false);
    },

    async selectStarred() {
      this.mailboxScope = 'starred';
      this.selectedThread = null;
      this.messages = [];
      this.threadScope = 'all';
      await this.loadMailbox(false);
    },

    closeThread() {
      this.selectedThread = null;
      this.messages = [];
    },

    async openThread(thread) {
      this.threadLoading = true;
      this.error = '';
      try {
        const data = await this.request(`/symbolika-mail/threads/${thread.id}`);
        this.selectedThread = data.thread;
        this.messages = data.messages || [];
        thread.is_unread = false;
        const folder = this.folders.find((row) => Number(row.id) === Number(thread.folder_id));
        if (folder) folder.unread = Math.max(0, Number(folder.unread || 0) - 1);
      } catch (error) {
        this.error = error.message;
      } finally {
        this.threadLoading = false;
      }
    },

    openComposer(thread = null) {
      const participant = thread?.participants?.find((row) => row.email && !row.email.endsWith('@symb62.ru'))
        || thread?.participants?.[0]
        || {};
      this.composer = {
        thread_id: thread?.id || null,
        folder_id: thread?.folder_id || this.selectedFolderId,
        from_alias: this.defaultSenderAlias,
        to: participant.email || '',
        subject: thread ? (/^re:/i.test(thread.subject) ? thread.subject : `Re: ${thread.subject}`) : '',
        body: '',
        include_signature: true,
      };
      this.showComposer = true;
      this.notice = '';
    },

    async sendMessage() {
      if (this.sending) return;
      this.sending = true;
      this.error = '';
      try {
        const result = await this.request('/symbolika-mail/send', {
          method: 'POST',
          body: JSON.stringify(this.composer),
        });
        this.showComposer = false;
        this.notice = result.delivered
          ? 'Письмо отправлено.'
          : 'Тестовое письмо добавлено в переписку. Реальная отправка пока отключена.';
        await this.loadMailbox(false);
        const thread = this.threads.find((row) => Number(row.id) === Number(result.thread_id));
        if (thread) await this.openThread(thread);
      } catch (error) {
        this.error = error.message;
      } finally {
        this.sending = false;
      }
    },

    async syncMailbox(silent = false) {
      if (this.syncing) return;
      this.syncing = true;
      if (!silent) this.notice = '';
      if (!silent) this.error = '';
      try {
        const result = await this.request('/symbolika-mail/sync', { method: 'POST', body: '{}' });
        if (!silent) this.notice = result.message || `Синхронизация завершена. Новых писем: ${result.synced || 0}.`;
        await this.loadMailbox(false, true);
      } catch (error) {
        if (!silent) this.error = error.message;
      } finally {
        this.syncing = false;
      }
    },

    async patchThread(thread, patch) {
      try {
        await this.request(`/symbolika-mail/threads/${thread.id}`, { method: 'PATCH', body: JSON.stringify(patch) });
        Object.assign(thread, patch);
        if (this.selectedThread?.id === thread.id) Object.assign(this.selectedThread, patch);
        if (Object.prototype.hasOwnProperty.call(patch, 'is_starred')) {
          this.totalStarred = Math.max(0, this.totalStarred + (patch.is_starred ? 1 : -1));
          if (this.mailboxScope === 'starred' && !patch.is_starred) {
            this.threads = this.threads.filter((row) => Number(row.id) !== Number(thread.id));
            if (this.selectedThread?.id === thread.id) {
              this.selectedThread = null;
              this.messages = [];
            }
          }
        }
        if (patch.is_archived) {
          this.selectedThread = null;
          this.messages = [];
          await this.loadMailbox(false);
        }
        return true;
      } catch (error) {
        this.error = error.message;
        return false;
      }
    },

    async openSettingsDialog() {
      this.showSettings = true;
      this.settingsLoading = true;
      this.error = '';
      try {
        this.settings = await this.request('/symbolika-mail/settings');
      } catch (error) {
        this.error = error.message;
        this.showSettings = false;
      } finally {
        this.settingsLoading = false;
      }
    },

    async saveFolder(folder) {
      this.savingFolderId = folder.id;
      try {
        await this.request(`/symbolika-mail/folders/${folder.id}`, {
          method: 'PATCH',
          body: JSON.stringify({
            name: folder.name,
            imap_name: folder.imap_name,
            alias_email: folder.alias_email,
            employee: folder.employee,
            is_shared: folder.is_shared,
            is_active: folder.is_active,
          }),
        });
        this.notice = `Папка «${folder.name}» сохранена.`;
        await this.loadMailbox(false);
      } catch (error) {
        this.error = error.message;
      } finally {
        this.savingFolderId = null;
      }
    },

    async createFolder() {
      if (this.creatingFolder) return;
      if (!this.newFolder.name.trim()) {
        this.error = 'Укажите название новой папки.';
        return;
      }
      this.creatingFolder = true;
      try {
        const created = await this.request('/symbolika-mail/folders', {
          method: 'POST',
          body: JSON.stringify(this.newFolder),
        });
        this.newFolder = { name: '', imap_name: '', alias_email: '', employee: null, is_shared: false };
        this.settings.folders.push(created);
        this.notice = `Папка «${created.name}» создана.`;
        await this.loadMailbox(false, true);
      } catch (error) {
        this.error = error.message;
      } finally {
        this.creatingFolder = false;
      }
    },

    async saveEmployeeSignature(employee) {
      this.savingSignatureEmployeeId = employee.id;
      try {
        const result = await this.request(`/symbolika-mail/employees/${employee.id}/signature`, {
          method: 'PATCH', body: JSON.stringify({ signature: employee.email_signature || '' }),
        });
        employee.email_signature = result.signature;
        if (Number(employee.id) === Number(this.actor?.employee_id)) this.actor.signature = result.signature;
        this.notice = `Подпись сотрудника «${employee.full_name}» сохранена.`;
      } catch (error) {
        this.error = error.message;
      } finally {
        this.savingSignatureEmployeeId = null;
      }
    },

    openEntity(type, id) {
      if (!id) return;
      const targets = {
        order: `/admin/symbolika-orders?order=${id}`,
        customer: `/admin/symbolika-orders?customer=${id}`,
        company: `/admin/symbolika-orders?company=${id}`,
        task: `/admin/symbolika-tasks?task=${id}`,
      };
      if (targets[type]) window.location.assign(targets[type]);
    },

    displayParticipant(thread) {
      const participant = thread?.participants?.[0] || {};
      return participant.name || participant.email || 'Неизвестный отправитель';
    },

    participantEmail(thread) {
      return thread?.participants?.[0]?.email || '';
    },

    initials(value) {
      return String(value || '?').split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]).join('').toUpperCase();
    },

    formatDate(value, full = false) {
      if (!value) return '';
      const date = new Date(value);
      const today = new Date();
      if (!full && date.toDateString() === today.toDateString()) {
        return date.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
      }
      return date.toLocaleString('ru-RU', full
        ? { day: '2-digit', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit' }
        : { day: '2-digit', month: 'short' });
    },

    formatBytes(value) {
      const bytes = Number(value || 0);
      if (!bytes) return '';
      if (bytes < 1024) return `${bytes} Б`;
      if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} КБ`;
      return `${(bytes / 1024 / 1024).toFixed(1).replace('.', ',')} МБ`;
    },

    installStyles() {
      if (document.getElementById('symbolika-mail-styles')) return;
      const style = document.createElement('style');
      style.id = 'symbolika-mail-styles';
      style.textContent = `
        .symbolika-mail-page { inline-size: 100%; block-size: 100%; min-inline-size: 0; min-block-size: 0; color: var(--theme--foreground); }
        body:has(.symbolika-mail-page) .main-split > .sp-end,
        body:has(.symbolika-mail-page) .private-view-sidebar,
        body:has(.symbolika-mail-page) .private-view__sidebar,
        body:has(.symbolika-mail-page) .content-sidebar,
        body:has(.symbolika-mail-page) aside.sidebar,
        body:has(.symbolika-mail-page) .sidebar.right,
        body:has(.symbolika-mail-page) .sidebar-detail,
        body:has(.symbolika-mail-page) #sidebar-mobile-outlet,
        body:has(.symbolika-mail-page) .container.right,
        body:has(.symbolika-mail-page) .module-page .sidebar {
          display: none !important;
          inline-size: 0 !important;
          min-inline-size: 0 !important;
          max-inline-size: 0 !important;
        }
        body:has(.symbolika-mail-page) .private-view,
        body:has(.symbolika-mail-page) .module-page,
        body:has(.symbolika-mail-page) .main-container,
        body:has(.symbolika-mail-page) .content-wrapper,
        body:has(.symbolika-mail-page) .private-view__content,
        body:has(.symbolika-mail-page) .module-page > .content,
        body:has(.symbolika-mail-page) .main-split,
        body:has(.symbolika-mail-page) .main-split > .sp-start,
        body:has(.symbolika-mail-page) .main-split > .sp-start > .scrolling-container,
        body:has(.symbolika-mail-page) .main-split .main-content-container,
        body:has(.symbolika-mail-page) main {
          inline-size: 100% !important;
          max-inline-size: none !important;
          margin-inline-end: 0 !important;
          padding-inline-end: 0 !important;
        }
        body:has(.symbolika-mail-page) .main-split { grid-template-columns: minmax(0, 1fr) 0 0 !important; }
        body:has(.symbolika-mail-page) .module-bar,
        body:has(.symbolika-mail-page) .modules,
        body:has(.symbolika-mail-page) .module-bar-avatar {
          inline-size: 54px !important;
          min-inline-size: 54px !important;
          max-inline-size: 54px !important;
          overflow-x: hidden !important;
          scrollbar-width: none !important;
        }
        body:has(.symbolika-mail-page) .sp-root.root-split:not(.sp-collapsed) { grid-template-columns: 240px 0 minmax(0, 1fr) !important; }
        body:has(.symbolika-mail-page) .sp-root.root-split:not(.sp-collapsed) > .sp-start,
        body:has(.symbolika-mail-page) .sp-root.root-split:not(.sp-collapsed) .module-nav,
        body:has(.symbolika-mail-page) .sp-root.root-split:not(.sp-collapsed) nav[aria-label="Module Navigation"],
        body:has(.symbolika-mail-page) .sp-root.root-split:not(.sp-collapsed) .module-nav-content,
        body:has(.symbolika-mail-page) .sp-root.root-split:not(.sp-collapsed) .project-info {
          inline-size: 240px !important;
          min-inline-size: 240px !important;
          max-inline-size: 240px !important;
          overflow-x: hidden !important;
          scrollbar-width: none !important;
          box-sizing: border-box !important;
        }
        body:has(.symbolika-mail-page) .sp-root.root-split:not(.sp-collapsed) > .sp-divider {
          inline-size: 0 !important;
          min-inline-size: 0 !important;
          max-inline-size: 0 !important;
        }
        body:has(.symbolika-mail-page) .symbolika-mail-side-nav {
          inline-size: 100% !important;
          min-inline-size: 0 !important;
          max-inline-size: 100% !important;
          overflow-x: hidden !important;
          scrollbar-width: none !important;
          box-sizing: border-box !important;
        }
        body:has(.symbolika-mail-page) .symbolika-mail-side-nav *,
        body:has(.symbolika-mail-page) .module-nav *,
        body:has(.symbolika-mail-page) nav[aria-label="Module Navigation"] * {
          box-sizing: border-box !important;
          min-inline-size: 0;
        }
        body:has(.symbolika-mail-page) .module-bar::-webkit-scrollbar,
        body:has(.symbolika-mail-page) .modules::-webkit-scrollbar,
        body:has(.symbolika-mail-page) .module-bar-avatar::-webkit-scrollbar,
        body:has(.symbolika-mail-page) .module-nav::-webkit-scrollbar,
        body:has(.symbolika-mail-page) .module-nav-content::-webkit-scrollbar,
        body:has(.symbolika-mail-page) .project-info::-webkit-scrollbar,
        body:has(.symbolika-mail-page) .symbolika-mail-side-nav::-webkit-scrollbar,
        body:has(.symbolika-mail-page) nav[aria-label="Module Navigation"]::-webkit-scrollbar {
          inline-size: 0 !important;
          block-size: 0 !important;
        }
        .symbolika-mail-shell { display: grid; grid-template-rows: auto minmax(0, 1fr); block-size: calc(100vh - 64px); min-block-size: 620px; overflow: hidden; background: var(--theme--background); }
        .symbolika-mail-topbar { position: relative; z-index: 6; display: grid; grid-template-columns: minmax(280px, 560px) minmax(0, 1fr); align-items: center; gap: 18px; min-block-size: 72px; padding: 12px 20px; border-block-end: 1px solid var(--theme--border-color-subdued); background: color-mix(in srgb, var(--theme--background) 92%, transparent); box-shadow: 0 10px 30px rgb(0 0 0 / .08); backdrop-filter: blur(18px); }
        .symbolika-mail-search-wrap { position: relative; }
        .symbolika-mail-search-wrap .v-icon { position: absolute; inset: 50% auto auto 15px; translate: 0 -50%; color: var(--theme--foreground-subdued); pointer-events: none; }
        .symbolika-mail-search { inline-size: 100%; block-size: 44px; padding: 0 42px; border: 1px solid var(--theme--border-color); border-radius: 13px; outline: none; background: color-mix(in srgb, var(--theme--background-subdued) 92%, var(--theme--background)); color: var(--theme--foreground); font: inherit; box-shadow: inset 0 1px rgb(255 255 255 / .025); }
        .symbolika-mail-search:focus { border-color: #F97316; box-shadow: 0 0 0 3px rgb(249 115 22 / .14); }
        .symbolika-mail-top-actions { display: flex; align-items: center; justify-content: flex-end; gap: 8px; min-inline-size: 0; }
        .symbolika-mail-sync-state { display: grid; gap: 1px; min-inline-size: 104px; color: var(--theme--foreground-subdued); font-size: 9px; line-height: 1.2; text-align: end; white-space: nowrap; }
        .symbolika-mail-sync-state strong { color: var(--theme--foreground); font-size: 10px; font-weight: 760; }
        .symbolika-mail-button, .symbolika-mail-icon-button { display: inline-flex; align-items: center; justify-content: center; gap: 8px; min-block-size: 42px; padding: 0 15px; border: 1px solid var(--theme--border-color); border-radius: 11px; background: var(--theme--background-normal); color: var(--theme--foreground); font-weight: 750; cursor: pointer; }
        .symbolika-mail-button:hover, .symbolika-mail-icon-button:hover { border-color: #F97316; color: #FB923C; }
        .symbolika-mail-button.is-primary { border-color: #F97316; background: #FF8438; color: #17120F; }
        .symbolika-mail-button.is-primary,
        .symbolika-mail-button.is-primary * { color: #17120F !important; -webkit-text-fill-color: #17120F !important; }
        .symbolika-mail-button.is-primary:hover { background: #FB923C; color: #17120F; }
        .symbolika-mail-icon-button { inline-size: 42px; padding: 0; }
        .symbolika-mail-button:disabled, .symbolika-mail-icon-button:disabled { opacity: .55; cursor: wait; }
        .symbolika-mail-content { display: grid; grid-template-columns: minmax(330px, 400px) minmax(0, 1fr); min-block-size: 0; overflow: hidden; }
        .symbolika-mail-list { min-inline-size: 0; overflow: auto; border-inline-end: 1px solid var(--theme--border-color-subdued); background: color-mix(in srgb, var(--theme--background-subdued) 82%, var(--theme--background)); scrollbar-width: thin; }
        .symbolika-mail-list-head { position: sticky; z-index: 4; inset-block-start: 0; display: grid; gap: 10px; padding: 14px 14px 11px; border-block-end: 1px solid var(--theme--border-color-subdued); background: color-mix(in srgb, var(--theme--background-subdued) 94%, transparent); backdrop-filter: blur(16px); }
        .symbolika-mail-list-title { display: flex; align-items: center; justify-content: space-between; gap: 10px; min-inline-size: 0; }
        .symbolika-mail-list-title strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 15px; }
        .symbolika-mail-list-count { display: inline-flex; align-items: center; justify-content: center; min-inline-size: 42px; block-size: 28px; padding-inline: 10px; border: 1px solid var(--theme--border-color-subdued); border-radius: 999px; background: var(--theme--background-normal); color: var(--theme--foreground); font-size: 10px; font-weight: 850; font-variant-numeric: tabular-nums; }
        .symbolika-mail-scopes { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 5px; }
        .symbolika-mail-scope { display: inline-flex; align-items: center; justify-content: center; gap: 5px; min-inline-size: 0; min-block-size: 30px; padding: 0 7px; border: 1px solid transparent; border-radius: 8px; background: transparent; color: var(--theme--foreground-subdued); font-size: 10px; font-weight: 760; cursor: pointer; }
        .symbolika-mail-scope:hover { background: var(--theme--background-normal); color: var(--theme--foreground); }
        .symbolika-mail-scope.is-active { border-color: rgb(249 115 22 / .32); background: rgb(249 115 22 / .12); color: #FB923C; }
        .symbolika-mail-scope small { display: inline-grid; place-items: center; min-inline-size: 18px; block-size: 18px; padding-inline: 4px; border-radius: 999px; background: var(--theme--background-accent); color: inherit; font-size: 8px; }
        .symbolika-mail-mode { display: inline-flex; align-items: center; gap: 5px; padding: 5px 8px; border-radius: 999px; background: rgb(249 115 22 / .12); color: #FB923C; font-size: 10px; font-weight: 850; text-transform: uppercase; letter-spacing: .04em; }
        .symbolika-mail-refresh-note { color: var(--theme--foreground-subdued); font-size: 10px; white-space: nowrap; }
        .symbolika-mail-thread { position: relative; display: grid; grid-template-columns: 42px minmax(0, 1fr) auto; gap: 11px; inline-size: calc(100% - 14px); margin: 7px; padding: 13px 12px; border: 1px solid transparent; border-radius: 12px; background: transparent; color: inherit; text-align: start; cursor: pointer; transition: border-color .16s ease, background .16s ease, transform .16s ease; }
        .symbolika-mail-thread:hover { border-color: var(--theme--border-color-subdued); background: var(--theme--background-normal); transform: translateY(-1px); }
        .symbolika-mail-thread.is-active { border-color: rgb(249 115 22 / .35); background: color-mix(in srgb, #F97316 11%, var(--theme--background-normal)); box-shadow: inset 3px 0 #F97316, 0 8px 22px rgb(0 0 0 / .08); }
        .symbolika-mail-thread.is-unread::after { position: absolute; inset: 11px 10px auto auto; inline-size: 6px; block-size: 6px; border-radius: 999px; background: #FB923C; content: ''; box-shadow: 0 0 0 3px rgb(249 115 22 / .12); }
        .symbolika-mail-thread.is-unread .symbolika-mail-thread-name, .symbolika-mail-thread.is-unread .symbolika-mail-thread-subject { color: var(--theme--foreground); font-weight: 850; }
        .symbolika-mail-avatar { display: grid; place-items: center; inline-size: 42px; block-size: 42px; border-radius: 12px; background: color-mix(in srgb, #F97316 17%, var(--theme--background-normal)); color: #FB923C; font-size: 12px; font-weight: 900; }
        .symbolika-mail-thread-main { min-inline-size: 0; }
        .symbolika-mail-thread-row { display: flex; align-items: center; gap: 7px; min-inline-size: 0; }
        .symbolika-mail-thread-name, .symbolika-mail-thread-subject, .symbolika-mail-thread-preview { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .symbolika-mail-thread-name { color: var(--theme--foreground-subdued); font-size: 12px; font-weight: 750; }
        .symbolika-mail-thread-subject { margin-block-start: 3px; font-size: 13px; font-weight: 720; }
        .symbolika-mail-thread-preview { margin-block-start: 4px; color: var(--theme--foreground-subdued); font-size: 11px; line-height: 1.35; }
        .symbolika-mail-thread-time { padding-inline-end: 7px; color: var(--theme--foreground-subdued); font-size: 9px; white-space: nowrap; }
        .symbolika-mail-star { color: #F59E0B; }
        .symbolika-mail-reader { position: relative; min-inline-size: 0; overflow: auto; background: radial-gradient(circle at 50% 0, rgb(249 115 22 / .035), transparent 34%), var(--theme--background); scrollbar-width: thin; }
        .symbolika-mail-reader-empty { display: grid; place-items: center; min-block-size: 100%; padding: 40px; color: var(--theme--foreground-subdued); text-align: center; }
        .symbolika-mail-empty-illustration { display: grid; place-items: center; inline-size: 72px; block-size: 72px; margin-inline: auto; border: 1px solid rgb(249 115 22 / .25); border-radius: 22px; background: rgb(249 115 22 / .08); }
        .symbolika-mail-reader-empty .v-icon { color: #F97316; opacity: .65; }
        .symbolika-mail-reader-empty strong { display: block; margin-block: 14px 5px; color: var(--theme--foreground); font-size: 19px; }
        .symbolika-mail-reader-head { position: sticky; z-index: 3; inset-block-start: 0; padding: 17px 22px 13px; border-block-end: 1px solid var(--theme--border-color-subdued); background: color-mix(in srgb, var(--theme--background) 94%, transparent); box-shadow: 0 8px 28px rgb(0 0 0 / .06); backdrop-filter: blur(18px); }
        .symbolika-mail-reader-title-row { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; }
        .symbolika-mail-reader-title { min-inline-size: 0; }
        .symbolika-mail-reader-title h2 { margin: 0; color: var(--theme--foreground); font-size: clamp(17px, 1.65vw, 23px); line-height: 1.25; }
        .symbolika-mail-reader-title p { display: flex; align-items: center; gap: 6px; margin: 6px 0 0; color: var(--theme--foreground-subdued); font-size: 11px; }
        .symbolika-mail-reader-title p::before { inline-size: 7px; block-size: 7px; border-radius: 999px; background: #34D399; content: ''; box-shadow: 0 0 0 3px rgb(52 211 153 / .10); }
        .symbolika-mail-reader-actions { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 6px; flex: 0 0 auto; }
        .symbolika-mail-back { display: none; }
        .symbolika-mail-links { display: flex; flex-wrap: wrap; gap: 6px; margin-block-start: 12px; padding-block-start: 11px; border-block-start: 1px solid var(--theme--border-color-subdued); }
        .symbolika-mail-links-label { display: inline-flex; align-items: center; min-block-size: 28px; margin-inline-end: 2px; color: var(--theme--foreground-subdued); font-size: 9px; font-weight: 850; text-transform: uppercase; letter-spacing: .06em; }
        .symbolika-mail-link { display: inline-flex; align-items: center; gap: 6px; min-block-size: 28px; padding: 0 9px; border: 1px solid var(--theme--border-color); border-radius: 8px; background: var(--theme--background-normal); color: var(--theme--foreground); font-size: 11px; font-weight: 750; cursor: pointer; }
        .symbolika-mail-link:hover { border-color: #F97316; color: #FB923C; }
        .symbolika-mail-link.is-action { border-style: dashed; }
        .symbolika-mail-link.is-payment { border-color: rgb(245 158 11 / .45); color: #FBBF24; }
        .symbolika-mail-tag { display: inline-flex; align-items: center; gap: 4px; min-block-size: 28px; padding: 0 9px; border-radius: 999px; background: rgb(59 130 246 / .14); color: #93C5FD; font-size: 10px; font-weight: 800; }
        .symbolika-mail-messages { display: grid; gap: 14px; max-inline-size: 980px; margin-inline: auto; padding: 22px 26px 92px; }
        .symbolika-mail-message { position: relative; padding: 17px 18px; border: 1px solid var(--theme--border-color-subdued); border-radius: 16px; background: color-mix(in srgb, var(--theme--background-subdued) 92%, var(--theme--background)); box-shadow: 0 10px 30px rgb(0 0 0 / .06); }
        .symbolika-mail-message.is-outbound { margin-inline-start: clamp(24px, 7vw, 94px); border-color: rgb(249 115 22 / .30); background: linear-gradient(135deg, rgb(249 115 22 / .09), transparent 48%), var(--theme--background-subdued); }
        .symbolika-mail-message:not(.is-outbound) { margin-inline-end: clamp(24px, 4vw, 56px); }
        .symbolika-mail-message.is-outbound::before { position: absolute; inset: 17px auto auto -1px; inline-size: 3px; block-size: 38px; border-radius: 0 4px 4px 0; background: #F97316; content: ''; }
        .symbolika-mail-message-head { display: grid; grid-template-columns: 38px minmax(0, 1fr) auto; align-items: center; gap: 10px; }
        .symbolika-mail-message-head .symbolika-mail-avatar { inline-size: 38px; block-size: 38px; border-radius: 10px; }
        .symbolika-mail-message-from { min-inline-size: 0; }
        .symbolika-mail-message-from strong, .symbolika-mail-message-from small { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .symbolika-mail-message-from strong { font-size: 13px; }
        .symbolika-mail-message-from small, .symbolika-mail-message time { color: var(--theme--foreground-subdued); font-size: 10px; }
        .symbolika-mail-message-body { margin-block-start: 15px; color: var(--theme--foreground); font-size: 13px; line-height: 1.65; overflow-wrap: anywhere; }
        .symbolika-mail-message-body-frame { display: block; inline-size: 100%; min-block-size: 100px; border: 0; background: transparent; color-scheme: light dark; }
        .symbolika-mail-attachments { display: flex; flex-wrap: wrap; gap: 8px; margin-block-start: 14px; }
        .symbolika-mail-attachment { display: grid; grid-template-columns: 32px minmax(0, 1fr) auto; align-items: center; gap: 8px; min-inline-size: 220px; max-inline-size: 380px; padding: 8px 10px; border: 1px solid var(--theme--border-color); border-radius: 10px; background: var(--theme--background-normal); }
        .symbolika-mail-attachment .v-icon { color: #FB923C; }
        .symbolika-mail-attachment strong, .symbolika-mail-attachment small { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .symbolika-mail-attachment strong { font-size: 11px; }
        .symbolika-mail-attachment small { color: var(--theme--foreground-subdued); font-size: 9px; }
        .symbolika-mail-attachment-actions { display: flex; align-items: center; gap: 4px; }
        .symbolika-mail-attachment-action { display: grid; place-items: center; inline-size: 30px; block-size: 30px; border: 1px solid var(--theme--border-color); border-radius: 8px; color: var(--theme--foreground); background: var(--theme--background); text-decoration: none; }
        .symbolika-mail-attachment-action:hover { border-color: #F97316; color: #F97316; }
        .symbolika-mail-reply-bar { position: sticky; z-index: 4; inset-block-end: 0; display: flex; justify-content: flex-end; padding: 12px 22px; border-block-start: 1px solid var(--theme--border-color-subdued); background: color-mix(in srgb, var(--theme--background) 91%, transparent); box-shadow: 0 -12px 30px rgb(0 0 0 / .08); backdrop-filter: blur(16px); }
        .symbolika-mail-alert { position: fixed; z-index: 10050; inset: 76px 24px auto auto; max-inline-size: min(460px, calc(100vw - 32px)); padding: 11px 14px; border: 1px solid #10B981; border-radius: 10px; background: color-mix(in srgb, #10B981 16%, var(--theme--background-normal)); color: #6EE7B7; font-size: 12px; font-weight: 750; box-shadow: 0 14px 40px rgb(0 0 0 / .25); pointer-events: none; }
        .symbolika-mail-alert.is-error { display: grid; grid-template-columns: 30px minmax(0, 1fr) 26px; align-items: center; gap: 10px; min-block-size: 58px; border-color: #F43F5E; background: color-mix(in srgb, #F43F5E 15%, var(--theme--background-normal)); color: var(--theme--foreground); animation: symbolika-mail-error-in .18s ease-out; pointer-events: auto; }
        .symbolika-mail-alert.is-error > .v-icon:first-child { color: #F43F5E; }
        .symbolika-mail-alert-error-copy { display: grid; gap: 2px; min-inline-size: 0; }
        .symbolika-mail-alert-error-copy strong { color: #F43F5E; font-size: 12px; }
        .symbolika-mail-alert-error-copy span { overflow-wrap: anywhere; line-height: 1.35; }
        .symbolika-mail-alert-close { display: grid; place-items: center; inline-size: 26px; block-size: 26px; padding: 0; border: 0; border-radius: 7px; background: transparent; color: var(--theme--foreground-subdued); cursor: pointer; }
        .symbolika-mail-alert-close:hover { background: color-mix(in srgb, #F43F5E 14%, transparent); color: #F43F5E; }
        @keyframes symbolika-mail-error-in { from { opacity: 0; transform: translateY(-8px) scale(.985); } to { opacity: 1; transform: translateY(0) scale(1); } }
        .symbolika-mail-overlay { position: fixed; z-index: 1000; inset: 0; display: grid; place-items: center; padding: 22px; background: rgb(4 8 12 / .68); backdrop-filter: blur(5px); }
        .symbolika-mail-overlay.is-signature { z-index: 1100; }
        .symbolika-mail-dialog { display: grid; grid-template-rows: auto minmax(0, 1fr) auto; inline-size: min(720px, 100%); max-block-size: min(820px, calc(100vh - 44px)); overflow: hidden; border: 1px solid var(--theme--border-color); border-radius: 18px; background: var(--theme--background-normal); box-shadow: 0 30px 100px rgb(0 0 0 / .55); }
        .symbolika-mail-dialog.is-compose { inline-size: min(800px, 100%); }
        .symbolika-mail-dialog.is-settings { inline-size: min(1050px, 100%); }
        .symbolika-mail-dialog.is-signature-editor { inline-size: min(1220px, 100%); }
        .symbolika-mail-dialog-head, .symbolika-mail-dialog-actions { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 15px 18px; border-block-end: 1px solid var(--theme--border-color-subdued); }
        .symbolika-mail-dialog-head h2 { margin: 0; font-size: 18px; }
        .symbolika-mail-dialog-actions { justify-content: flex-end; border-block: 1px solid var(--theme--border-color-subdued) 0; border-block-start: 1px solid var(--theme--border-color-subdued); }
        .symbolika-mail-dialog-body { min-block-size: 0; overflow: auto; padding: 17px 18px; }
        .symbolika-mail-field { display: grid; gap: 6px; margin-block-end: 12px; color: var(--theme--foreground-subdued); font-size: 10px; font-weight: 800; text-transform: uppercase; letter-spacing: .03em; }
        .symbolika-mail-input, .symbolika-mail-select, .symbolika-mail-textarea { inline-size: 100%; min-block-size: 42px; padding: 9px 11px; border: 1px solid var(--theme--border-color); border-radius: 10px; outline: none; background: var(--theme--background); color: var(--theme--foreground); font: inherit; text-transform: none; letter-spacing: normal; }
        .symbolika-mail-textarea { min-block-size: 230px; resize: vertical; line-height: 1.55; }
        .symbolika-mail-textarea.is-compact { min-block-size: 120px; }
        .symbolika-mail-input:focus, .symbolika-mail-select:focus, .symbolika-mail-textarea:focus { border-color: #F97316; box-shadow: 0 0 0 3px rgb(249 115 22 / .12); }
        .symbolika-mail-field-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
        .symbolika-mail-address-grid { display: grid; grid-template-columns: minmax(220px, .8fr) minmax(280px, 1.2fr); gap: 12px; }
        .symbolika-mail-compose-hint { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-block-start: -3px; color: var(--theme--foreground-subdued); font-size: 9px; }
        .symbolika-mail-help { margin: 0 0 16px; padding: 11px 13px; border: 1px solid rgb(249 115 22 / .28); border-radius: 10px; background: rgb(249 115 22 / .07); color: var(--theme--foreground-subdued); font-size: 12px; line-height: 1.5; }
        .symbolika-mail-signature-preview { margin-block: 9px 14px; padding: 12px; border-inline-start: 3px solid #F97316; background: var(--theme--background-subdued); color: var(--theme--foreground-subdued); font-size: 12px; white-space: pre-wrap; }
        .symbolika-mail-signature-preview small { display: block; margin-block-end: 7px; color: #FB923C; font-size: 9px; font-weight: 850; text-transform: uppercase; }
        .symbolika-mail-signature-preview div { white-space: normal; }
        .symbolika-mail-branded-preview { margin-block: 12px 18px; padding: 14px; overflow: auto; border: 1px solid var(--theme--border-color-subdued); border-radius: 12px; background: #eef1f4; }
        .symbolika-mail-branded-preview > table { margin-inline: auto !important; }
        .symbolika-mail-signature-preview a, .symbolika-mail-signature-editor a { color: #F97316; text-decoration: underline; }
        .symbolika-mail-signature-designer { display: grid; grid-template-columns: minmax(420px, .9fr) minmax(500px, 1.1fr); gap: 18px; align-items: start; margin-block-end: 18px; }
        .symbolika-mail-signature-fields, .symbolika-mail-signature-live { padding: 16px; border: 1px solid var(--theme--border-color-subdued); border-radius: 14px; background: var(--theme--background-subdued); }
        .symbolika-mail-signature-section-head { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; margin-block-end: 14px; }
        .symbolika-mail-signature-section-head div { display: grid; gap: 3px; }
        .symbolika-mail-signature-section-head span { color: var(--theme--foreground-subdued); font-size: 10px; }
        .symbolika-mail-button.is-compact { min-block-size: 32px; padding: 6px 10px; font-size: 10px; white-space: nowrap; }
        .symbolika-mail-signature-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px 12px; }
        .symbolika-mail-signature-grid .is-wide { grid-column: 1 / -1; }
        .symbolika-mail-signature-live > strong { display: block; margin-block-end: 12px; }
        .symbolika-mail-signature-card { display: grid; grid-template-columns: minmax(145px, .7fr) minmax(180px, .9fr) minmax(210px, 1.1fr); overflow: hidden; min-block-size: 250px; border: 1px solid #3d4855; border-radius: 14px; background: #171c22; color: #f5f7fa; box-shadow: 0 14px 34px rgb(0 0 0 / .22); }
        .symbolika-mail-signature-brand, .symbolika-mail-signature-person, .symbolika-mail-signature-contacts { display: flex; flex-direction: column; justify-content: center; min-inline-size: 0; padding: 20px; }
        .symbolika-mail-signature-brand img { display: block; inline-size: 100%; max-inline-size: 175px; block-size: auto; margin: auto; }
        .symbolika-mail-signature-brand b { font-size: 21px; text-align: center; }
        .symbolika-mail-signature-person { border-inline-start: 2px solid #f97316; }
        .symbolika-mail-signature-person h3 { margin: 0; color: #f5f7fa; font-size: clamp(18px, 2vw, 24px); line-height: 1.08; overflow-wrap: anywhere; }
        .symbolika-mail-signature-person > b { margin-block-start: 6px; color: #f97316; font-size: 11px; letter-spacing: .08em; text-transform: uppercase; }
        .symbolika-mail-signature-person i { inline-size: 38px; block-size: 2px; margin-block: 15px; background: #f97316; }
        .symbolika-mail-signature-person p { margin: 0; color: #c3c9d1; font-size: 11px; font-style: italic; line-height: 1.55; }
        .symbolika-mail-signature-contacts { gap: 4px; }
        .symbolika-mail-signature-contacts a { display: grid; grid-template-columns: 28px minmax(0, 1fr); align-items: center; gap: 8px; min-block-size: 34px; color: #f5f7fa; text-decoration: none; }
        .symbolika-mail-signature-contacts a > b { color: #f97316; }
        .symbolika-mail-signature-contacts a span { padding-block: 7px; border-block-end: 1px solid #46515e; font-size: 11px; line-height: 1.35; overflow-wrap: anywhere; }
        .symbolika-mail-editor-shell { overflow: hidden; border: 1px solid var(--theme--border-color); border-radius: 12px; background: var(--theme--background); }
        .symbolika-mail-editor-toolbar { display: flex; flex-wrap: wrap; gap: 5px; padding: 8px; border-block-end: 1px solid var(--theme--border-color-subdued); background: var(--theme--background-subdued); }
        .symbolika-mail-editor-tool { display: inline-grid; place-items: center; min-inline-size: 34px; block-size: 32px; padding: 0 8px; border: 1px solid transparent; border-radius: 8px; background: transparent; color: var(--theme--foreground); font-size: 12px; font-weight: 800; cursor: pointer; }
        .symbolika-mail-editor-tool:hover { border-color: rgb(249 115 22 / .42); background: rgb(249 115 22 / .10); color: #F97316; }
        .symbolika-mail-editor-separator { inline-size: 1px; block-size: 24px; margin: 4px 2px; background: var(--theme--border-color); }
        .symbolika-mail-signature-editor { min-block-size: 180px; padding: 14px; outline: none; color: var(--theme--foreground); font-size: 13px; line-height: 1.55; overflow-wrap: anywhere; }
        .symbolika-mail-signature-editor:empty::before { color: var(--theme--foreground-subdued); content: attr(data-placeholder); pointer-events: none; }
        .symbolika-mail-signature-editor:focus { box-shadow: inset 0 0 0 2px rgb(249 115 22 / .38); }
        .symbolika-mail-link-editor { display: grid; grid-template-columns: 1fr 1.4fr auto auto; gap: 8px; margin-block-start: 10px; padding: 10px; border: 1px solid rgb(249 115 22 / .32); border-radius: 10px; background: rgb(249 115 22 / .06); }
        .symbolika-mail-settings-summary { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 10px; margin-block-end: 16px; }
        .symbolika-mail-settings-card { padding: 12px; border: 1px solid var(--theme--border-color-subdued); border-radius: 11px; background: var(--theme--background-subdued); }
        .symbolika-mail-settings-card small, .symbolika-mail-settings-card strong { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .symbolika-mail-settings-card small { color: var(--theme--foreground-subdued); font-size: 9px; text-transform: uppercase; }
        .symbolika-mail-settings-card strong { margin-block-start: 5px; font-size: 12px; }
        .symbolika-mail-settings-section { margin-block: 18px 8px; }
        .symbolika-mail-settings-section h3 { margin: 0; font-size: 15px; }
        .symbolika-mail-settings-section p { margin: 5px 0 0; color: var(--theme--foreground-subdued); font-size: 11px; }
        .symbolika-mail-signature-row { display: grid; grid-template-columns: 190px minmax(280px, 1fr) auto; align-items: center; gap: 10px; padding: 10px 0; border-block-start: 1px solid var(--theme--border-color-subdued); }
        .symbolika-mail-signature-row strong, .symbolika-mail-signature-row small { display: block; }
        .symbolika-mail-signature-row small { margin-block-start: 4px; color: var(--theme--foreground-subdued); font-size: 10px; }
        .symbolika-mail-signature-summary { min-block-size: 52px; max-block-size: 76px; overflow: hidden; padding: 9px 11px; border: 1px solid var(--theme--border-color-subdued); border-radius: 9px; background: var(--theme--background); color: var(--theme--foreground-subdued); font-size: 11px; line-height: 1.4; }
        .symbolika-mail-settings-folder { display: grid; grid-template-columns: 1.1fr 1.2fr 1.2fr 1fr auto auto; align-items: end; gap: 9px; padding: 12px 0; border-block-start: 1px solid var(--theme--border-color-subdued); }
        .symbolika-mail-settings-folder.is-new { margin-block: 12px 4px; padding: 14px; border: 1px dashed rgb(249 115 22 / .45); border-radius: 12px; background: rgb(249 115 22 / .055); }
        .symbolika-mail-settings-folder.is-new .symbolika-mail-button { border-color: #F97316; }
        .symbolika-mail-checkbox { display: inline-flex; align-items: center; gap: 7px; min-block-size: 42px; color: var(--theme--foreground); font-size: 11px; font-weight: 700; white-space: nowrap; }
        .symbolika-mail-loading { display: grid; place-items: center; min-block-size: 240px; color: var(--theme--foreground-subdued); }
        .symbolika-mail-empty-list { padding: 38px 20px; color: var(--theme--foreground-subdued); text-align: center; font-size: 12px; }
        .symbolika-mail-side-nav { display: flex; flex-direction: column; inline-size: 100%; min-inline-size: 0; max-inline-size: 100%; block-size: 100%; padding: 16px 12px; overflow-x: hidden; overflow-y: auto; box-sizing: border-box; background: linear-gradient(180deg, rgb(249 115 22 / .035), transparent 180px), color-mix(in srgb, var(--theme--background-subdued) 88%, var(--theme--background)); }
        .symbolika-mail-side-title { display: flex; align-items: center; justify-content: space-between; padding: 3px 8px 15px; font-size: 18px; font-weight: 900; }
        .symbolika-mail-side-title span { display: inline-flex; align-items: center; gap: 8px; }
        .symbolika-mail-side-title span::before { inline-size: 9px; block-size: 9px; border-radius: 3px; background: #F97316; content: ''; box-shadow: 0 0 0 4px rgb(249 115 22 / .11); }
        .symbolika-mail-side-title small { display: inline-flex; align-items: center; justify-content: center; min-inline-size: 48px; block-size: 28px; padding-inline: 10px; border: 1px solid rgb(249 115 22 / .40); border-radius: 999px; background: rgb(249 115 22 / .14); color: #FB923C; font-size: 10px; font-weight: 900; font-variant-numeric: tabular-nums; white-space: nowrap; }
        .symbolika-mail-side-compose { inline-size: 100%; min-block-size: 44px; margin-block-end: 15px; border-radius: 12px; box-shadow: 0 8px 22px rgb(249 115 22 / .16); }
        .symbolika-mail-side-section-label { padding: 3px 9px 7px; color: var(--theme--foreground-subdued); font-size: 9px; font-weight: 850; text-transform: uppercase; letter-spacing: .08em; }
        .symbolika-mail-side-folder { display: grid; grid-template-columns: 24px minmax(0, 1fr) auto; align-items: center; gap: 8px; inline-size: 100%; min-block-size: 40px; margin-block-end: 2px; padding: 0 10px; border: 1px solid transparent; border-radius: 10px; background: transparent; color: var(--theme--foreground-subdued); text-align: start; cursor: pointer; }
        .symbolika-mail-side-folder:hover { background: var(--theme--background-normal); color: var(--theme--foreground); }
        .symbolika-mail-side-folder.is-active { border-color: rgb(249 115 22 / .25); background: color-mix(in srgb, #F97316 14%, var(--theme--background-normal)); color: #FB923C; box-shadow: inset 3px 0 #F97316; }
        .symbolika-mail-side-folder span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 12px; font-weight: 750; }
        .symbolika-mail-side-folder small { display: inline-flex; align-items: center; justify-content: center; min-inline-size: 30px; block-size: 22px; padding-inline: 8px; border: 1px solid var(--theme--border-color-subdued); border-radius: 999px; background: var(--theme--background-normal); color: var(--theme--foreground); text-align: center; font-size: 9px; font-weight: 850; font-variant-numeric: tabular-nums; }
        .symbolika-mail-side-folder.is-active small { border-color: rgb(249 115 22 / .35); background: rgb(249 115 22 / .12); color: #FB923C; }
        .symbolika-mail-side-footer { margin-block-start: auto; padding-block-start: 13px; border-block-start: 1px solid var(--theme--border-color-subdued); }
        html:is([data-symbolika-theme="pearl"], [data-symbolika-theme="frost"]) .symbolika-mail-mode,
        html:is([data-symbolika-theme="pearl"], [data-symbolika-theme="frost"]) .symbolika-mail-side-folder.is-active {
          color: #9a430f;
        }
        html:is([data-symbolika-theme="pearl"], [data-symbolika-theme="frost"]) .symbolika-mail-tag {
          background: rgb(21 95 160 / .11);
          color: #124f85;
        }
        html:is([data-symbolika-theme="pearl"], [data-symbolika-theme="frost"]) .symbolika-mail-link.is-payment {
          color: #704900;
        }
        html:is([data-symbolika-theme="pearl"], [data-symbolika-theme="frost"]) .symbolika-mail-alert {
          color: #075f4b;
        }
        html:is([data-symbolika-theme="pearl"], [data-symbolika-theme="frost"]) .symbolika-mail-alert.is-error {
          color: #9a1e36;
        }
        html:is([data-symbolika-theme="pearl"], [data-symbolika-theme="frost"]) .symbolika-mail-thread.is-active {
          border-color: rgb(194 83 16 / .38);
          background: rgb(249 115 22 / .10);
        }
        html:is([data-symbolika-theme="pearl"], [data-symbolika-theme="frost"]) .symbolika-mail-scope.is-active,
        html:is([data-symbolika-theme="pearl"], [data-symbolika-theme="frost"]) .symbolika-mail-reader-title p::before {
          color: #9a430f;
        }
        @media (max-width: 1500px) {
          .symbolika-mail-sync-state { min-inline-size: 72px; }
          .symbolika-mail-sync-state > span { display: none; }
        }
        @media (max-width: 1100px) {
          .symbolika-mail-signature-designer { grid-template-columns: 1fr; }
          .symbolika-mail-content { grid-template-columns: 300px minmax(0, 1fr); }
          .symbolika-mail-topbar { grid-template-columns: minmax(260px, 1fr) auto; gap: 10px; padding-inline: 14px; }
          .symbolika-mail-sync-state, .symbolika-mail-top-actions > .symbolika-mail-mode { display: none; }
          .symbolika-mail-reader-actions .symbolika-mail-button-label { display: none; }
          .symbolika-mail-settings-summary { grid-template-columns: repeat(2, minmax(0, 1fr)); }
          .symbolika-mail-settings-folder { grid-template-columns: 1fr 1fr; }
          .symbolika-mail-signature-row { grid-template-columns: 160px minmax(240px, 1fr); }
          .symbolika-mail-signature-row > button { grid-column: 2; justify-self: end; }
          .symbolika-mail-settings-folder > button { justify-self: end; }
        }
        @media (max-width: 760px) {
          .symbolika-mail-signature-grid { grid-template-columns: 1fr; }
          .symbolika-mail-signature-grid .is-wide { grid-column: auto; }
          .symbolika-mail-signature-section-head { display: grid; }
          .symbolika-mail-signature-card { grid-template-columns: 1fr; }
          .symbolika-mail-signature-person { border-inline-start: 0; border-block: 1px solid #46515e; }
          .symbolika-mail-shell { block-size: calc(100vh - 56px); }
          .symbolika-mail-topbar { grid-template-columns: minmax(0, 1fr) auto; min-block-size: 62px; padding: 8px 10px; }
          .symbolika-mail-top-actions { justify-content: flex-end; overflow: visible; }
          .symbolika-mail-top-actions > :is(.symbolika-mail-refresh-note, .symbolika-mail-icon-button, .symbolika-mail-mode) { display: none; }
          .symbolika-mail-top-actions .symbolika-mail-button { inline-size: 42px; padding: 0; }
          .symbolika-mail-top-actions .symbolika-mail-button-label { display: none; }
          .symbolika-mail-search { block-size: 42px; }
          .symbolika-mail-content { display: grid; grid-template-columns: 1fr; overflow: auto; }
          .symbolika-mail-list { display: ${'block'}; min-block-size: 100%; border: 0; }
          .symbolika-mail-reader { min-block-size: 100%; }
          .symbolika-mail-content:has(.symbolika-mail-reader-head) .symbolika-mail-list { display: none; }
          .symbolika-mail-reader-head, .symbolika-mail-messages { padding-inline: 14px; }
          .symbolika-mail-reader-title-row { display: grid; grid-template-columns: auto minmax(0, 1fr); }
          .symbolika-mail-reader-title { min-inline-size: 0; }
          .symbolika-mail-reader-title h2 { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
          .symbolika-mail-reader-actions { grid-column: 1 / -1; justify-content: flex-start; }
          .symbolika-mail-back { display: inline-flex; align-self: start; }
          .symbolika-mail-links { overflow-x: auto; flex-wrap: nowrap; padding-block-end: 2px; }
          .symbolika-mail-links > * { flex: 0 0 auto; }
          .symbolika-mail-message.is-outbound { margin-inline-start: 12px; }
          .symbolika-mail-message:not(.is-outbound) { margin-inline-end: 8px; }
          .symbolika-mail-message-head { grid-template-columns: 34px minmax(0, 1fr); }
          .symbolika-mail-message-head time { grid-column: 2; }
          .symbolika-mail-reply-bar { padding: 10px 14px; }
          .symbolika-mail-settings-summary { grid-template-columns: 1fr; }
          .symbolika-mail-settings-folder { grid-template-columns: 1fr; }
          .symbolika-mail-signature-row { grid-template-columns: 1fr; }
          .symbolika-mail-signature-row > button { grid-column: auto; }
          .symbolika-mail-field-grid { grid-template-columns: 1fr; }
          .symbolika-mail-address-grid { grid-template-columns: 1fr; gap: 0; }
          .symbolika-mail-link-editor { grid-template-columns: 1fr; }
        }
        @media (max-width: 520px) {
          .symbolika-mail-reader-head { padding-inline: 10px; }
          .symbolika-mail-links { flex-wrap: wrap; overflow-x: visible; }
          .symbolika-mail-links-label { flex-basis: 100%; min-block-size: 20px; }
          .symbolika-mail-messages { padding-inline: 10px; }
          .symbolika-mail-message { padding: 14px; }
          .symbolika-mail-message.is-outbound,
          .symbolika-mail-message:not(.is-outbound) { margin-inline: 0; }
          .symbolika-mail-dialog { max-block-size: calc(100vh - 16px); border-radius: 14px; }
          .symbolika-mail-overlay { padding: 8px; }
        }
      `;
      document.head.appendChild(style);
    },
  },

  template: `
    <private-view title="Почта">
      <template #navigation>
        <nav class="symbolika-mail-side-nav" aria-label="Почтовые папки">
          <div class="symbolika-mail-side-title">
            <span>Почта</span>
            <small v-if="totalUnread">{{ totalUnread }} новых</small>
          </div>
          <button type="button" class="symbolika-mail-button is-primary symbolika-mail-side-compose" @click="openComposer()">
            <v-icon name="edit" small /> Написать
          </button>
          <div class="symbolika-mail-side-section-label">Быстрый доступ</div>
          <button
            type="button"
            class="symbolika-mail-side-folder"
            :class="{ 'is-active': mailboxScope === 'starred' }"
            @click="selectStarred"
          >
            <v-icon name="star" small />
            <span>Избранное</span>
            <small v-if="totalStarred">{{ totalStarred }}</small>
          </button>
          <div class="symbolika-mail-side-section-label">Папки</div>
          <button
            v-for="folder in folders"
            :key="folder.id"
            type="button"
            class="symbolika-mail-side-folder"
            :class="{ 'is-active': mailboxScope === 'folder' && Number(folder.id) === Number(selectedFolderId) }"
            @click="selectFolder(folder)"
          >
            <v-icon :name="folder.slug === 'inbox' ? 'inbox' : folder.slug === 'sent' ? 'send' : folder.slug === 'archive' ? 'archive' : 'folder'" small />
            <span>{{ folder.name }}</span>
            <small v-if="folder.unread">{{ folder.unread }}</small>
          </button>
          <div class="symbolika-mail-side-footer">
            <button type="button" class="symbolika-mail-side-folder" @click="openSignatureDialog">
              <v-icon name="draw" small /><span>Моя подпись</span>
            </button>
            <button v-if="actor?.is_admin" type="button" class="symbolika-mail-side-folder" @click="openSettingsDialog">
              <v-icon name="settings" small /><span>Настройки ящика</span>
            </button>
          </div>
        </nav>
      </template>
      <div class="symbolika-mail-page">
        <div class="symbolika-mail-shell">
          <header class="symbolika-mail-topbar">
            <div class="symbolika-mail-search-wrap">
              <v-icon name="search" small />
              <input v-model="search" class="symbolika-mail-search" type="search" placeholder="Поиск по теме, отправителю и тексту письма" />
            </div>
            <div class="symbolika-mail-top-actions">
              <span class="symbolika-mail-mode"><v-icon :name="mode === 'mock' ? 'science' : 'cloud_done'" small /> {{ mode === 'mock' ? 'Тестовая почта' : 'REG.RU' }}</span>
              <span class="symbolika-mail-sync-state"><strong>{{ syncing ? 'Обновляем…' : lastRefreshLabel }}</strong><span>Автообновление каждые 10 сек.</span></span>
              <button type="button" class="symbolika-mail-icon-button" :disabled="syncing" title="Получить новые письма" @click="syncMailbox(false)">
                <v-icon name="sync" small />
              </button>
              <button type="button" class="symbolika-mail-icon-button" title="Моя подпись" @click="openSignatureDialog"><v-icon name="draw" small /></button>
              <button v-if="actor?.is_admin" type="button" class="symbolika-mail-icon-button" title="Настройки почты" @click="openSettingsDialog">
                <v-icon name="settings" small />
              </button>
              <button type="button" class="symbolika-mail-button is-primary" title="Написать письмо" @click="openComposer()"><v-icon name="edit" small /><span class="symbolika-mail-button-label">Написать</span></button>
            </div>
          </header>

          <div v-if="loading" class="symbolika-mail-loading"><v-icon name="sync" /><span>Загружаем почту…</span></div>
          <div v-else class="symbolika-mail-content">
            <aside class="symbolika-mail-list">
              <div class="symbolika-mail-list-head">
                <div class="symbolika-mail-list-title">
                  <strong>{{ mailboxScope === 'starred' ? 'Избранное' : (selectedFolder?.name || 'Письма') }}</strong>
                  <span class="symbolika-mail-list-count">{{ visibleThreads.length }}</span>
                </div>
                <div class="symbolika-mail-scopes" aria-label="Фильтр писем">
                  <button type="button" class="symbolika-mail-scope" :class="{ 'is-active': threadScope === 'all' }" @click="threadScope = 'all'">Все <small>{{ threads.length }}</small></button>
                  <button type="button" class="symbolika-mail-scope" :class="{ 'is-active': threadScope === 'unread' }" @click="threadScope = 'unread'">Новые <small>{{ unreadThreadCount }}</small></button>
                  <button type="button" class="symbolika-mail-scope" :class="{ 'is-active': threadScope === 'starred' }" @click="threadScope = 'starred'">Важные <small>{{ starredThreadCount }}</small></button>
                </div>
              </div>
              <button
                v-for="thread in visibleThreads"
                :key="thread.id"
                type="button"
                class="symbolika-mail-thread"
                :class="{ 'is-active': selectedThread?.id === thread.id, 'is-unread': thread.is_unread }"
                @click="openThread(thread)"
              >
                <span class="symbolika-mail-avatar">{{ initials(displayParticipant(thread)) }}</span>
                <span class="symbolika-mail-thread-main">
                  <span class="symbolika-mail-thread-row">
                    <span class="symbolika-mail-thread-name">{{ displayParticipant(thread) }}</span>
                    <v-icon v-if="thread.is_starred" class="symbolika-mail-star" name="star" small />
                  </span>
                  <span class="symbolika-mail-thread-subject">{{ thread.subject }}</span>
                  <span class="symbolika-mail-thread-preview">{{ thread.preview || 'Нет текстового фрагмента' }}</span>
                </span>
                <time class="symbolika-mail-thread-time">{{ formatDate(thread.last_message_at) }}</time>
              </button>
              <div v-if="!visibleThreads.length" class="symbolika-mail-empty-list">Писем по выбранным условиям нет</div>
            </aside>

            <section class="symbolika-mail-reader">
              <div v-if="threadLoading" class="symbolika-mail-loading"><span>Открываем переписку…</span></div>
              <div v-else-if="!selectedThread" class="symbolika-mail-reader-empty">
                <div><span class="symbolika-mail-empty-illustration"><v-icon name="mark_email_unread" x-large /></span><strong>Выберите письмо</strong><span>Здесь откроется переписка, вложения и связанные рабочие объекты.</span></div>
              </div>
              <template v-else>
                <header class="symbolika-mail-reader-head">
                  <div class="symbolika-mail-reader-title-row">
                    <button type="button" class="symbolika-mail-icon-button symbolika-mail-back" title="Вернуться к списку" @click="closeThread"><v-icon name="arrow_back" small /></button>
                    <div class="symbolika-mail-reader-title">
                      <h2>{{ selectedThread.subject }}</h2>
                      <p>{{ displayParticipant(selectedThread) }} · {{ participantEmail(selectedThread) }}</p>
                    </div>
                    <div class="symbolika-mail-reader-actions">
                      <button type="button" class="symbolika-mail-icon-button" title="Связи, папка и теги" @click="openLinkDialog"><v-icon name="link" small /></button>
                      <button type="button" class="symbolika-mail-icon-button" title="Переслать" @click="openForwardComposer(selectedThread)"><v-icon name="forward" small /></button>
                      <button type="button" class="symbolika-mail-icon-button" :title="selectedThread.is_starred ? 'Убрать из избранного' : 'В избранное'" @click="patchThread(selectedThread, { is_starred: !selectedThread.is_starred })"><v-icon :name="selectedThread.is_starred ? 'star' : 'star_outline'" small /></button>
                      <button type="button" class="symbolika-mail-icon-button" title="Архивировать" @click="patchThread(selectedThread, { is_archived: true })"><v-icon name="archive" small /></button>
                      <button type="button" class="symbolika-mail-button is-primary" @click="openComposer(selectedThread)"><v-icon name="reply" small /><span class="symbolika-mail-button-label">Ответить</span></button>
                    </div>
                  </div>
                  <div class="symbolika-mail-links">
                    <span class="symbolika-mail-links-label">Работа с письмом</span>
                    <button v-if="selectedThread.order_id" type="button" class="symbolika-mail-link" @click="openEntity('order', selectedThread.order_id)"><v-icon name="receipt_long" small /> Заказ {{ selectedThread.order_number || selectedThread.order_id }}</button>
                    <button v-if="selectedThread.customer_id" type="button" class="symbolika-mail-link" @click="openEntity('customer', selectedThread.customer_id)"><v-icon name="person" small /> {{ selectedThread.customer_name || 'Клиент' }}</button>
                    <button v-if="selectedThread.company_id" type="button" class="symbolika-mail-link" @click="openEntity('company', selectedThread.company_id)"><v-icon name="business" small /> {{ selectedThread.company_name || 'Компания' }}</button>
                    <button v-if="selectedThread.task_id" type="button" class="symbolika-mail-link" @click="openEntity('task', selectedThread.task_id)"><v-icon name="task_alt" small /> {{ selectedThread.task_title || 'Задача' }}</button>
                    <span v-if="!selectedThread.order_id && !selectedThread.customer_id && !selectedThread.company_id && !selectedThread.task_id" class="symbolika-mail-mode">Связи не найдены</span>
                    <button type="button" class="symbolika-mail-link is-action" @click="openLinkDialog"><v-icon name="add_link" small /> Привязать</button>
                    <button type="button" class="symbolika-mail-link is-action" @click="openTaskDialog"><v-icon name="add_task" small /> Создать задачу</button>
                    <button type="button" class="symbolika-mail-link is-payment" @click="openPaymentDialog"><v-icon name="request_quote" small /> Счет на оплату</button>
                    <span v-for="tag in selectedThread.tags || []" :key="tag" class="symbolika-mail-tag"><v-icon name="label" small />{{ tag }}</span>
                  </div>
                </header>

                <div class="symbolika-mail-messages">
                  <article v-for="message in messages" :key="message.id" class="symbolika-mail-message" :class="{ 'is-outbound': message.direction === 'outbound' }">
                    <header class="symbolika-mail-message-head">
                      <span class="symbolika-mail-avatar">{{ initials(message.from_name || message.from_email) }}</span>
                      <div class="symbolika-mail-message-from">
                        <strong>{{ message.from_name || message.from_email }}</strong>
                        <small>{{ message.from_email }} → {{ (message.to_emails || []).join(', ') }}</small>
                      </div>
                      <time>{{ formatDate(message.sent_at, true) }}</time>
                    </header>
                    <div class="symbolika-mail-message-body">
                      <iframe class="symbolika-mail-message-body-frame" :srcdoc="mailBodyDocument(message)" sandbox="allow-same-origin allow-popups allow-popups-to-escape-sandbox" title="Содержимое письма" @load="resizeMailBody"></iframe>
                    </div>
                    <div v-if="message.attachments?.length" class="symbolika-mail-attachments">
                      <div v-for="(file, index) in message.attachments" :key="index" class="symbolika-mail-attachment">
                        <v-icon name="attach_file" small />
                        <span><strong>{{ file.name }}</strong><small>{{ formatBytes(file.size) }} · {{ file.type || 'файл' }}</small></span>
                        <span class="symbolika-mail-attachment-actions">
                          <a class="symbolika-mail-attachment-action" :href="'/symbolika-mail/messages/' + message.id + '/attachments/' + index" target="_blank" rel="noopener" title="Открыть"><v-icon name="open_in_new" small /></a>
                          <a class="symbolika-mail-attachment-action" :href="'/symbolika-mail/messages/' + message.id + '/attachments/' + index + '?download=1'" title="Скачать"><v-icon name="download" small /></a>
                        </span>
                      </div>
                    </div>
                  </article>
                </div>
                <div class="symbolika-mail-reply-bar"><button type="button" class="symbolika-mail-button is-primary" @click="openComposer(selectedThread)"><v-icon name="reply" small /> Ответить</button></div>
              </template>
            </section>
          </div>
        </div>

        <div v-if="notice" class="symbolika-mail-alert" @click="notice = ''">{{ notice }}</div>
        <div v-if="error" class="symbolika-mail-alert is-error" role="alert" aria-live="assertive">
          <v-icon name="error" />
          <span class="symbolika-mail-alert-error-copy"><strong>Не удалось выполнить действие</strong><span>{{ error }}</span></span>
          <button type="button" class="symbolika-mail-alert-close" title="Закрыть" aria-label="Закрыть уведомление" @click="error = ''"><v-icon name="close" small /></button>
        </div>

        <div v-if="showComposer" class="symbolika-mail-overlay" @click.self="showComposer = false">
          <form class="symbolika-mail-dialog is-compose" @submit.prevent="sendMessage">
            <header class="symbolika-mail-dialog-head"><h2>{{ composer.thread_id ? 'Ответить' : 'Новое письмо' }}</h2><button type="button" class="symbolika-mail-icon-button" @click="showComposer = false"><v-icon name="close" small /></button></header>
            <div class="symbolika-mail-dialog-body">
              <div class="symbolika-mail-address-grid">
                <label class="symbolika-mail-field">От кого<input v-model.trim="composer.from_alias" class="symbolika-mail-input" type="email" required /></label>
                <label class="symbolika-mail-field">Кому<input v-model.trim="composer.to" class="symbolika-mail-input" type="text" placeholder="client@example.ru" required /></label>
              </div>
              <label class="symbolika-mail-field">Тема<input v-model.trim="composer.subject" class="symbolika-mail-input" type="text" required /></label>
              <label class="symbolika-mail-field">Сообщение<textarea v-model="composer.body" class="symbolika-mail-textarea" placeholder="Введите текст письма…" spellcheck="true" required @keydown.ctrl.enter.prevent="sendMessage"></textarea></label>
              <div class="symbolika-mail-compose-hint"><span>Ctrl + Enter — отправить</span><span>{{ composer.body.length }} символов</span></div>
              <label class="symbolika-mail-checkbox"><input v-model="composer.include_signature" type="checkbox" /> Добавить мою подпись</label>
              <div v-if="composer.include_signature && actor?.signature" class="symbolika-mail-signature-preview"><small>Подпись</small><div v-html="actor.signature"></div></div>
              <span v-if="mode === 'mock'" class="symbolika-mail-mode"><v-icon name="science" small /> Письмо сохранится только в тестовой почте</span>
            </div>
            <footer class="symbolika-mail-dialog-actions"><button type="button" class="symbolika-mail-button" @click="showComposer = false">Отмена</button><button type="submit" class="symbolika-mail-button is-primary" :disabled="sending"><v-icon name="send" small /> {{ sending ? 'Отправляем…' : 'Отправить' }}</button></footer>
          </form>
        </div>

        <div v-if="showLinkDialog" class="symbolika-mail-overlay" @click.self="showLinkDialog = false">
          <form class="symbolika-mail-dialog" @submit.prevent="saveThreadLinks">
            <header class="symbolika-mail-dialog-head"><h2>Связи, папка и теги</h2><button type="button" class="symbolika-mail-icon-button" @click="showLinkDialog = false"><v-icon name="close" small /></button></header>
            <div class="symbolika-mail-dialog-body">
              <p class="symbolika-mail-help">Клиент и компания подставляются автоматически по email отправителя. Заказ также определяется по номеру вида SO-00012 в теме. Здесь связи можно исправить вручную.</p>
              <label class="symbolika-mail-field">Заказ<select v-model="linkForm.order_id" class="symbolika-mail-select" @change="applyLinkOrder"><option :value="null">Не привязан</option><option v-for="row in options.orders" :key="row.id" :value="row.id">{{ row.order_number }} · {{ row.customer_name || row.company_name || 'без заказчика' }}</option></select></label>
              <label class="symbolika-mail-field">Клиент<select v-model="linkForm.customer_id" class="symbolika-mail-select" @change="applyLinkCustomer"><option :value="null">Не привязан</option><option v-for="row in options.customers" :key="row.id" :value="row.id">{{ row.name }}{{ row.email ? ' · ' + row.email : '' }}</option></select></label>
              <label class="symbolika-mail-field">Компания<select v-model="linkForm.company_id" class="symbolika-mail-select"><option :value="null">Не привязана</option><option v-for="row in options.companies" :key="row.id" :value="row.id">{{ row.name }}{{ row.email ? ' · ' + row.email : '' }}</option></select></label>
              <label class="symbolika-mail-field">Рабочая папка<select v-model="linkForm.folder_id" class="symbolika-mail-select"><option v-for="row in options.folders" :key="row.id" :value="row.id">{{ row.name }}</option></select></label>
              <label class="symbolika-mail-field">Теги<input v-model="linkForm.tags_text" class="symbolika-mail-input" placeholder="счет, поставщик, срочно" /><small>Несколько тегов разделяйте запятыми.</small></label>
            </div>
            <footer class="symbolika-mail-dialog-actions"><button type="button" class="symbolika-mail-button" @click="showLinkDialog = false">Отмена</button><button type="submit" class="symbolika-mail-button is-primary" :disabled="actionSaving">Сохранить</button></footer>
          </form>
        </div>

        <div v-if="showTaskDialog" class="symbolika-mail-overlay" @click.self="showTaskDialog = false">
          <form class="symbolika-mail-dialog" @submit.prevent="createTaskFromMail">
            <header class="symbolika-mail-dialog-head"><h2>Создать задачу из письма</h2><button type="button" class="symbolika-mail-icon-button" @click="showTaskDialog = false"><v-icon name="close" small /></button></header>
            <div class="symbolika-mail-dialog-body">
              <label class="symbolika-mail-field">Название<input v-model.trim="taskForm.title" class="symbolika-mail-input" required /></label>
              <label class="symbolika-mail-field">Исполнитель<select v-model="taskForm.assigned_to" class="symbolika-mail-select"><option :value="null">Не назначен</option><option v-for="row in options.employees" :key="row.id" :value="row.id">{{ row.full_name }}</option></select></label>
              <div class="symbolika-mail-field-grid"><label class="symbolika-mail-field">Срок<input v-model="taskForm.due_date" class="symbolika-mail-input" type="date" /></label><label class="symbolika-mail-field">Приоритет<select v-model="taskForm.priority" class="symbolika-mail-select"><option value="normal">Обычный</option><option value="important">Важный</option><option value="urgent">Срочный</option></select></label></div>
              <label class="symbolika-mail-field">Комментарий<textarea v-model="taskForm.description" class="symbolika-mail-textarea is-compact" placeholder="Что нужно сделать по письму"></textarea></label>
            </div>
            <footer class="symbolika-mail-dialog-actions"><button type="button" class="symbolika-mail-button" @click="showTaskDialog = false">Отмена</button><button type="submit" class="symbolika-mail-button is-primary" :disabled="actionSaving">Создать задачу</button></footer>
          </form>
        </div>

        <div v-if="showPaymentDialog" class="symbolika-mail-overlay" @click.self="showPaymentDialog = false">
          <form class="symbolika-mail-dialog" @submit.prevent="createPaymentTasks">
            <header class="symbolika-mail-dialog-head"><h2>Передать счет на оплату</h2><button type="button" class="symbolika-mail-icon-button" @click="showPaymentDialog = false"><v-icon name="close" small /></button></header>
            <div class="symbolika-mail-dialog-body">
              <p class="symbolika-mail-help">Система создаст важные задачи всем активным администраторам и управляющим. В задачу попадут тема письма, список вложений и уже установленные связи с заказом или заказчиком.</p>
              <label class="symbolika-mail-field">Оплатить до<input v-model="paymentForm.due_date" class="symbolika-mail-input" type="date" /></label>
              <label class="symbolika-mail-field">Комментарий<textarea v-model="paymentForm.comment" class="symbolika-mail-textarea is-compact" placeholder="Сумма, назначение платежа, особые условия"></textarea></label>
            </div>
            <footer class="symbolika-mail-dialog-actions"><button type="button" class="symbolika-mail-button" @click="showPaymentDialog = false">Отмена</button><button type="submit" class="symbolika-mail-button is-primary" :disabled="actionSaving">Отправить в задачи</button></footer>
          </form>
        </div>

        <div v-if="showSignatureDialog" class="symbolika-mail-overlay is-signature" @click.self="showSignatureDialog = false">
          <form class="symbolika-mail-dialog is-signature-editor" @submit.prevent="saveSignature">
            <header class="symbolika-mail-dialog-head"><h2>{{ signatureTargetEmployee ? 'Подпись · ' + signatureTargetEmployee.full_name : 'Моя подпись' }}</h2><button type="button" class="symbolika-mail-icon-button" @click="showSignatureDialog = false"><v-icon name="close" small /></button></header>
            <div class="symbolika-mail-dialog-body">
              <div class="symbolika-mail-signature-designer">
                <section class="symbolika-mail-signature-fields">
                  <div class="symbolika-mail-signature-section-head">
                    <div><strong>Данные подписи</strong><span>Изменения здесь не меняют карточку сотрудника.</span></div>
                    <button type="button" class="symbolika-mail-button is-compact" @click="resetSignatureSettings">Вернуть из карточки</button>
                  </div>
                  <div class="symbolika-mail-signature-grid">
                    <label class="symbolika-mail-field">Имя и фамилия<input v-model="signatureSettings.full_name" class="symbolika-mail-input" /></label>
                    <label class="symbolika-mail-field">Публичная должность<input v-model="signatureSettings.position" class="symbolika-mail-input" /></label>
                    <label class="symbolika-mail-field">Телефон<input v-model="signatureSettings.phone" class="symbolika-mail-input" placeholder="+7 (___) ___-__-__" /></label>
                    <label class="symbolika-mail-field">Email<input v-model="signatureSettings.email" class="symbolika-mail-input" type="email" /></label>
                    <label class="symbolika-mail-field">Сайт — текст<input v-model="signatureSettings.website_label" class="symbolika-mail-input" /></label>
                    <label class="symbolika-mail-field">Сайт — ссылка<input v-model="signatureSettings.website_url" class="symbolika-mail-input" /></label>
                    <label class="symbolika-mail-field is-wide">Адрес офиса<input v-model="signatureSettings.address" class="symbolika-mail-input" /></label>
                    <label class="symbolika-mail-field is-wide">Ссылка на Яндекс Карты<input v-model="signatureSettings.map_url" class="symbolika-mail-input" /></label>
                    <label class="symbolika-mail-field">VK — текст<input v-model="signatureSettings.vk_label" class="symbolika-mail-input" /></label>
                    <label class="symbolika-mail-field">VK — ссылка<input v-model="signatureSettings.vk_url" class="symbolika-mail-input" /></label>
                    <label class="symbolika-mail-field is-wide">Слоган, строка 1<input v-model="signatureSettings.slogan_line_1" class="symbolika-mail-input" /></label>
                    <label class="symbolika-mail-field is-wide">Слоган, строка 2<input v-model="signatureSettings.slogan_line_2" class="symbolika-mail-input" /></label>
                    <label class="symbolika-mail-field is-wide">Логотип — URL изображения<input v-model="signatureSettings.logo_url" class="symbolika-mail-input" /></label>
                  </div>
                </section>
                <section class="symbolika-mail-signature-live">
                  <strong>Живое превью</strong>
                  <div class="symbolika-mail-signature-card">
                    <div class="symbolika-mail-signature-brand"><img v-if="signatureSettings.logo_url" :src="signatureSettings.logo_url" alt="Символика" /><b v-else>Символика</b></div>
                    <div class="symbolika-mail-signature-person"><h3>{{ signatureSettings.full_name || 'Имя Фамилия' }}</h3><b>{{ signatureSettings.position || 'Должность' }}</b><i></i><p>{{ signatureSettings.slogan_line_1 }}<br v-if="signatureSettings.slogan_line_2" />{{ signatureSettings.slogan_line_2 }}</p></div>
                    <div class="symbolika-mail-signature-contacts">
                      <a v-if="signatureSettings.phone" :href="'tel:' + signatureSettings.phone">☎ <span>{{ signatureSettings.phone }}</span></a>
                      <a v-if="signatureSettings.email" :href="'mailto:' + signatureSettings.email">✉ <span>{{ signatureSettings.email }}</span></a>
                      <a v-if="signatureSettings.website_label" :href="signatureSettings.website_url" target="_blank">◎ <span>{{ signatureSettings.website_label }}</span></a>
                      <a v-if="signatureSettings.address" :href="signatureSettings.map_url" target="_blank">◉ <span>{{ signatureSettings.address }}</span></a>
                      <a v-if="signatureSettings.vk_label" :href="signatureSettings.vk_url" target="_blank"><b>VK</b> <span>{{ signatureSettings.vk_label }}</span></a>
                    </div>
                  </div>
                </section>
              </div>
              <p class="symbolika-mail-help">Дополнительный блок после фирменной подписи — можно оставить пустым.</p>
              <div class="symbolika-mail-editor-shell">
                <div class="symbolika-mail-editor-toolbar" aria-label="Форматирование подписи">
                  <button type="button" class="symbolika-mail-editor-tool" title="Жирный" @click="formatSignature('bold')"><strong>Ж</strong></button>
                  <button type="button" class="symbolika-mail-editor-tool" title="Курсив" @click="formatSignature('italic')"><em>К</em></button>
                  <button type="button" class="symbolika-mail-editor-tool" title="Подчеркнутый" @click="formatSignature('underline')"><u>Ч</u></button>
                  <span class="symbolika-mail-editor-separator"></span>
                  <button type="button" class="symbolika-mail-editor-tool" title="По левому краю" @click="formatSignature('justifyLeft')"><v-icon name="format_align_left" small /></button>
                  <button type="button" class="symbolika-mail-editor-tool" title="По центру" @click="formatSignature('justifyCenter')"><v-icon name="format_align_center" small /></button>
                  <button type="button" class="symbolika-mail-editor-tool" title="По правому краю" @click="formatSignature('justifyRight')"><v-icon name="format_align_right" small /></button>
                  <span class="symbolika-mail-editor-separator"></span>
                  <button type="button" class="symbolika-mail-editor-tool" title="Маркированный список" @click="formatSignature('insertUnorderedList')"><v-icon name="format_list_bulleted" small /></button>
                  <button type="button" class="symbolika-mail-editor-tool" title="Нумерованный список" @click="formatSignature('insertOrderedList')"><v-icon name="format_list_numbered" small /></button>
                  <button type="button" class="symbolika-mail-editor-tool" title="Добавить ссылку" @click="openSignatureLink"><v-icon name="link" small /></button>
                  <button type="button" class="symbolika-mail-editor-tool" title="Убрать форматирование" @click="formatSignature('removeFormat')"><v-icon name="format_clear" small /></button>
                </div>
                <div ref="signatureEditor" class="symbolika-mail-signature-editor" contenteditable="true" data-placeholder="Имя, должность, телефон, сайт" spellcheck="true" @input="syncSignatureEditor" @blur="syncSignatureEditor"></div>
              </div>
              <div v-if="signatureLinkVisible" class="symbolika-mail-link-editor">
                <input v-model="signatureLinkForm.text" class="symbolika-mail-input" placeholder="Текст ссылки" />
                <input v-model="signatureLinkForm.url" class="symbolika-mail-input" placeholder="https://example.ru" @keydown.enter.prevent="insertSignatureLink" />
                <button type="button" class="symbolika-mail-button is-primary" @click="insertSignatureLink">Вставить</button>
                <button type="button" class="symbolika-mail-button" @click="signatureLinkVisible = false">Отмена</button>
              </div>
            </div>
            <footer class="symbolika-mail-dialog-actions"><button type="button" class="symbolika-mail-button" @click="showSignatureDialog = false">Отмена</button><button type="submit" class="symbolika-mail-button is-primary" :disabled="signatureSaving">Сохранить</button></footer>
          </form>
        </div>

        <div v-if="showSettings" class="symbolika-mail-overlay" @click.self="showSettings = false">
          <section class="symbolika-mail-dialog is-settings">
            <header class="symbolika-mail-dialog-head"><h2>Настройки почты</h2><button type="button" class="symbolika-mail-icon-button" @click="showSettings = false"><v-icon name="close" small /></button></header>
            <div v-if="settingsLoading" class="symbolika-mail-loading">Загружаем настройки…</div>
            <div v-else-if="settings" class="symbolika-mail-dialog-body">
              <div class="symbolika-mail-settings-summary">
                <div class="symbolika-mail-settings-card"><small>Режим</small><strong>{{ settings.connection.mode === 'mock' ? 'Тестовый' : 'IMAP / SMTP' }}</strong></div>
                <div class="symbolika-mail-settings-card"><small>IMAP</small><strong>{{ settings.connection.imap_host || 'Не настроен' }}:{{ settings.connection.imap_port }}</strong></div>
                <div class="symbolika-mail-settings-card"><small>SMTP</small><strong>{{ settings.connection.smtp_host || 'Не настроен' }}:{{ settings.connection.smtp_port }}</strong></div>
                <div class="symbolika-mail-settings-card"><small>Общий ящик</small><strong>{{ settings.connection.user || 'Не настроен' }}</strong></div>
              </div>
              <section class="symbolika-mail-settings-section">
                <h3>Подписи сотрудников</h3>
                <p>Подпись автоматически добавляется к исходящим письмам конкретного сотрудника.</p>
                <div v-for="employee in settings.employees" :key="'signature-' + employee.id" class="symbolika-mail-signature-row">
                  <div><strong>{{ employee.full_name }}</strong><small>{{ employee.email || 'Нет учетной почты' }}</small></div>
                  <div class="symbolika-mail-signature-summary" v-html="employee.signature_preview || 'Подпись не настроена'"></div>
                  <button type="button" class="symbolika-mail-button" @click="openSignatureDialog(employee)"><v-icon name="edit" small /> Настроить</button>
                </div>
              </section>
              <section class="symbolika-mail-settings-section"><h3>Папки и псевдонимы</h3><p>Сопоставление папок REG.RU с сотрудниками и адресами отправителя.</p></section>
              <div class="symbolika-mail-settings-folder is-new">
                <label class="symbolika-mail-field">Название<input v-model.trim="newFolder.name" class="symbolika-mail-input" placeholder="Новая папка" /></label>
                <label class="symbolika-mail-field">Папка IMAP<input v-model.trim="newFolder.imap_name" class="symbolika-mail-input" placeholder="INBOX.Новая папка" /></label>
                <label class="symbolika-mail-field">Псевдоним<input v-model.trim="newFolder.alias_email" class="symbolika-mail-input" type="email" placeholder="manager@symb62.ru" /></label>
                <label class="symbolika-mail-field">Сотрудник<select v-model="newFolder.employee" class="symbolika-mail-select"><option :value="null">Не назначен</option><option v-for="employee in settings.employees" :key="'new-' + employee.id" :value="employee.id">{{ employee.full_name }}</option></select></label>
                <label class="symbolika-mail-checkbox"><input v-model="newFolder.is_shared" type="checkbox" /> Общая</label>
                <button type="button" class="symbolika-mail-button" :disabled="creatingFolder" @click="createFolder">{{ creatingFolder ? 'Создаём…' : 'Добавить' }}</button>
              </div>
              <div v-for="folder in settings.folders" :key="folder.id" class="symbolika-mail-settings-folder">
                <label class="symbolika-mail-field">Название<input v-model.trim="folder.name" class="symbolika-mail-input" /></label>
                <label class="symbolika-mail-field">Папка IMAP<input v-model.trim="folder.imap_name" class="symbolika-mail-input" placeholder="INBOX/Менеджер" /></label>
                <label class="symbolika-mail-field">Псевдоним<input v-model.trim="folder.alias_email" class="symbolika-mail-input" type="email" placeholder="manager@symb62.ru" /></label>
                <label class="symbolika-mail-field">Сотрудник<select v-model="folder.employee" class="symbolika-mail-select"><option :value="null">Не назначен</option><option v-for="employee in settings.employees" :key="employee.id" :value="employee.id">{{ employee.full_name }}</option></select></label>
                <label class="symbolika-mail-checkbox"><input v-model="folder.is_shared" type="checkbox" /> Общая</label>
                <button type="button" class="symbolika-mail-button" :disabled="savingFolderId === folder.id" @click="saveFolder(folder)">{{ savingFolderId === folder.id ? 'Сохраняем…' : 'Сохранить' }}</button>
              </div>
            </div>
            <footer class="symbolika-mail-dialog-actions"><button type="button" class="symbolika-mail-button" @click="showSettings = false">Закрыть</button></footer>
          </section>
        </div>
      </div>
    </private-view>
  `,
};

export default {
  id: 'symbolika-mail-module',
  name: 'Почта',
  icon: 'mail',
  color: '#F97316',
  routes: [{ path: '', component: MailWorkspace }],
};
