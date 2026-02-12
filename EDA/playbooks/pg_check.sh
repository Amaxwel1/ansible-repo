#!/usr/bin/env bash
set -euo pipefail

DB_HOST="10.208.xxx.xxxx"
DB_PORT="5433"
DB_NAME="xxxxxxx"
DB_USERNAME="xxxxxx"
PGPASSWORD="xxxxxxxx"
export PGPASSWORD

SAIDA="/root/logs/$(hostname)_core_$(date '+%Y%m%d').log"
EDA_WEBHOOK_URL="${EDA_WEBHOOK_URL:-http://127.0.0.1:5000}"
FAIL_COOLDOWN_SECONDS="${FAIL_COOLDOWN_SECONDS:-300}" 

_last_fail_sent=0

post_eda_failed() {
  local error="$1"
  local ts
  ts="$(date '+%d/%m/%Y %H:%M:%S')"

  error="${error//\"/\\\"}"

  curl -sS -X POST "$EDA_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"type\": \"db_connection\",
      \"db_status\": \"failed\",
      \"db_name\": \"${DB_NAME}\",
      \"hostname\": \"$(hostname)\",
      \"log_file\": \"${SAIDA}\",
      \"error\": \"${error}\",
      \"timestamp\": \"${ts}\"
    }" >/dev/null || true
}

while true; do
  now_epoch="$(date +%s)"
  ts="$(date '+%d/%m/%Y %H:%M:%S')"

  echo "${ts} Starting" >> "$SAIDA"

  READY_OUT="$(pg_isready --dbname="$DB_NAME" --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USERNAME" 2>&1)"
  READY_RC=$?
  echo "${ts} ${READY_OUT}" >> "$SAIDA"

  SELECT_OUT="$(psql --dbname="$DB_NAME" --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USERNAME" --command='SELECT now()' -t 2>&1)"
  SELECT_RC=$?
  echo "${ts} SELECT: ${SELECT_OUT}" >> "$SAIDA"

  echo "${ts} Done" >> "$SAIDA"

  if [[ "$READY_RC" -ne 0 || "$SELECT_RC" -ne 0 ]]; then
    if (( now_epoch - _last_fail_sent >= FAIL_COOLDOWN_SECONDS )); then
      if [[ "$SELECT_RC" -ne 0 ]]; then
        post_eda_failed "$SELECT_OUT"
      else
        post_eda_failed "$READY_OUT"
      fi
      _last_fail_sent=$now_epoch
    fi
  fi

  sleep 5
done
