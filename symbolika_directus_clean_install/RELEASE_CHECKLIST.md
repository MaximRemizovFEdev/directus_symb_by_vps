# Чек-лист релиза

## До отправки

- [ ] Все секреты вынесены в `.env`.
- [ ] В Git нет `.env`, базы, dumps, uploads, node_modules и временных скриншотов.
- [ ] Git remote не содержит токенов.
- [ ] GitHub PAT и опубликованные provider tokens отозваны.
- [ ] JS проходит `node --check`.
- [ ] SQL применяется с `ON_ERROR_STOP=1`.
- [ ] Directus стартует без ошибок extensions.
- [ ] Выполнен Playwright smoke/regression по ролям.
- [ ] Создан `pg_dump -Fc` и проверен через `pg_restore --list`.
- [ ] Подготовлен архив uploads, если локальные файлы нужны на сервере.
- [ ] Shell-скрипты имеют LF.

## На сервере

- [ ] `.env` имеет права 600.
- [ ] PostgreSQL не опубликован наружу.
- [ ] Directus доступен через HTTPS.
- [ ] WebSocket работает через reverse proxy.
- [ ] Выполнен restore release dump.
- [ ] Применен `setup/create-work-views.sql`.
- [ ] Установлены npm-зависимости calculations и mail.
- [ ] Проверены все роли и связи пользователей с сотрудниками.
- [ ] Подключены и отдельно протестированы Яндекс Диск, SMTP/IMAP, Push, Telegram и VK.
- [ ] Настроен ежедневный off-server backup.
- [ ] Выполнена приемочная бизнес-цепочка от заказа до выдачи.

