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
  echo -e "${color}[${timestamp}] [$level] ${message}${COLOR_RESET}"
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

# Environment variables
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
    BACKUP_SOURCE_DIR
  )

  for v in "${vars[@]}"; do
    if [[ -z "${!v:-}" ]]; then
      error "Environment variable $v is not set"
      exit 1
    fi
  done

  if [[ ! -d "$BACKUP_SOURCE_DIR" ]]; then
    error "Source directory does not exist: $BACKUP_SOURCE_DIR"
    exit 1
  fi
}
