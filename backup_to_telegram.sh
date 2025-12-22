#!/usr/bin/env bash

set -Eeuo pipefail

# Global constants
ENV_FILE="$(dirname "$0")/.env"

# ANSI color codes
readonly COLOR_RESET="\033[0m"
readonly COLOR_INFO="\033[0;36m"
readonly COLOR_SUCCESS="\033[0;32m"
readonly COLOR_WARN="\033[0;33m"
readonly COLOR_ERROR="\033[0;31m"

# Logging
log() {
  local level="$1"
  local color="$2"
  local message="$3"
  local timestamp

  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  echo -e "${color}[${timestamp}] [$level] ${message}${COLOR_RESET}" >&2;
}

info()    { log INFO    "$COLOR_INFO"    "$1"; }
success() { log SUCCESS "$COLOR_SUCCESS" "$1"; }
warn()    { log WARN    "$COLOR_WARN"    "$1"; }
error()   { log ERROR   "$COLOR_ERROR"   "$1"; }

# Error handler
on_error() {
  local code=$?
  error "Script failed with exit code ${code}"
  exit "$code"
}

trap on_error ERR

# Environments & Validation 
load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    error ".env file not found: $ENV_FILE"
    exit 1
  fi

  export $(grep -v '^#' "$ENV_FILE" | xargs)
}

validate_env() {
  local vars=(
    TELEGRAM_BOT_TOKEN
    TELEGRAM_CHAT_ID
  )

  for v in "${vars[@]}"; do
    if [[ -z "${!v:-}" ]]; then
      error "Environment variable $v is not set"
      exit 1
    fi
  done
}

validate_args() {
  if [[ $# -ne 2 ]]; then
    error "Usage: $0 <backup_name> <directory_path>"
    exit 1
  fi

  BACKUP_NAME="$1"
  BACKUP_SOURCE_DIR="$2"

  if [[ ! -d "$BACKUP_SOURCE_DIR" ]]; then
    error "Directory does not exist: $BACKUP_SOURCE_DIR"
    exit 1
  fi
}

# Creating & cleanup backup
create_archive() {
  local timestamp archive_name archive_path

  timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  archive_name="${BACKUP_NAME// /_}_${timestamp}.tar.gz"
  archive_path="/tmp/${archive_name}"

  info "Creating archive ${archive_path}..."

  tar -czf "$archive_path" \
    -C "$(dirname "$BACKUP_SOURCE_DIR")" \
    "$(basename "$BACKUP_SOURCE_DIR")"

  echo "$archive_path"
}

cleanup() {
  local archive_path="$1"

  rm -f "$archive_path"
  info "Temporary file removed"
}

# Sending notification
send_backup() {
  local archive_path="$1"
  local size caption

  info "Sending archive to Telegram..."

  size="$(du -h "$archive_path" | cut -f1)"
  caption="$(cat <<EOF
🟢 Резервное <b>копирование</b> директории успешно <b>выполнено</b>.
≡≡≡≡≡≡≡≡≡≡≡≡≡≡≡
Название: <b>${BACKUP_NAME}</b>
Путь: <i>${BACKUP_SOURCE_DIR}</i>
Итоговый размер: <b>${size}</b>
EOF
)"

  curl -sS -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F chat_id="$TELEGRAM_CHAT_ID" \
    -F document=@"$archive_path" \
    -F caption="$caption" \
    -F parse_mode="HTML" \
    > /dev/null

  success "Archive sent successfully!"
}

main() {
  info "Backup script started..."

  load_env
  validate_env
  validate_args "$@"

  info "Directory to backup: $BACKUP_SOURCE_DIR"

  local archive
  archive="$(create_archive)"

  send_backup "$archive"
  cleanup "$archive"

  success "Backup finished successfully!"
}

main "$@"
