# Git Workflow Notes

Основная рабочая папка проекта:

```text
symbolika_directus_clean_install/
```

В Git хранить код и конфигурацию:

```text
symbolika_directus_clean_install/docker-compose.yml
symbolika_directus_clean_install/extensions/
symbolika_directus_clean_install/setup/
symbolika_directus_clean_install/README.md
symbolika_directus_clean_install/INSTALL_CLEAN.md
symbolika_directus_clean_install/.env.example
```

Не коммитить живую PostgreSQL-базу:

```text
symbolika_directus_clean_install/database/
```

Также обычно игнорировать:

```text
.cache/
.config/
.local/
.ssh/
logs/
*.log
*.zip
```

## Database Backup

Настройки Directus, коллекции, поля, роли, права и записи хранятся в PostgreSQL. Для точки восстановления делать полный SQL-дамп одним файлом:

```powershell
mkdir db_backups
docker exec symbolika-db pg_dump -U directus -d directus --clean --if-exists > db_backups/dev_initial.sql
```

Если в БД нет реальных/персональных данных, такой дамп можно добавить в Git как контрольную точку. Папка `uploads/` в SQL-дамп не входит; важные файлы из нее сохранять отдельно или коммитить осознанно.

## Опыт деплоя / известные проблемы

### 1. Shell-скрипты должны храниться в формате LF

При переносе проекта с Windows на Linux shell-скрипты (`*.sh`) могут получить окончания строк CRLF, из-за чего контейнер Directus не запускается.

Типичная ошибка:

```text
/directus/setup/patch-directus-admin-locale.sh: set: line 2: illegal option -
```

Причина:

```text
Windows перевел файл в формат CRLF.
```

Исправление на сервере:

```bash
find setup -name "*.sh" -exec sed -i 's/\r$//' {} \;
```

Также необходимо настроить репозиторий так, чтобы все `*.sh` всегда коммитились в формате LF. Для этого используется `.gitattributes`.

### 2. Делать PostgreSQL dump только в custom-формате

Для переноса базы используется только PostgreSQL custom dump (формат `-Fc`), который затем восстанавливается через `pg_restore`.

Команда создания:

```bash
docker exec symbolika-db \
  pg_dump \
  -U directus \
  -d directus \
  -Fc \
  -f /tmp/directus.dump
```

После этого скопировать файл из контейнера:

```bash
docker cp symbolika-db:/tmp/directus.dump backups/directus.dump
```

Не использовать SQL dump для переноса.

Перед восстановлением рекомендуется проверить дамп:

```bash
pg_restore --list directus.dump
```

Если команда успешно выводит содержимое архива, значит дамп корректный.

## Agent Pipeline

1. Перед первым коммитом создать `.gitignore`.
2. Убедиться, что `symbolika_directus_clean_install/database/` не попадает в Git.
3. При необходимости создать полный дамп БД в `db_backups/dev_initial.sql`.
4. Показать пользователю `git status` и список файлов, которые попадут в коммит.
5. Сделать первый коммит: `Initial local Directus setup`.
6. Дальше перед каждой заметной правкой делать маленькие коммиты, чтобы можно было быстро откатиться.
7. Ничего не удалять из рабочей папки без явного разрешения пользователя.
