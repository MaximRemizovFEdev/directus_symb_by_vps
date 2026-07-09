# Symbolika Directus Clean Install

Готовый комплект для чистой установки Directus 11 + PostgreSQL под учет заказов «Символика».

Главный файл инструкции:

```text
INSTALL_CLEAN.md
```

Запуск:

```bash
docker compose up -d
docker exec -it symbolika-directus node /directus/setup/import-symbolika.mjs
```
