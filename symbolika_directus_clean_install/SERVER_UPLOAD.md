# Загрузка релиза на сервер

Эта инструкция описывает только перенос файлов и базы. Первичный запуск выполняется по [FIRST_SERVER_SETUP.md](FIRST_SERVER_SETUP.md).

## 1. Что переносится

- код — через Git;
- база — отдельным PostgreSQL custom dump `-Fc`;
- пользовательские файлы Directus — отдельным архивом каталога `uploads`, если они нужны;
- секреты — вручную в серверный `.env`, никогда не через Git;
- макеты на Яндекс Диске переносить не нужно.

Каталог `database` копировать между Windows и Linux нельзя.

## 2. Подготовить сервер

Нужен Linux-сервер с Docker Engine, Docker Compose plugin, Git и доступом по SSH.

Рекомендуемый каталог:

```bash
sudo mkdir -p /opt/symbolika
sudo chown "$USER":"$USER" /opt/symbolika
cd /opt/symbolika
```

## 3. Настроить доступ GitHub

Предпочтителен deploy key:

```bash
ssh-keygen -t ed25519 -C "symbolika-server" -f ~/.ssh/symbolika_deploy
cat ~/.ssh/symbolika_deploy.pub
```

Добавьте публичный ключ в GitHub → репозиторий → `Settings → Deploy keys` без права записи. Настройте `~/.ssh/config` и клонируйте по SSH. Не вставляйте GitHub-токен в URL remote.

```bash
git clone git@github.com:MaximRemizovFEdev/directus_symb_by_vps.git
cd directus_symb_by_vps/symbolika_directus_clean_install
```

Для обновления существующей установки:

```bash
cd /opt/symbolika/directus_symb_by_vps
git fetch origin
git checkout dev-v1
git pull --ff-only origin dev-v1
```

Перед `pull` серверный рабочий каталог должен быть чистым. `.env`, `database`, `uploads` и дампы не должны отслеживаться Git.

## 4. Передать дамп базы

На рабочем компьютере создайте и проверьте custom dump:

```powershell
docker exec symbolika-db pg_dump -U directus -d directus -Fc -f /tmp/directus.dump
docker cp symbolika-db:/tmp/directus.dump backups/directus-release.dump
pg_restore --list backups/directus-release.dump
```

Передайте его по SCP:

```powershell
scp backups/directus-release.dump user@SERVER_IP:/opt/symbolika/directus-release.dump
```

Дамп не добавлять в Git.

## 5. Передать локальные uploads при необходимости

```powershell
tar -czf uploads-release.tar.gz -C symbolika_directus_clean_install uploads
scp uploads-release.tar.gz user@SERVER_IP:/opt/symbolika/
```

На сервере распакуйте только в каталог проекта и проверьте путь:

```bash
cd /opt/symbolika/directus_symb_by_vps/symbolika_directus_clean_install
tar -xzf /opt/symbolika/uploads-release.tar.gz
```

## 6. После загрузки

1. Создайте `.env` по [TOKENS_AND_SECRETS.md](TOKENS_AND_SECRETS.md).
2. Выполните [FIRST_SERVER_SETUP.md](FIRST_SERVER_SETUP.md).
3. После проверки удалите переданный дамп из общего каталога либо перенесите в защищенное хранилище с ограниченными правами.

