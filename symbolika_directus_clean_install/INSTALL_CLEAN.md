# Чистая установка Directus «Символика»

Этот пакет поднимает новый Directus рядом со старым, на порту `8057`.

Старый Directus не трогаем.

---

## 1. Загрузить архив на сервер

```bash
scp symbolika_directus_clean_install.zip root@IP_СЕРВЕРА:/root/
```

---

## 2. Распаковать

```bash
cd /root
unzip symbolika_directus_clean_install.zip
cd symbolika_directus_clean_install
```

---

## 3. Запустить новый чистый Directus

```bash
docker compose up -d
```

Проверить:

```bash
docker ps
```

Должны появиться:

- `symbolika-directus`
- `symbolika-db`

---

## 4. Открыть новый Directus

В браузере:

```text
http://IP_СЕРВЕРА:8057
```

Логин:

```text
admin@symb.local
```

Пароль:

```text
ChangeThisAdminPass2026
```

---

## 5. Накатить структуру

Выполни:

```bash
docker exec -it symbolika-directus node /directus/setup/import-symbolika.mjs
```

Дождись сообщения:

```text
Готово. Структура Символики создана.
```

---

## 6. Перезапустить Directus

```bash
docker restart symbolika-directus
```

---

## 7. Проверить коллекции

В новом Directus должны быть:

- Заказы
- Позиции заказа
- Технические задания позиций
- Платежи
- Распределение платежей
- Клиенты
- Компании
- Контрагенты
- Оплаты контрагентам
- Склад
- Категории склада

---

## 8. Важно поменять пароли

После проверки обязательно измени в `docker-compose.yml`:

- `ADMIN_PASSWORD`
- `POSTGRES_PASSWORD`
- `KEY`
- `SECRET`

Потом:

```bash
docker compose down
docker compose up -d
```

---

## 9. Старый Directus пока не удаляй

Сначала проверь новую систему на тестовом заказе.

Старые контейнеры:

- `directus-pg`
- `directus`
- `directus-db`

пока не трогай.

---

## 10. Когда всё проверишь

Можно будет переключить домен на новый порт/контейнер и только потом убрать старое.
