# AGENTS.md

## Быстрый старт

Перед новой задачей сначала читать:

```text
symbolika_directus_clean_install/CODEX_WORKFLOW.md
```

Если нужен более широкий контекст по бизнес-логике, дополнительно читать:

```text
symbolika_directus_clean_install/PROJECT_CONTEXT.md
```

`symbolika_directus_clean_install/TZ_CONSTRUCTOR_SPEC.md` не читать и не держать в контексте, если задача явно не про конструктор ТЗ или будущие калькуляторы. Конструктор ТЗ уже собран, к нему вернемся позже.

Карта проекта для Codex и будущих агентов. Обновляй этот файл, когда меняется архитектура, важные команды, правила деплоя или подход к данным.

## Проект

Это учетная система «Символика» на Directus 11 + PostgreSQL/PostGIS.

Основная рабочая папка:

```text
symbolika_directus_clean_install/
```

Локальный адрес:

```text
http://localhost:8057/admin/
```

Основные контейнеры:

```text
symbolika-directus
symbolika-db
```

## Главные файлы

- `symbolika_directus_clean_install/docker-compose.yml` — запуск Directus и PostgreSQL. В файле могут быть живые токены и ключи, не цитировать их в ответах.
- `symbolika_directus_clean_install/setup/create-work-views.sql` — основной SQL-слой: таблицы, представления, триггеры, права, роли, статусы, маршрутизация и metadata Directus.
- `symbolika_directus_clean_install/setup/symbolika-admin-ui.js` — клиентские правки стандартной админки Directus.
- `symbolika_directus_clean_install/setup/symbolika-admin-ui.css` — визуальные правки стандартной админки Directus.
- `symbolika_directus_clean_install/extensions/symbolika-costing-module/` — основной рабочий интерфейс системы.
- `symbolika_directus_clean_install/extensions/symbolika-calculations/` — серверная бизнес-логика: суммы, оплаты, статусы, офис, производство.
- `symbolika_directus_clean_install/extensions/symbolika-event-rollback/` — endpoint точечного и последовательного отката событий с проверкой прав Directus.
- `symbolika_directus_clean_install/extensions/symbolika-contact-duplicates/` — админский endpoint поиска и транзакционного объединения дублей клиентов и компаний с переносом связанных данных.
- `symbolika_directus_clean_install/extensions/symbolika-push/` — push и внешние уведомления, включая VK.

## Рабочие модули

Основной интерфейс постепенно переносится из стандартных коллекций Directus в собственные модули.

Тонкие модули-обертки над `symbolika-costing-module`:

- `symbolika-admin-module` — админка, справочники, расходы, зарплаты, финрезультат.
- `symbolika-clients-module` — legacy-обертка для совместимости ссылок; клиенты и компании выведены в `Заказы`.
- `symbolika-finance-module` — legacy-обертка для совместимости ссылок; сверки и клиентские операции выведены в `Заказы`.
- `symbolika-management-module` — себестоимость и управление заказами.
- `symbolika-production-module` — производство, шелкография, этикетки.
- `symbolika-contractor-module` — будущий кабинет контрагента.
- `symbolika-profile-module` — личный кабинет пользователя: аватар, контакты и собственная зарплата.
- `symbolika-news-module` — внутренняя лента новостей компании с черновиками, визуальным редактором и отметками прочтения.

Защищённый endpoint `symbolika-news` обслуживает публикации и создаёт системные уведомления активным сотрудникам при первой публикации новости. Создавать и редактировать новости могут админ и управляющий, читать — все сотрудники.

Защищённый endpoint `symbolika-profile` возвращает и изменяет только профиль текущего пользователя и его собственные зарплатные данные.

Экспериментальные/исторические расширения:

- `symbolika-autosave-select`
- `symbolika-live-calc-interface`

Их не включать обратно без отдельного тестирования. Автосохранение в таблицах уже пробовали: значения отскакивали назад, Directus путал dirty-состояние формы.

## Бизнес-правила

- Менеджер видит свои заказы, своих клиентов и свои рабочие показатели.
- Админ и управляющий видят общую картину.
- Офис работает с заказами на выдачу, заказами в офисе и архивом выданных.
- Производство и шелкография видят только свои позиции.
- Если производство ставит «Доработка макета», статус позиции тоже должен стать «Доработка макета».
- Если все позиции готовы, заказ готов. Если заказ готов, все позиции готовы.
- Если все позиции доставлены/выданы, заказ доставлен/выдан. Аналогично для отмены.
- Если клиент заказывает от компании, плательщиком для сверки считается компания.
- Частичная оплата распределяется по позициям сверху вниз.
- Оплаты контрагентам не считаются операционным расходом в финрезультате, потому что себестоимость уже вычтена из прибыли заказа.

## Справочники и маршрутизация

Основные справочники:

- `employees`
- `employee_positions`
- `contractors`
- `product_categories`
- `product_subcategories`
- `product_application_methods`
- `product_routing_rules`
- `order_statuses`
- `production_statuses`

Маршрутизация подрядчиков должна идти через `product_routing_rules`:

```text
категория / подкатегория / вид нанесения -> подрядчик 1 / подрядчик 2
```

Исторические поля `default_product_category` и `default_product_subcategory` у контрагентов могут существовать, но основной источник истины — правила маршрутизации.

## База и бэкапы

Живая база:

```text
symbolika_directus_clean_install/database/
```

Не коммитить.

Для переноса базы использовать только PostgreSQL custom dump:

```bash
docker exec symbolika-db pg_dump -U directus -d directus -Fc -f /tmp/directus.dump
docker cp symbolika-db:/tmp/directus.dump backups/directus.dump
```

Проверка дампа:

```bash
pg_restore --list backups/directus.dump
```

Обычный SQL dump не использовать для деплоя на VPS.

## Частые команды

Применить SQL-настройки:

```powershell
cmd /c "docker exec -i symbolika-db psql -v ON_ERROR_STOP=1 -U directus -d directus < symbolika_directus_clean_install\setup\create-work-views.sql"
```

Проверить JS:

```powershell
node --check symbolika_directus_clean_install\extensions\symbolika-costing-module\index.js
node --check symbolika_directus_clean_install\extensions\symbolika-calculations\index.js
node --check symbolika_directus_clean_install\setup\symbolika-admin-ui.js
```

Перезапустить Directus:

```powershell
docker restart symbolika-directus
```

Логи:

```powershell
docker logs --tail 80 symbolika-directus
```

## Git и перенос на Linux

Правила git смотри также в `INFO.md`.

Важно:

- shell-скрипты `*.sh` должны храниться в LF;
- не коммитить `database/`, живые дампы, локальные секреты и временные файлы;
- перед коммитом проверять `git status --short`;
- не откатывать чужие изменения без явного разрешения.

Если после переноса на Linux Directus падает с ошибкой вида:

```text
/directus/setup/patch-directus-admin-locale.sh: set: line 2: illegal option -
```

исправить CRLF:

```bash
find setup -name "*.sh" -exec sed -i 's/\r$//' {} \;
```

## UI-правила

- Основной режим эксплуатации — темная тема.
- Операционные действия делать в рабочих модулях, а не в стандартных коллекциях Directus.
- Стандартные коллекции Directus считать техническим нижним уровнем, доступ к ним по возможности оставлять только админу.
- Таблицы должны быть плотными, но читаемыми.
- Статусы показывать русским текстом и цветными пинами.
- В быстрых карточках показывать полезную информацию, без внутренних id.
- Не показывать менеджерам и производству лишние служебные справочники.

## Осторожно

- `symbolika-costing-module/index.js` большой и сейчас является главным кандидатом на рефакторинг. Перед каждой правкой делать `node --check`.
- В `setup/create-work-views.sql` есть исторический блок с битой кириллицей. Не исправлять его механически без понимания актуальности этих Directus-витрин.
- На Windows легко случайно сломать кодировку русских строк. Файлы должны оставаться UTF-8.
