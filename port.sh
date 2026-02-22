#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/root/packettunnel/config.json"

err() { echo "ERROR: $*" >&2; exit 1; }

# Checks
[ -f "$CONFIG_FILE" ] || err "Config file not found: $CONFIG_FILE"
command -v jq >/dev/null 2>&1 || err "jq is not installed. Install it and retry."

# Read current ports for input1 and output1
mapfile -t PORTS < <(
  jq -r '
    .. | objects
    | select(
        has("name")
        and (.name=="input1" or .name=="output1")
        and has("settings")
        and (.settings | has("port"))
      )
    | .settings.port
  ' "$CONFIG_FILE"
)

[ "${#PORTS[@]}" -eq 2 ] || err "Expected 2 ports (input1/output1), found ${#PORTS[@]}."
[ "${PORTS[0]}" = "${PORTS[1]}" ] || err "Ports are not equal: input1=${PORTS[0]} output1=${PORTS[1]}"

CURRENT_PORT="${PORTS[0]}"
echo "Current port: $CURRENT_PORT"

read -r -p "Enter new port: " NEW_PORT

# Validate port
[[ "$NEW_PORT" =~ ^[0-9]+$ ]] || err "Invalid port (not a number)."
if [ "$NEW_PORT" -lt 1 ] || [ "$NEW_PORT" -gt 65535 ]; then
  err "Invalid port (must be 1..65535)."
fi

# Backup
cp -f "$CONFIG_FILE" "${CONFIG_FILE}.bak1"

# Update using jq (safe write)
TMP_FILE="$(mktemp)"
jq --argjson p "$NEW_PORT" '
  def walk(f):
    . as $in
    | if type == "object" then
        reduce keys[] as $key ({}; . + { ($key): ($in[$key] | walk(f)) }) | f
      elif type == "array" then
        map(walk(f)) | f
      else
        f
      end;

  walk(
    if type=="object"
       and has("name")
       and (.name=="input1" or .name=="output1")
       and has("settings")
       and (.settings | has("port"))
    then
      .settings.port = $p
    else
      .
    end
  )
' "$CONFIG_FILE" > "$TMP_FILE"

mv -f "$TMP_FILE" "$CONFIG_FILE"

echo "Port updated to: $NEW_PORT"

read -r -p "Reboot now? (y/n): " REBOOT_CONFIRM
case "$REBOOT_CONFIRM" in
  y|Y)
    echo "Rebooting..."
    reboot
    ;;
  n|N)
    echo "Exit."
    exit 0
    ;;
  *)
    echo "Invalid choice. Exit without reboot."
    exit 1
    ;;
esac
