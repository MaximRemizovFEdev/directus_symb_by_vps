#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${1:-/opt/symbolika/directus_symb_by_vps}"
BRANCH="${2:-dev-v1}"
PROJECT_DIR="${REPO_ROOT}/symbolika_directus_clean_install"
BACKUP_DIR="${SYMBOLIKA_BACKUP_DIR:-/opt/symbolika/backups}"
DB_CONTAINER="symbolika-db"
DIRECTUS_CONTAINER="symbolika-directus"

log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  printf '\nОШИБКА: %s\n' "$*" >&2
  exit 1
}

for command_name in git docker curl; do
  command -v "$command_name" >/dev/null 2>&1 || fail "Не найдена команда: ${command_name}"
done

docker compose version >/dev/null 2>&1 || fail "Не установлен Docker Compose plugin"
test -d "${REPO_ROOT}/.git" || fail "Репозиторий не найден: ${REPO_ROOT}"
test -f "${PROJECT_DIR}/docker-compose.yml" || fail "docker-compose.yml не найден: ${PROJECT_DIR}"
test -f "${PROJECT_DIR}/.env" || fail "Серверный .env не найден: ${PROJECT_DIR}/.env"

cd "$REPO_ROOT"

if test -n "$(git status --porcelain --untracked-files=normal)"; then
  git status --short
  fail "На сервере есть незакоммиченные файлы. Обновление остановлено без их изменения."
fi

log "Получение ветки origin/${BRANCH}"
git fetch --prune origin "$BRANCH"
CURRENT_COMMIT="$(git rev-parse HEAD)"
TARGET_COMMIT="$(git rev-parse "origin/${BRANCH}")"

git merge-base --is-ancestor "$CURRENT_COMMIT" "$TARGET_COMMIT" \
  || fail "Ветка сервера разошлась с origin/${BRANCH}; автоматический merge запрещён."

cd "$PROJECT_DIR"
docker compose config >/dev/null
docker compose up -d database

log "Ожидание PostgreSQL"
for attempt in $(seq 1 30); do
  if docker exec "$DB_CONTAINER" pg_isready -U directus -d directus >/dev/null 2>&1; then
    break
  fi
  test "$attempt" -lt 30 || fail "PostgreSQL не перешёл в состояние ready"
  sleep 2
done

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
STAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_NAME="symbolika-before-update-${STAMP}-${CURRENT_COMMIT:0:8}.dump"
CONTAINER_BACKUP="/tmp/${BACKUP_NAME}"
HOST_BACKUP="${BACKUP_DIR}/${BACKUP_NAME}"

log "Создание резервной копии: ${HOST_BACKUP}"
docker exec "$DB_CONTAINER" pg_dump -U directus -d directus -Fc -f "$CONTAINER_BACKUP"
docker exec "$DB_CONTAINER" pg_restore --list "$CONTAINER_BACKUP" >/dev/null
docker cp "${DB_CONTAINER}:${CONTAINER_BACKUP}" "$HOST_BACKUP"
docker exec "$DB_CONTAINER" rm -f "$CONTAINER_BACKUP"
chmod 600 "$HOST_BACKUP"
test -s "$HOST_BACKUP" || fail "Получен пустой backup"

if test "$CURRENT_COMMIT" = "$TARGET_COMMIT"; then
  log "Код уже актуален: ${CURRENT_COMMIT}"
else
  log "Обновление ${CURRENT_COMMIT:0:8} -> ${TARGET_COMMIT:0:8}"
  cd "$REPO_ROOT"
  git checkout "$BRANCH"
  git merge --ff-only "origin/${BRANCH}"
fi

cd "$PROJECT_DIR"

restart_on_error() {
  exit_code=$?
  printf '\nОбновление прервано. Пытаюсь оставить Directus запущенным.\n' >&2
  docker compose up -d directus >/dev/null 2>&1 || true
  docker logs --tail 100 "$DIRECTUS_CONTAINER" >&2 2>/dev/null || true
  exit "$exit_code"
}
trap restart_on_error ERR

log "Установка воспроизводимых зависимостей расширений"
docker compose stop directus >/dev/null 2>&1 || true
docker run --rm -v "${PROJECT_DIR}/extensions/symbolika-calculations:/app" -w /app node:20-alpine npm ci --omit=dev
docker run --rm -v "${PROJECT_DIR}/extensions/symbolika-mail:/app" -w /app node:20-alpine npm ci --omit=dev

log "Применение актуального SQL-слоя"
docker exec -i "$DB_CONTAINER" psql -v ON_ERROR_STOP=1 -U directus -d directus < setup/create-work-views.sql

log "Пересоздание Directus"
docker compose up -d --force-recreate directus

log "Проверка здоровья приложения"
for attempt in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:8057/server/health >/dev/null 2>&1; then
    break
  fi
  test "$attempt" -lt 60 || fail "Directus не прошёл health-check за 120 секунд"
  sleep 2
done

docker compose ps
docker logs --tail 50 "$DIRECTUS_CONTAINER"
trap - ERR

FINAL_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
log "Готово. Версия: ${FINAL_COMMIT}. Backup: ${HOST_BACKUP}"
