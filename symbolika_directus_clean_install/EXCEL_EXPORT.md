# Экспорт базы в Excel

Скрипт `setup/export-db-to-excel.mjs` выгружает строки таблиц PostgreSQL в один Excel-файл.

По умолчанию экспортируются пользовательские таблицы проекта без служебных `directus_*`, `spatial_ref_sys` и push-подписок.

Запуск из корня репозитория:

```powershell
node symbolika_directus_clean_install\setup\export-db-to-excel.mjs
```

Файл создается в папке `exports/`:

```text
exports/symbolika-export-YYYYMMDD-HHMMSS.xls
```

Каждая таблица попадает на отдельный лист.

Если нужен полный экспорт всех public-таблиц, включая служебные Directus:

```powershell
node symbolika_directus_clean_install\setup\export-db-to-excel.mjs --all-public
```

Папка `exports/` добавлена в `.gitignore`, чтобы выгрузки не попадали в репозиторий.

Для автоматического обновления на сервере скрипт можно запускать по расписанию через cron или планировщик задач.
