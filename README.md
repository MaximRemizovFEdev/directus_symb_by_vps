# directus_symb_by_vps

Код и дамп базы для локального/серверного запуска Directus проекта «Символика».

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

3. Проверить, что контейнеры запущены:

```bash
docker ps
```

Должны быть `symbolika-db` и `symbolika-directus`.

4. Восстановить полный дамп базы:

```bash
docker exec -i symbolika-db psql -U directus -d directus < ../full_directus_backup.sql
```

5. Перезапустить Directus:

```bash
docker restart symbolika-directus
```

6. Открыть Directus:

```text
http://localhost:8057
```

Логин: `admin@symb.local`

Пароль по умолчанию указан в `symbolika_directus_clean_install/docker-compose.yml`.

## Важно

- Живая база лежит в `symbolika_directus_clean_install/database/` и не хранится в Git.
- Загруженные файлы лежат в `symbolika_directus_clean_install/uploads/` и не входят в SQL-дамп.
- После запуска на сервере нужно заменить пароли, `KEY` и `SECRET` в `docker-compose.yml`.
