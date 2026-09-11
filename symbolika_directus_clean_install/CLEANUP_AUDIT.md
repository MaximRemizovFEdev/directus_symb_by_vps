# Аудит и план чистки проекта

Дата первичного аудита: 2026-08-01.

## Что уже сделано безопасно

- Добавлены правила LF для основных типов файлов в `.gitattributes`: `sh`, `js`, `mjs`, `css`, `sql`, `md`, `json`, `yml`, `yaml`.
- В `.gitignore` добавлены временные файлы `tmp-*` и `*.tmp`.
- Из `.gitignore` убрано исключение для `full_directus_backup.sql`, чтобы новые SQL-дампы не попадали в репозиторий.
- Удален временный Playwright-скрипт `tmp-symbolika-collapse.js`.
- В SQL-настройках витрин убрана ссылка на старый интерфейс `symbolika-autosave-select`; для офисных статусов используется стандартный `select-dropdown`.
- Из `setup/symbolika-admin-ui.js` и `setup/symbolika-admin-ui.css` удален отключенный автосейв стандартных карточек Directus и его всплывающий индикатор. Это снижает риск фантомных сообщений `Ошибка сохранения` / `Сохранено`.
- Корневой `README.md` переписан в нормальной UTF-8 кодировке и приведен к актуальной схеме восстановления через `pg_restore` из custom dump.
- `symbolika_directus_clean_install/README.md` переписан в нормальной UTF-8 кодировке и приведен к текущему устройству системы.
- В новом модуле кабинета контрагента исправлено отображаемое имя модуля на `Кабинет`.
- `AGENTS.md` переписан в нормальной UTF-8 кодировке.
- В `setup/create-work-views.sql` добавлен защитный блок нормализации русских подписей для офисных и производственных витрин. Внутри `U&'...'` исправлены неверные `\uXXXX` escape-последовательности на PostgreSQL-совместимый формат.
- В `setup/create-work-views.sql` добавлена регистрация недостающих `directus_fields` для `production_work` и `screen_printing_work`: `price_per_unit`, `order_sum`, `blank_source`, `blank_ordered`, `product_category`, `product_subcategory`, `application_method`, `contractor_1`, `contractor_1_cost`. Это чинит ошибки вида `You don't have permission to access fields ... or they do not exist` после добавления логики заготовок.
- Этот блок применен к локальной базе: в Directus-метаданных появились 18 недостающих полей для производственных таблиц, после чего контейнер Directus был перезапущен.

## Проверки

- `git diff --check` проходит без ошибок. Git предупреждает только о будущей нормализации CRLF в больших файлах.
- `node --check` ранее проходил для:
  - `setup/symbolika-admin-ui.js`;
  - `extensions/symbolika-costing-module/index.js`;
  - `extensions/symbolika-calculations/index.js`;
  - `extensions/symbolika-contractor-module/index.js`.
- Для touched-файлов проверены окончания строк: `.gitattributes`, `.gitignore`, корневой `README.md`, `AGENTS.md`, `CLEANUP_AUDIT.md`, `symbolika-admin-ui.js`, `symbolika-admin-ui.css` сохранены без CRLF.
- Проверено, что в `U&'...'` строках `setup/create-work-views.sql` не осталось неверных `\uXXXX` escape-последовательностей. JSON-переводы с `\uXXXX` не трогались.
- Проверено, что в БД у `production_work` и `screen_printing_work` зарегистрированы поля, которые запрашивает рабочий центр после добавления заготовок и себестоимостей.

## Найденные проблемные зоны

- `extensions/symbolika-costing-module/index.js` остается большим монолитом. В нем смешаны:
  - API-клиент;
  - справочники статусов и цветов;
  - расчеты;
  - экспорт;
  - модальные карточки;
  - таблицы заказов, финансов, производства, админки;
  - большой CSS и шаблоны.
- В CSS-блоке `symbolika-costing-module/index.js` есть явные наслоения правил. По состоянию на аудит часто переопределяются:
  - `.symbolika-costing-page` — 11 раз;
  - `.symbolika-costing-table-select` и `.symbolika-costing-table-date` — по 10 раз;
  - `.symbolika-costing-table`, `.symbolika-costing-actions`, `.symbolika-costing-table th` — по 9 раз;
  - `.symbolika-costing-detail`, `.symbolika-costing-toolbar`, `.symbolika-costing-table td` — по 8 раз.
  Это объясняет, почему правки меню, таблиц и карточек иногда конфликтуют между собой.
- `setup/create-work-views.sql` содержит исторический блок с битой кириллицей примерно в районе строк 2472-2707 и 2795. Новый функционал ниже в файле частично написан корректнее, поэтому старый блок нельзя чинить слепой заменой.
- В репозитории лежат экспериментальные расширения:
  - `extensions/symbolika-autosave-select/`;
  - `extensions/symbolika-live-calc-interface/`.
  Их не стоит включать обратно без отдельной проверки.
- В git отслеживается `full_directus_backup.sql`, хотя для деплоя нужен только PostgreSQL custom dump `pg_dump -Fc`.
- В git отслеживается временный скриншот `tmp-office-order-link-bottom-right.png`.
- `symbolika_directus_clean_install/README.md` уже очищен, но при дальнейших изменениях важно сохранять его в UTF-8.
- В логах Directus остаются предупреждения о backup-таблицах без первичного ключа: `directus_fields_backup_before_*` и `directus_permissions_backup_before_*`. Это не критическая ошибка запуска, но кандидат на отдельную ручную чистку после подтверждения.
- В логах Directus есть предупреждение, что `PUBLIC_URL` задан не полным URL. Перед VPS-деплоем лучше указать полный внешний адрес системы.

## Рекомендуемый порядок дальнейшей чистки

1. Отдельно согласовать удаление из git:
   - `full_directus_backup.sql`;
   - `tmp-office-order-link-bottom-right.png`;
   - экспериментальных расширений `symbolika-autosave-select` и `symbolika-live-calc-interface`, если они больше не нужны.
2. Нормализовать оставшуюся битую кириллицу в исторических блоках `create-work-views.sql` или удалить устаревшие Directus-витрины, если основной интерфейс окончательно переехал в рабочие модули.
3. Начать дробить `symbolika-costing-module/index.js` на небольшие файлы:
   - `api.js`;
   - `formatters.js`;
   - `domain/statuses.js`;
   - `domain/finance.js`;
   - `views/orders.js`;
   - `views/production.js`;
   - `views/finance.js`;
   - `views/admin.js`;
   - `components/sidebar.js`;
   - `components/modals.js`;
   - `styles.css`.
4. Перед визуальными доработками вынести CSS из injected-string в отдельный файл или хотя бы пересобрать его в один упорядоченный блок: базовые переменные, layout, sidebar, формы, таблицы, карточки, модалки, адаптив.
5. После каждого шага проверять:
   - `node --check`;
   - запуск Directus;
   - Playwright-проверку под ролями админ, управляющий, менеджер, офис, производство, шелкография.

## Принцип

Большие чистки не смешивать с новой бизнес-логикой. Сначала стабилизировать структуру, потом развивать функции.
