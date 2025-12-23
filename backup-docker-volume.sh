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

    # Validate bot token and chat ID
    info "Checking Telegram bot..."
    response=$(curl -sS -o /dev/null -w "%{http_code}" -X POST \
      "https://api.telegram.org/bot${token}/sendMessage" \
      -d chat_id="${chat_id}" \
      -d text="Hi, it's a test message for the backup script!"
    )
    
    if [[ "$response" -ne 200 ]]; then
        wrong "Invalid bot token, chat ID, or Telegram API error!"
    else
        success "Bot token and chat ID are valid."
        break
    fi
  done

  # Creating .env file
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
  if [[ $# -ne 1 ]]; then
    error "Usage: $0 <docker_volume>"
    exit 1
  fi

  VOLUME_NAME="$1"

  if ! docker volume inspect "$VOLUME_NAME" > /dev/null 2>&1; then
    error "Docker volume does not exist: $VOLUME_NAME"
    exit 1
  fi
}

# Creating & cleanup backup
create_archive() {
  local timestamp archive_name archive_path

  timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  archive_name="${VOLUME_NAME// /_}_${timestamp}.tar.gz"
  archive_path="/tmp/${archive_name}"

  info "Creating archive from Docker volume ${VOLUME_NAME}..."

  docker run --rm \
    --user $(id -u):$(id -g) \
    -v "${VOLUME_NAME}:/data:ro" \
    -v "/tmp:/backup" \
    alpine \
    tar -czf "/backup/${archive_name}" -C /data .

  success "Archive created: $archive_path"

  echo "$archive_path"
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

  info "Sending archive to Telegram..."

  size="$(du -h "$backup_path" | cut -f1)"
  caption="$(cat <<EOF
🟢 Резервное копирование <b>тома</b> успешно <b>выполнено</b>.
≡≡≡≡≡≡≡≡≡≡≡≡≡≡≡
Том: <b>${VOLUME_NAME}</b>
Итоговый размер: <b>${size}</b>
EOF
)"

  curl -sS -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F chat_id="$TELEGRAM_CHAT_ID" \
    -F document=@"$backup_path" \
    -F caption="$caption" \
    -F parse_mode="HTML" \
    > /dev/null

  success "Archive sent successfully!"
}

main() {
  info "Docker volume backup script started..."

  load_env
  validate_args "$@"

  info "Volume to backup: $VOLUME_NAME"

  local archive
  archive="$(create_archive)"

  send_backup "$archive"
  cleanup "$archive"

  success "Docker volume backup finished successfully!"
}

main "$@"
