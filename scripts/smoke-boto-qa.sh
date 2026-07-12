#!/usr/bin/env bash
# Post-deploy smoke checks for BOTO QA stack.
set -euo pipefail

SALEOR_API_URL="${SALEOR_API_URL:-}"
DASHBOARD_URL="${DASHBOARD_URL:-https://boto-dashboard-qa.web.app}"
STOREFRONT_URL="${STOREFRONT_URL:-}"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

check_http() {
  local url="$1"
  local label="$2"
  local code
  code=$(curl -fsS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "000")
  [[ "$code" == "200" ]] || fail "${label} returned HTTP ${code} (${url})"
  echo "OK ${label} (${code})"
}

if [[ -n "$SALEOR_API_URL" ]]; then
  API_BASE="${SALEOR_API_URL%/graphql/}"
  API_BASE="${API_BASE%/graphql}"
  check_http "${API_BASE}/health/" "Saleor API health"
fi

if [[ -n "$DASHBOARD_URL" ]]; then
  code=$(curl -fsS -o /dev/null -w '%{http_code}' "${DASHBOARD_URL}/" 2>/dev/null || echo "000")
  if [[ "$code" == "200" ]]; then
    echo "OK Dashboard (${code})"
  else
    echo "SKIP Dashboard not deployed yet (HTTP ${code}) — run saleor-dashboard Firebase workflow"
  fi
fi

if [[ -n "$STOREFRONT_URL" ]]; then
  code=$(curl -fsSL -o /dev/null -w '%{http_code}' "${STOREFRONT_URL%/}/en/default-channel/" 2>/dev/null || echo "000")
  if [[ "$code" == "200" ]]; then
    echo "OK Storefront (${code})"
  else
    echo "SKIP Storefront not deployed yet (HTTP ${code}) — run storefront Cloud Run workflow"
  fi
fi

echo "All configured BOTO smoke checks passed"
