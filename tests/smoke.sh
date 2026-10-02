#!/usr/bin/env bash
# Smoke tests of the gateway (Annex F, "Cómo se verifica"). Needs only curl.
#
#   GATEWAY_URL=http://localhost:8000 FRONT_ORIGIN=http://localhost:3000 ./tests/smoke.sh
#
# In this repository's CI no service exists behind the gateway, so SMOKE_UPSTREAMS_DOWN=true
# also proves that a dead service gives 503 while the gateway itself stays healthy.
set -uo pipefail

GATEWAY="${GATEWAY_URL:-http://localhost:8000}"
ORIGIN="${FRONT_ORIGIN:-http://localhost:3000}"
UPSTREAMS_DOWN="${SMOKE_UPSTREAMS_DOWN:-false}"
failures=0
HEADERS="$(mktemp)"
trap 'rm -f "$HEADERS"' EXIT

# request METHOD PATH [curl args...]: prints the body, writes the response headers to $HEADERS
request() {
  local method="$1" path="$2"; shift 2
  curl -s -X "$method" -D "$HEADERS" "$GATEWAY$path" "$@"
}
status() { head -1 "$HEADERS" | awk '{print $2}'; }
header() { grep -i "^$1:" "$HEADERS" | head -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//'; }

check() { # check NAME CONDITION(exit code) [DETAIL]
  if [[ "$2" == "0" ]]; then echo "PASS  $1"; else echo "FAIL  $1  $3"; failures=$((failures + 1)); fi
}
contains() { [[ "$1" == *"$2"* ]]; }

# 1. health of the gateway itself
body="$(request GET /health)"
check "/health answers 200" "$([[ "$(status)" == 200 ]]; echo $?)" "got $(status)"

# 2. unknown route: 404 with the common envelope
body="$(request GET /api/v1/nothing-here)"
check "unknown route: 404 NOT_FOUND with the envelope" \
  "$([[ "$(status)" == 404 ]] && contains "$body" '"error":"NOT_FOUND"' && contains "$body" '"traceId"'; echo $?)" "$(status) $body"

# 3. protected route without credential: 401
body="$(request GET /api/v1/patients)"
check "protected route without Authorization: 401 UNAUTHORIZED with the envelope" \
  "$([[ "$(status)" == 401 ]] && contains "$body" '"error":"UNAUTHORIZED"' && contains "$body" '"traceId"'; echo $?)" "$(status) $body"
body="$(request GET /api/v1/patients -H 'Authorization: Basic abc')"
check "an Authorization that is not a bearer token is refused too" "$([[ "$(status)" == 401 ]]; echo $?)" "$(status)"

# 4. correlation: generated when missing, kept when sent, replaced when unsafe; traceId is the same id
request GET /api/v1/patients > /dev/null
generated="$(header X-Correlation-Id)"
check "without X-Correlation-Id the gateway generates one and returns it" "$([[ -n "$generated" ]]; echo $?)"
body="$(request GET /api/v1/patients -H 'X-Correlation-Id: e2e-smoke-1')"
check "a well-formed X-Correlation-Id is kept and is the traceId" \
  "$([[ "$(header X-Correlation-Id)" == "e2e-smoke-1" ]] && contains "$body" '"traceId":"e2e-smoke-1"'; echo $?)" "$(header X-Correlation-Id) $body"
request GET /api/v1/patients -H 'X-Correlation-Id: bad id;with*chars' > /dev/null
check "an unsafe X-Correlation-Id is replaced" "$([[ "$(header X-Correlation-Id)" != *";"* && -n "$(header X-Correlation-Id)" ]]; echo $?)"

# 5. CORS: preflight from the front, exposed headers, unknown origin
request OPTIONS /api/v1/patients -H "Origin: $ORIGIN" -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: idempotency-key,authorization' > /dev/null
allow_headers="$(header Access-Control-Allow-Headers)"
check "preflight from the front answers 204 and allows Idempotency-Key" \
  "$([[ "$(status)" == 204 ]] && contains "$allow_headers" 'Idempotency-Key'; echo $?)" "$(status) $allow_headers"
check "the front origin is echoed, never *" \
  "$([[ "$(header Access-Control-Allow-Origin)" == "$ORIGIN" ]]; echo $?)" "$(header Access-Control-Allow-Origin)"
request GET /api/v1/patients -H "Origin: $ORIGIN" > /dev/null
check "the response exposes X-Correlation-Id and Location" \
  "$(contains "$(header Access-Control-Expose-Headers)" 'X-Correlation-Id' && contains "$(header Access-Control-Expose-Headers)" 'Location'; echo $?)"
request GET /api/v1/patients -H 'Origin: https://evil.example' > /dev/null
check "an unknown origin gets no Access-Control-Allow-Origin" "$([[ -z "$(header Access-Control-Allow-Origin)" ]]; echo $?)" "$(header Access-Control-Allow-Origin)"

# 6. a dead service: only its routes answer 503, the gateway keeps working
if [[ "$UPSTREAMS_DOWN" == "true" ]]; then
  body="$(request GET /api/v1/patients -H 'Authorization: Bearer whatever')"
  check "with the service down its route answers 503 SERVICE_UNAVAILABLE with the envelope" \
    "$([[ "$(status)" == 503 ]] && contains "$body" '"error":"SERVICE_UNAVAILABLE"'; echo $?)" "$(status) $body"
  request GET /health > /dev/null
  check "and the gateway stays healthy" "$([[ "$(status)" == 200 ]]; echo $?)"
fi

# 7. rate limit on sign-in (last: it uses the quota of the client)
limited=0
for _ in $(seq 1 20); do
  body="$(request POST /api/v1/auth/login -H 'Content-Type: application/json' -d '{"username":"x","password":"y"}')"
  if [[ "$(status)" == 429 ]]; then
    limited=1
    break
  fi
done
check "beyond the limit sign-in answers 429 TOO_MANY_REQUESTS with Retry-After" \
  "$([[ "$limited" == 1 ]] && contains "$body" '"error":"TOO_MANY_REQUESTS"' && [[ -n "$(header Retry-After)" ]]; echo $?)" "$(status) $body"

echo
if [[ "$failures" -gt 0 ]]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all gateway checks passed"
