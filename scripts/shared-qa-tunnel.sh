#!/usr/bin/env bash
# SSH tunnel to shared QA Postgres + Redis on fortronx-qa-shared.
#
# Usage:
#   ./scripts/shared-qa-tunnel.sh start
#   ./scripts/shared-qa-tunnel.sh stop
#   ./scripts/shared-qa-tunnel.sh status

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="$ROOT/.shared-qa-tunnel.pid"
SHARED_CONFIG="$ROOT/../../fortronx-qa-shared/config/gcp-config.env"
LOCAL_CONFIG="$ROOT/config/gcp-config.env"

if [[ -f "$LOCAL_CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$LOCAL_CONFIG"
elif [[ -f "$SHARED_CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$SHARED_CONFIG"
else
  echo "Missing config. Copy fortronx-qa-shared/config/gcp-config.env to saleor-platform/config/gcp-config.env" >&2
  exit 1
fi

PROJECT="${GCP_PROJECT_ID:?}"
ZONE="${GCP_ZONE:-us-central1-a}"
VM="${GCP_VM_NAME:-fortronx-qa-shared}"
USER_NAME="${GCP_SSH_USER:-oshirotechnologiesweb}"
LOCAL_PG_PORT="${LOCAL_PG_PORT:-5432}"
LOCAL_REDIS_PORT="${LOCAL_REDIS_PORT:-6379}"

cmd="${1:-status}"

stop_tunnel() {
  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE")"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      echo "Stopped shared QA tunnel (pid $pid)"
    fi
    rm -f "$PID_FILE"
  fi
}

case "$cmd" in
  start)
    stop_tunnel
    gcloud compute ssh "${USER_NAME}@${VM}" \
      --project="$PROJECT" \
      --zone="$ZONE" \
      --tunnel-through-iap \
      -- -N \
      -L "${LOCAL_PG_PORT}:127.0.0.1:5432" \
      -L "${LOCAL_REDIS_PORT}:127.0.0.1:6379" &
    echo $! > "$PID_FILE"
    sleep 2
    if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo "Shared QA tunnel running (pid $(cat "$PID_FILE"))"
      echo "  Postgres: 127.0.0.1:${LOCAL_PG_PORT}"
      echo "  Redis:    127.0.0.1:${LOCAL_REDIS_PORT}"
    else
      rm -f "$PID_FILE"
      echo "Tunnel failed to start" >&2
      exit 1
    fi
    ;;
  stop)
    stop_tunnel
    ;;
  status)
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo "running pid $(cat "$PID_FILE")"
      nc -z 127.0.0.1 "$LOCAL_PG_PORT" && echo "  postgres: open" || echo "  postgres: closed"
      nc -z 127.0.0.1 "$LOCAL_REDIS_PORT" && echo "  redis: open" || echo "  redis: closed"
    else
      echo "stopped"
    fi
    ;;
  *)
    echo "Usage: $0 {start|stop|status}"
    exit 1
    ;;
esac
