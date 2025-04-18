#!/usr/bin/env bash

# Simplified search script: search in filenames or contents using find or locate

# Default flags
DEBUG=0
SHOW_ERR=0
SHOW_HELP=0
INSIDE=0
LOCATE_MODE=0
ONLY_INSIDE=0
UPDATE_DB=0
PATH_FLAG=0
SEARCH_PATH=""

# Usage information
usage() {
  cat <<EOF
Usage: search [-h]
       search [-u]
       search [-d] [-e] [-l] [-i [-o]] STRING [STRING…]
       search [-d] [-e] [-l] [-i [-o]] STRING [PATH] [STRING…]
       search [-d] [-e] [-l] [-i [-o]] [-p PATH] STRING [STRING…]

Options:
  -d, --debug      Show debug info
  -e, --error      Show error messages
  -h, --help       Show this help
  -i, --inside     Search inside files
  -l, --locate     Use locate instead of find
  -o, --only       With -i: only search inside files (skip name search)
  -p, --path PATH  Force search in PATH
  -u, --update     Update the locate/plocate database and exit
EOF
}

# Function to update database
update_db_cmd() {
  if command -v updatedb &>/dev/null; then
    sudo updatedb
  elif command -v plocate-build &>/dev/null; then
    sudo plocate-build
  else
    echo "Error: neither 'updatedb' nor 'plocate-build' found; cannot update database." >&2
    exit 1
  fi
}

# Parse options
OPTS=$(getopt -o dehilop:u --long debug,error,help,inside,locate,only,path:,update -- "$@")
if [ $? -ne 0 ]; then
  usage; exit 1
fi
eval set -- "$OPTS"
while true; do
  case "$1" in
    -d|--debug)    DEBUG=1; shift;;
    -e|--error)    SHOW_ERR=1; shift;;
    -h|--help)     SHOW_HELP=1; shift;;
    -i|--inside)   INSIDE=1; shift;;
    -l|--locate)   LOCATE_MODE=1; shift;;
    -o|--only)     ONLY_INSIDE=1; shift;;
    -p|--path)     PATH_FLAG=1; SEARCH_PATH="$2"; shift 2;;
    -u|--update)   UPDATE_DB=1; shift;;
    --) shift; break;;
    *) break;;
  esac
done

# Enable debug if requested
test "$DEBUG" -eq 1 && set -x

# Show help and exit
if [ "$SHOW_HELP" -eq 1 ]; then
  usage; exit 0
fi

# Update database if requested
if [ "$UPDATE_DB" -eq 1 ]; then
  update_db_cmd
  # exit if no further args
  [ $# -eq 0 ] && exit 0
fi

# Determine which locate command to use
if [ "$LOCATE_MODE" -eq 1 ]; then
  if command -v locate &>/dev/null; then
    LOC_CMD=locate
  elif command -v plocate &>/dev/null; then
    LOC_CMD=plocate
  else
    echo "Error: neither 'locate' nor 'plocate' found. Please install mlocate or plocate." >&2
    exit 1
  fi
fi

# Determine search path: forced or first existing directory
if [ "$PATH_FLAG" -eq 0 ]; then
  for arg in "$@"; do
    if [ -d "$arg" ]; then
      SEARCH_PATH="$arg"; PATH_FLAG=1; break
    fi
  done
fi
[ -z "$SEARCH_PATH" ] && SEARCH_PATH="$PWD"

# Build search terms, skipping the used directory
TERMS=()
SKIP=0
for arg in "$@"; do
  if [ "$PATH_FLAG" -eq 1 ] && [ "$SKIP" -eq 0 ] && [ "$arg" = "$SEARCH_PATH" ]; then
    SKIP=1; continue
  fi
  TERMS+=("$arg")
done

# Require at least one term
if [ ${#TERMS[@]} -eq 0 ]; then
  usage; exit 1
fi

# Prepare temp file for errors
tmp_err=$(mktemp)

# Name-based search results
NAME_RESULTS=()
if [ "$ONLY_INSIDE" -eq 0 ]; then
  if [ "$LOCATE_MODE" -eq 1 ]; then
    # Use selected locate command
    CMD=("$LOC_CMD" -i "${TERMS[0]}")
    for ((i=1; i<${#TERMS[@]}; i++)); do
      CMD+=( '|' "grep -i -- '${TERMS[i]}'" )
    done
    if [ "$SHOW_ERR" -eq 1 ]; then
      mapfile -t NAME_RESULTS < <(eval "${CMD[*]}" 2>&1)
    else
      mapfile -t NAME_RESULTS < <(eval "${CMD[*]}" 2> "$tmp_err")
    fi
  else
    # Use find
    FIND_CMD=(find "$SEARCH_PATH")
    for t in "${TERMS[@]}"; do
      if [[ "$t" == */* ]]; then
        FIND_CMD+=( -ipath "*${t}*" )
      else
        FIND_CMD+=( -iname "*${t}*" )
      fi
    done
    FIND_CMD+=( -print )
    if [ "$SHOW_ERR" -eq 1 ]; then
      mapfile -t NAME_RESULTS < <("${FIND_CMD[@]}" 2>&1)
    else
      mapfile -t NAME_RESULTS < <("${FIND_CMD[@]}" 2> "$tmp_err")
    fi
  fi
fi

# Inside-file search results
INSIDE_RESULTS=()
if [ "$INSIDE" -eq 1 ]; then
  CMD="find \"$SEARCH_PATH\" -type f -print0 | xargs -0 grep -I -i -l -- '${TERMS[0]}'"
  for ((i=1; i<${#TERMS[@]}; i++)); do
    CMD+=" | xargs grep -I -i -l -- '${TERMS[i]}'"
  done
  if [ "$SHOW_ERR" -eq 1 ]; then
    mapfile -t INSIDE_RESULTS < <(eval "$CMD" 2>&1)
  else
    mapfile -t INSIDE_RESULTS < <(eval "$CMD" 2> "$tmp_err")
  fi
fi

# Merge, sort uniquely, display
ALL=("${NAME_RESULTS[@]}" "${INSIDE_RESULTS[@]}")
IFS=$'\n' ALL=( $(printf "%s\n" "${ALL[@]}" | sort -u) )
unset IFS
for entry in "${ALL[@]}"; do
  echo "$entry"
done

# Summarize hidden errors
if [ "$SHOW_ERR" -eq 0 ] && [ -s "$tmp_err" ]; then
  echo "Warning: some error reported during search. Use -e to show them" >&2
fi
rm -f "$tmp_err"
