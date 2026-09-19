#!/usr/bin/env bash
set -euo pipefail

LEVEL=${1:-info}
MESSAGE=${2:-}
TOKEN_FILE=${TELEGRAM_TOKEN_FILE:-/etc/minecraft/secrets/telegram_bot_token}
CHAT_FILE=${TELEGRAM_CHAT_FILE:-/etc/minecraft/secrets/telegram_chat_id}

if [[ -z "$MESSAGE" ]]; then
  echo "usage: telegram.sh <critical|warning|info> <message>" >&2
  exit 2
fi

if [[ ! -r "$TOKEN_FILE" || ! -r "$CHAT_FILE" ]]; then
  echo "telegram secrets are not readable" >&2
  exit 1
fi

TOKEN=$(<"$TOKEN_FILE")
CHAT_ID=$(<"$CHAT_FILE")
TEXT="[$LEVEL] minecraft.nikchester.ru: $MESSAGE"

curl -fsS \
  -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  --data-urlencode "text=${TEXT}" \
  >/dev/null
