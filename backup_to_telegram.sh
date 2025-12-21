#!/usr/bin/env bash

set -Eeuo pipefail

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
