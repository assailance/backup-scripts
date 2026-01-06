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

# Logging functions
log() {
  local level="$1"
  local color="$2"
  local message="$3"
  local timestamp

  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  echo -e "${color}[${timestamp}] [$level] ${message}${COLOR_RESET}" >&2
}

info()    { log INFO    "$COLOR_INFO"    "$1"; }
success() { log SUCCESS "$COLOR_SUCCESS" "$1"; }
wrong()   { log WRONG   "$COLOR_ERROR"   "$1"; }
error()   { log ERROR   "$COLOR_ERROR"   "$1"; }

# Interactive functions
input() { read -rp "$(echo -e "${COLOR_WARN}${1}${COLOR_RESET}")" "$2"; }

# Error handler
on_error() {
  local code=$?
  error "Script failed with exit code ${code}"
  exit "$code"
}

trap on_error ERR

# Environments & validation
create_env() {
  local token chat_id

  while true; do
    # Get bot token
    while true; do
      input "Enter the bot token: " token

      if [[ -z "$token" ]]; then
        wrong "Bot token cannot be empty!"
      elif [[ ! "$token" =~ ^[0-9]+:[a-zA-Z0-9_-]{35}$ ]]; then
        wrong "Invalid bot token format!"
      else
        break
      fi
    done

    # Get chat ID
    while true; do
      input "Enter the chat ID: " chat_id

      if [[ -z "$chat_id" ]]; then
        wrong "Chat ID cannot be empty!"
      elif [[ ! "$chat_id" =~ ^-?[0-9]+$ ]]; then
        wrong "Invalid chat ID format!"
      else
        break
      fi
    done

    info "Checking Telegram bot..."
    response=$(curl -sS -o /dev/null -w "%{http_code}" -X POST \
      "https://api.telegram.org/bot${token}/sendMessage" \
      -d chat_id="${chat_id}" \
      -d text="Hi, it's a test message for the PostgreSQL backup script!"
    )

    if [[ "$response" -ne 200 ]]; then
      wrong "Invalid bot token, chat ID, or Telegram API error!"
    else
      success "Bot token and chat ID are valid."
      break
    fi
  done

  cat > "$ENV_FILE" <<EOF
TELEGRAM_BOT_TOKEN=${token}
TELEGRAM_CHAT_ID=${chat_id}
EOF

  chmod 600 "$ENV_FILE"
  success ".env file successfully created!"
}

load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    info ".env file not found. Creating a new one..."
    create_env
  fi

  export $(grep -v '^#' "$ENV_FILE" | xargs)
  validate_env
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
  if [[ $# -ne 3 ]]; then
    error "Usage: $0 <postgres_container> <db_name> <db_user>"
    exit 1
  fi

  CONTAINER_NAME="$1"
  DATABASE_NAME="$2"
  POSTGRES_USER="$3"

  if ! docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2> /dev/null | grep -q true; then
    error "Docker container does not exist or is not running: $CONTAINER_NAME"
    exit 1
  fi
}

# Creating & cleanup backup
create_backup() {
  local timestamp dump_name dump_path

  timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  dump_name="${CONTAINER_NAME}_${timestamp}.sql"
  dump_path="/tmp/${dump_name}"

  info "Creating PostgreSQL dump from container ${CONTAINER_NAME}..."

  if ! docker exec "$CONTAINER_NAME" \
      pg_dump -U "$POSTGRES_USER" "$DATABASE_NAME" > "$dump_path"; then
    error "PostgreSQL dump failed"
    cleanup "$dump_path"
    return 1
  fi

	success "Dump successfully completed: $dump_path"

  echo "$dump_path"
}

cleanup() {
  local path="$1"

  rm -f "$path"
  info "Temporary file removed"
}

# Sending notification
send_backup() {
  local backup_path="$1"
  local size caption

  size="$(du -h "$backup_path" | cut -f1)"
  info "Backup size: $size"

  info "Sending backup to Telegram..."
  
  caption="$(cat <<EOF
🟢 <b>PostgreSQL database</b> backup completed <b>successfully</b>.
≡≡≡≡≡≡≡≡≡≡≡≡≡≡≡
Container: <b>${CONTAINER_NAME}</b>
Database: <b>${DATABASE_NAME}</b>
Backup size: <b>${size}</b>
EOF
)"

  response="$(
    curl -sS -o /dev/null -w "%{http_code}" \
      --connect-timeout 10 \
      --max-time 120 \
      -X POST \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
      -F chat_id="$TELEGRAM_CHAT_ID" \
      -F document=@"$backup_path" \
      -F caption="$caption" \
      -F parse_mode="HTML"
  )"
  curl_code=$?

  if [[ "$curl_code" -eq 0 && "$response" == "200" ]]; then
    success "Backup sent successfully!"
    return 0
  fi

  # Error handling
  if [[ "$curl_code" -eq 28 ]]; then
    error "Telegram request timed out"
  else
    error "Failed to send backup to Telegram (HTTP ${response:-unknown})"
  fi

  cleanup "$backup_path"
  return 1
}

main() {
  info "PostgreSQL backup script started..."

  load_env
  validate_args "$@"

	info "Database to backup: $DATABASE_NAME"

  local dump
  if ! dump="$(create_backup)"; then
    exit 1
  fi

  if ! send_backup "$dump"; then
    exit 1
  fi

  cleanup "$dump"
  success "PostgreSQL backup finished successfully!"
}

main "$@"
