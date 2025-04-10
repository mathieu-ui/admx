#!/usr/bin/env bash
set -euo pipefail

RED=$(printf '\033[1;31m')
GREEN=$(printf '\033[1;32m')
YELLOW=$(printf '\033[1;33m')
BLUE=$(printf '\033[1;34m')
MAGENTA=$(printf '\033[1;35m')
CYAN=$(printf '\033[1;36m')
WHITE=$(printf '\033[1;37m')
RESET=$(printf '\033[0m')

print_help() {
  echo "Usage: $0 [-h|--help] <logfile>"
  echo "       cat <logfile> | $0"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  print_help
  exit 0
fi

is_access_log() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]] && grep -q "\[" <<< "$1" && grep -q "\"" <<< "$1"
}

process_access_log() {
  local ln="$1"
  local ip date req method path status stat_color

  ip=$(cut -d' ' -f1 <<< "$ln")
  date=$(sed -n 's/.*\[\(.*\)\].*/\1/p' <<< "$ln")
  req=$(awk -F'"' '{print $2}' <<< "$ln")
  method=$(awk '{print $1}' <<< "$req")
  path=$(awk '{print $2}' <<< "$req")
  status=$(awk '{print $(NF-1)}' <<< "$ln")

  if [[ "$status" =~ ^2 ]]; then
    stat_color=$BLUE
  elif [[ "$status" =~ ^3 ]]; then
    stat_color=$MAGENTA
  else
    stat_color=$RED
  fi

  echo -e "${YELLOW}${ip}${RESET} - [${GREEN}${date}${RESET}] \"${CYAN}${method}${RESET} ${WHITE}${path}${RESET}\" ${stat_color}${status}${RESET}"
}

process_error_log() {
  local ln="$1"
  ln=$(sed -E "s/\[([A-Z][a-z]{2} [A-Z][a-z]{2} [0-9]{2} [0-9:.]+ [0-9]{4})\]/[${GREEN}\1${RESET}]/" <<< "$ln")
  ln=$(sed -E "s/\[([a-z_]+:[a-z]+)\]/[${YELLOW}\1${RESET}]/g" <<< "$ln")
  ln=$(sed -E "s/\[([eE]rror)\]/[${RED}\1${RESET}]/g" <<< "$ln")
  ln=$(sed -E "s/\[([wW]arn)\]/[${MAGENTA}\1${RESET}]/g" <<< "$ln")
  ln=$(sed -E "s/\[([nN]otice)\]/[${CYAN}\1${RESET}]/g" <<< "$ln")
  ln=$(sed -E "s/\[([iI]nfo)\]/[${BLUE}\1${RESET}]/g" <<< "$ln")
  echo -e "$ln"
}

main() {
  while IFS= read -r ln; do
    if is_access_log "$ln"; then
      process_access_log "$ln"
    else
      process_error_log "$ln"
    fi
  done
}

if [ -t 0 ]; then
  if [ -z "${1:-}" ]; then
    print_help
    exit 1
  fi
  main < "$1"
else
  main
fi
