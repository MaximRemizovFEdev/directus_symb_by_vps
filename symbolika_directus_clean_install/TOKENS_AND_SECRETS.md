# Токены, пароли и переменные окружения

Все секреты записываются только в серверный файл:

```text
symbolika_directus_clean_install/.env
```

Права файла: `chmod 600 .env`. Не вставляйте секреты в `docker-compose.yml`, `.env.example`, Git, документацию, скриншоты или чат.

## 1. Обязательные системные секреты

| Переменная | Что вставить | Где получить |
|---|---|---|
| `DIRECTUS_KEY` | случайную строку 32+ байта | `openssl rand -hex 32` |
| `DIRECTUS_SECRET` | другую случайную строку 32+ байта | `openssl rand -hex 32` |
| `ADMIN_EMAIL` | email первого администратора | выбрать самостоятельно |
| `ADMIN_PASSWORD` | уникальный сильный пароль | менеджер паролей |
| `POSTGRES_PASSWORD` | уникальный пароль базы | менеджер паролей |
| `SYMBOLIKA_PUBLIC_URL` | внешний HTTPS URL без `/admin` | ваш домен |
| `DIRECTUS_CORS_ORIGIN` | домен системы либо `true` на первом запуске | настройка администратора |

`DIRECTUS_KEY` и `DIRECTUS_SECRET` после запуска не менять без плана миграции сессий и токенов.

## 2. Яндекс Диск

| Переменная | Значение |
|---|---|
| `SYMBOLIKA_YANDEX_DISK_TOKEN` | OAuth-токен приложения Яндекса |
| `SYMBOLIKA_YANDEX_DISK_ROOT` | `app:/Заказы` |
| `SYMBOLIKA_YANDEX_DISK_PUBLISH_FILES` | `true` |
| `SYMBOLIKA_YANDEX_DISK_DELETE_REPLACED` | `true` |

Приложению Яндекса нужны только права `cloud_api:disk.app_folder` и `cloud_api:disk.info`. Полный доступ ко всему Диску не выдавать.

Проверка после перезапуска:

```text
GET https://YOUR_DOMAIN/symbolika-yandex-disk/status
```

Ответ авторизованному администратору: `configured: true`, `connected: true`.

## 3. Browser Push

| Переменная | Значение |
|---|---|
| `SYMBOLIKA_PUSH_PUBLIC_KEY` | публичный VAPID key |
| `SYMBOLIKA_PUSH_PRIVATE_KEY` | приватный VAPID key |
| `SYMBOLIKA_PUSH_SUBJECT` | `mailto:start@symb62.ru` |

Сгенерировать одну пару:

```bash
docker run --rm node:20-alpine sh -c "npx --yes web-push generate-vapid-keys"
```

Push работает только через HTTPS, кроме localhost. Приватный ключ не показывать пользователям.

## 4. ВКонтакте

| Переменная | Значение |
|---|---|
| `SYMBOLIKA_VK_TOKEN` | токен сообщества с правом сообщений |
| `SYMBOLIKA_VK_API_VERSION` | `5.199` |
| `SYMBOLIKA_VK_PRODUCTION_PEER_ID` | peer_id чата/получателя производства |
| `SYMBOLIKA_VK_SCREEN_PRINTING_PEER_ID` | peer_id шелкографии |

Токен создается в управлении сообществом VK. Используйте токен сообщества, не личный пользовательский токен. Для персональных уведомлений сотрудник указывает свой идентификатор в настройках центра уведомлений.

После создания нового токена старый отзовите. Если токен когда-либо попадал в Git или URL, он считается скомпрометированным.

## 5. Telegram

| Переменная | Значение |
|---|---|
| `SYMBOLIKA_TELEGRAM_BOT_TOKEN` | токен от `@BotFather` |

Каждый сотрудник/клиент сначала пишет боту `/start`, после чего в карточке или настройках указывается его `chat_id`. Токен один на систему, `chat_id` индивидуальны.

## 6. SMTP для отправки почты

Для REG.RU:

```env
SYMBOLIKA_SMTP_HOST=mail.hosting.reg.ru
SYMBOLIKA_SMTP_PORT=465
SYMBOLIKA_SMTP_SECURE=true
SYMBOLIKA_SMTP_USER=start@symb62.ru
SYMBOLIKA_SMTP_PASSWORD=<пароль основного ящика>
SYMBOLIKA_EMAIL_FROM="Символика <start@symb62.ru>"
```

Используйте пароль почтового ящика, не пароль ISPmanager.

## 7. IMAP для встроенной почты

```env
SYMBOLIKA_MAIL_MODE=imap
SYMBOLIKA_IMAP_HOST=mail.hosting.reg.ru
SYMBOLIKA_IMAP_PORT=993
SYMBOLIKA_IMAP_SECURE=true
SYMBOLIKA_IMAP_USER=start@symb62.ru
SYMBOLIKA_IMAP_PASSWORD=<пароль основного ящика>
SYMBOLIKA_MAIL_ALLOWED_ALIASES=start@symb62.ru,alias1@symb62.ru,alias2@symb62.ru
```

Для безопасной проверки оставьте `SYMBOLIKA_MAIL_MODE=mock`. После проверки папок, подписей и прав переключите на `imap`.

Псевдонимы перечисляются через запятую без пробелов. Они должны реально поддерживать отправку на почтовом хостинге.

## 8. SMS.ru — необязательно

```env
SYMBOLIKA_SMS_RU_API_ID=<api_id из кабинета SMS.ru>
SYMBOLIKA_SMS_RU_FROM=<согласованное имя отправителя>
```

Не заполняйте эти поля, если SMS-канал не используется. Имя отправителя должно быть предварительно согласовано у провайдера.

## 9. Где хранятся идентификаторы получателей

Системный `.env` содержит ключи провайдеров. Конкретные адресаты задаются в интерфейсе:

- сотрудник — `Центр уведомлений → Настройки`: email, VK, Telegram, push;
- клиент/компания — карточка: основной канал и адрес/идентификатор;
- производство и шелкография — общие `peer_id` в `.env`;
- почтовые псевдонимы и папки — настройки модуля `Почта`.

## 10. Применение изменений

```bash
docker compose up -d --force-recreate directus
docker logs --tail 150 symbolika-directus
```

Проверяйте один канал за раз. Ошибки доставки смотрите в `Управление → Контроль автоматизаций` и в журнале центра уведомлений.

## 11. Обязательная ротация перед боевым запуском

Перед релизом замените:

- старые пароли администратора и PostgreSQL;
- `DIRECTUS_KEY` и `DIRECTUS_SECRET`, если использовались тестовые;
- VK-токен, если он когда-либо был записан в репозиторий;
- GitHub PAT, если он когда-либо находился в URL remote;
- SMTP/IMAP пароль, если передавался небезопасным способом;
- тестовые VAPID-ключи, если их приватная часть была опубликована.

