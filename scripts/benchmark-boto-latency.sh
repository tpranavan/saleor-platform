#!/usr/bin/env bash
# Benchmark cold/warm latency for BOTO QA cloud stack.
# Usage:
#   export SALEOR_API_URL="https://boto-saleor-api-....run.app/graphql/"
#   export STOREFRONT_URL="https://boto-storefront-....run.app"
#   export DASHBOARD_URL="https://boto-dashboard-qa.web.app"
#   ./scripts/benchmark-boto-latency.sh
#   ./scripts/benchmark-boto-latency.sh --warm-only
set -euo pipefail

SALEOR_API_URL="${SALEOR_API_URL:-}"
STOREFRONT_URL="${STOREFRONT_URL:-}"
DASHBOARD_URL="${DASHBOARD_URL:-https://boto-dashboard-qa.web.app}"
WARM_ONLY=false
WARM_RUNS=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --warm-only) WARM_ONLY=true ;;
    --runs) WARM_RUNS="${2:?}"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
  shift
done

if [[ -z "$SALEOR_API_URL" ]]; then
  echo "Set SALEOR_API_URL (GraphQL base)" >&2
  exit 1
fi

API_BASE="${SALEOR_API_URL%/graphql/}"
API_BASE="${API_BASE%/graphql}"
HEALTH_URL="${API_BASE}/health/"
GRAPHQL_URL="${API_BASE}/graphql/"
GRAPHQL_BODY='{"query":"{ shop { name } }"}'
SF_PATH="${STOREFRONT_URL%/}/en/default-channel/"

curl_timings() {
  local label="$1"
  local method="${2:-GET}"
  local url="$3"
  local data="${4:-}"
  local out
  if [[ "$method" = "POST" && -n "$data" ]]; then
    out=$(curl -fsS -X POST -H "Content-Type: application/json" -d "$data" -o /dev/null -w '%{time_namelookup} %{time_connect} %{time_starttransfer} %{time_total} %{http_code}' "$url" 2>/dev/null || echo "0 0 0 0 000")
  else
    out=$(curl -fsS -o /dev/null -w '%{time_namelookup} %{time_connect} %{time_starttransfer} %{time_total} %{http_code}' "$url" 2>/dev/null || echo "0 0 0 0 000")
  fi
  read -r dns connect ttfb total code <<<"$out"
  printf '%-28s dns=%ss connect=%ss ttfb=%ss total=%ss http=%s\n' "$label" "$dns" "$connect" "$ttfb" "$total" "$code"
}

percentile() {
  local p="$1"
  shift
  printf '%s\n' "$@" | sort -n | awk -v p="$p" '{
    a[NR]=$1
  } END {
    if (NR==0) { print "n/a"; exit }
    idx=int((p/100)*NR+0.999)
    if (idx<1) idx=1
    if (idx>NR) idx=NR
    print a[idx]
  }'
}

bench_warm() {
  local label="$1"
  local method="$2"
  local url="$3"
  local data="${4:-}"
  local totals=()
  local i out
  for ((i=1; i<=WARM_RUNS; i++)); do
    if [[ "$method" = "POST" && -n "$data" ]]; then
      out=$(curl -fsS -X POST -H "Content-Type: application/json" -d "$data" -o /dev/null -w '%{time_total}' "$url" 2>/dev/null || echo "999")
    else
      out=$(curl -fsS -o /dev/null -w '%{time_total}' "$url" 2>/dev/null || echo "999")
    fi
    totals+=("$out")
  done
  local p50 p95
  p50=$(percentile 50 "${totals[@]}")
  p95=$(percentile 95 "${totals[@]}")
  printf '%-28s warm p50=%ss p95=%ss (n=%s)\n' "$label" "$p50" "$p95" "$WARM_RUNS"
}

echo "==> BOTO latency benchmark ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
echo "API health:    $HEALTH_URL"
echo "API GraphQL:   $GRAPHQL_URL"
echo "Storefront:    ${SF_PATH:-<unset>}"
echo "Dashboard:     $DASHBOARD_URL/"
echo ""

if [[ "$WARM_ONLY" = false ]]; then
  echo "==> Single-request timings (instance may be warm if recently used)"
  curl_timings "API /health/" GET "$HEALTH_URL"
  curl_timings "API GraphQL shop" POST "$GRAPHQL_URL" "$GRAPHQL_BODY"
  if [[ -n "$STOREFRONT_URL" ]]; then
    curl_timings "Storefront channel" GET "$SF_PATH"
  fi
  curl_timings "Dashboard /" GET "${DASHBOARD_URL}/"
  echo ""
fi

echo "==> Warm run stats (${WARM_RUNS} consecutive requests)"
bench_warm "API /health/" GET "$HEALTH_URL"
bench_warm "API GraphQL shop" POST "$GRAPHQL_URL" "$GRAPHQL_BODY"
if [[ -n "$STOREFRONT_URL" ]]; then
  bench_warm "Storefront channel" GET "$SF_PATH"
fi
bench_warm "Dashboard /" GET "${DASHBOARD_URL}/"

echo ""
echo "==> QA targets (guidance)"
echo "API /health/ warm p95 < 0.5s | GraphQL warm p95 < 1.0s"
echo "Storefront warm p95 < 2.0s | Dashboard warm p95 < 0.3s"
echo "Cold starts (min-instances=0): first request after idle may be 3-15s"
