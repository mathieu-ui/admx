#!/usr/bin/env bash
# Script : script_fetch_info.sh

set -euo pipefail

usage() {
  cat << EOF
Usage: ${0##*/} [-h|--help]

Options:
  -h, --help    Affiche ce message d'aide et quitte
EOF
}

while [[ ${#} -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Option inconnue : $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

echo "=== Nom du système ==="
uname -snrmo
echo

echo "=== Résumé du hardware ==="
echo "- CPU :"
lscpu | grep -E 'Architecture|Model name|Socket \(s\)|Thread|Core|CPU \(s\)' || true
echo "- RAM :"
free -h | awk '/Mem:/ {printf "%s total, %s utilisé, %s libre\n", $2, $3, $4}'
echo "- Disques :"
df -h --total | awk '$1=="total" {printf "%s total, %s utilisé, %s disponible\n", $2, $3, $4}'
echo "- Interfaces réseau :"
ip -brief link show
echo

echo "=== Utilisateurs connectés interactivement ==="
sessions=$(last -Fw | grep -vE 'reboot|shutdown|wtmp')
users=$(echo "$sessions" | awk '{print $1}' | sort | uniq)

printf "%-20s %-15s %-10s %-25s %-10s\n" "Nom complet" "Login" "Connexions" "Dernière connexion" "Type"

for user in $users; do
    count=$(echo "$sessions" | awk -v u="$user" '$1==u {c++} END{print c+0}')
    [ "$count" -eq 0 ] && continue
    last_entry=$(echo "$sessions" | awk -v u="$user" '$1==u {print; exit}')
    terminal=$(echo "$last_entry" | awk '{print $2}')
    host=$(echo "$last_entry" | awk '{print $3}')
    date=$(echo "$last_entry" | awk '{print $4" "$5" "$6" "$7" "$8}')
    if [[ -n "$host" && "$host" != "-" ]]; then
        type_conn="SSH"
    else
        type_conn="LOCAL"
    fi
    fullname=$(getent passwd "$user" | cut -d: -f5 | cut -d, -f1)
    printf "%-20s %-15s %-10s %-25s %-10s\n" "$fullname" "$user" "$count" "$date" "$type_conn"
done
