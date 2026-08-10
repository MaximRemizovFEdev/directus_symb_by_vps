# directus_symb_by_vps

Код проекта Directus для учетной системы «Символика».

Все пользовательские и серверные инструкции собраны в папке [`symbolika_directus_clean_install/Инструкции`](symbolika_directus_clean_install/Инструкции/README.md).

## Развертывание

1. Склонировать репозиторий:

```bash
git clone https://github.com/MaximRemizovFEdev/directus_symb_by_vps.git
cd directus_symb_by_vps/symbolika_directus_clean_install
```

2. Запустить контейнеры:

```bash
docker compose up -d
```

Если используется старый Compose:

```bash
docker-compose up -d
```

3. Проверить контейнеры:

```bash
docker ps
```

Должны быть запущены `symbolika-db` и `symbolika-directus`.

4. Восстановить базу только из PostgreSQL custom dump:

```bash
docker cp ../backups/directus.dump symbolika-db:/tmp/directus.dump
docker exec symbolika-db pg_restore -U directus -d directus --clean --if-exists /tmp/directus.dump
```

Не использовать SQL dump для переноса. Актуальная инструкция по созданию и проверке дампа лежит в `INFO.md`.

5. Перезапустить Directus:

```bash
docker restart symbolika-directus
```

6. Открыть Directus:

```text
http://localhost:8057
```

Логин администратора и стартовые переменные окружения указаны в `symbolika_directus_clean_install/docker-compose.yml`.

## Важно

- Живая база лежит в `symbolika_directus_clean_install/database/` и не хранится в Git.
- Загруженные файлы лежат в `symbolika_directus_clean_install/uploads/` и не входят в дамп базы.
- Перед переносом на сервер shell-скрипты должны быть в LF. Это зафиксировано в `.gitattributes`.
- После запуска на сервере нужно заменить пароли, `KEY` и `SECRET` в `docker-compose.yml`.
