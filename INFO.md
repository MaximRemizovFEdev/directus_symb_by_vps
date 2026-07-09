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

## Agent Pipeline

1. Перед первым коммитом создать `.gitignore`.
2. Убедиться, что `symbolika_directus_clean_install/database/` не попадает в Git.
3. При необходимости создать полный дамп БД в `db_backups/dev_initial.sql`.
4. Показать пользователю `git status` и список файлов, которые попадут в коммит.
5. Сделать первый коммит: `Initial local Directus setup`.
6. Дальше перед каждой заметной правкой делать маленькие коммиты, чтобы можно было быстро откатиться.
7. Ничего не удалять из рабочей папки без явного разрешения пользователя.
