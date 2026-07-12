#!/bin/sh
# Real end-to-end tests for module/provider/cloudflare.sh's HTTP handling.
# Runs provider_update_record against a fake `curl` on PATH that plays back
# canned Cloudflare API responses per scenario, so these exercise the actual
# shell logic (not just a syntax check) - including cases that only ever show
# up against a live API: a mid-lookup network failure, a 200-with-success:false
# body, and pre-existing duplicate records.
#
# Usage: sh module/provider/cloudflare.test.sh

set -u
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MOCK_DIR="$SCRIPT_DIR/.cloudflare_test_mock"
LOG_FILE="$SCRIPT_DIR/.cloudflare_test_mock.log"

mkdir -p "$MOCK_DIR"

cat > "$MOCK_DIR/curl" <<'MOCKCURL'
#!/bin/sh
# Fake curl: reads $CF_MOCK_SCENARIO to decide how to respond, records every
# call (method + URL) to $CF_MOCK_LOG so tests can assert on request patterns.
method="GET"
url=""
prev=""
for arg in "$@"; do
    case "$prev" in
        -X) method="$arg" ;;
    esac
    case "$arg" in
        http*) url="$arg" ;;
    esac
    prev="$arg"
done
printf "%s %s\n" "$method" "$url" >> "$CF_MOCK_LOG"

case "$CF_MOCK_SCENARIO" in
    no_existing_record)
        case "$method" in
            GET) printf '{"result":[],"success":true,"errors":[]}'; exit 0 ;;
            POST) printf '{"result":{"id":"new1"},"success":true,"errors":[]}'; exit 0 ;;
        esac
        ;;
    one_existing_record)
        case "$method" in
            GET) printf '{"result":[{"id":"rec1","content":"old"}],"success":true,"errors":[]}'; exit 0 ;;
            PATCH) printf '{"result":{"id":"rec1"},"success":true,"errors":[]}'; exit 0 ;;
        esac
        ;;
    duplicate_records)
        case "$method" in
            GET) printf '{"result":[{"id":"rec1"},{"id":"rec2"}],"success":true,"errors":[]}'; exit 0 ;;
            PATCH) printf '{"result":{"id":"rec1"},"success":true,"errors":[]}'; exit 0 ;;
            DELETE) printf '{"result":{"id":"rec2"},"success":true,"errors":[]}'; exit 0 ;;
        esac
        ;;
    lookup_network_failure)
        case "$method" in
            GET) exit 22 ;;
        esac
        ;;
    patch_rejected)
        case "$method" in
            GET) printf '{"result":[{"id":"rec1"}],"success":true,"errors":[]}'; exit 0 ;;
            PATCH) printf '{"result":null,"success":false,"errors":[{"code":9106,"message":"Invalid content"}]}'; exit 0 ;;
        esac
        ;;
esac
exit 1
MOCKCURL
chmod +x "$MOCK_DIR/curl"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/cloudflare.sh"

CLOUDFLARE_API_TOKEN="test-token"
CLOUDFLARE_ZONE_ID="test-zone"
DOMAIN="example.com"
HOST="pi"
export CLOUDFLARE_API_TOKEN CLOUDFLARE_ZONE_ID DOMAIN HOST

PATH="$MOCK_DIR:$PATH"
export PATH

pass=0
fail=0

assert_eq() {
    _desc="$1"; _expected="$2"; _actual="$3"
    if [ "$_expected" = "$_actual" ]; then
        printf "  ok   - %s\n" "$_desc"
        pass=$((pass + 1))
    else
        printf "  FAIL - %s (expected [%s], got [%s])\n" "$_desc" "$_expected" "$_actual"
        fail=$((fail + 1))
    fi
}

run_scenario() {
    CF_MOCK_SCENARIO="$1"
    export CF_MOCK_SCENARIO
    : > "$LOG_FILE"
    CF_MOCK_LOG="$LOG_FILE"
    export CF_MOCK_LOG
}

printf "1. No existing record -> creates via POST\n"
run_scenario no_existing_record
out=$(provider_update_record AAAA "2001:db8::1" 2>&1)
rc=$?
assert_eq "returns success" "0" "$rc"
assert_eq "POSTs a new record" "1" "$(grep -c '^POST ' "$LOG_FILE")"
assert_eq "never issues a PATCH" "0" "$(grep -c '^PATCH ' "$LOG_FILE")"

printf "\n2. One existing record -> updates via PATCH, no duplicate created\n"
run_scenario one_existing_record
out=$(provider_update_record AAAA "2001:db8::1" 2>&1)
rc=$?
assert_eq "returns success" "0" "$rc"
assert_eq "PATCHes the existing record" "1" "$(grep -c '^PATCH ' "$LOG_FILE")"
assert_eq "never issues a POST" "0" "$(grep -c '^POST ' "$LOG_FILE")"

printf "\n3. Duplicate records already exist -> patches one, deletes the rest (self-heal)\n"
run_scenario duplicate_records
out=$(provider_update_record AAAA "2001:db8::1" 2>&1)
rc=$?
assert_eq "returns success" "0" "$rc"
assert_eq "PATCHes the first record" "1" "$(grep -c '^PATCH ' "$LOG_FILE")"
assert_eq "DELETEs the leftover duplicate" "1" "$(grep -c '^DELETE ' "$LOG_FILE")"

printf "\n4. Lookup fails (network/API error) -> aborts, does NOT create a duplicate\n"
run_scenario lookup_network_failure
out=$(provider_update_record AAAA "2001:db8::1" 2>&1)
rc=$?
assert_eq "returns failure" "1" "$rc"
assert_eq "never issues a POST" "0" "$(grep -c '^POST ' "$LOG_FILE")"
assert_eq "never issues a PATCH" "0" "$(grep -c '^PATCH ' "$LOG_FILE")"
case "$out" in
    *"Failed to look up"*) printf "  ok   - prints a lookup error\n"; pass=$((pass + 1)) ;;
    *) printf "  FAIL - expected a lookup error message, got: %s\n" "$out"; fail=$((fail + 1)) ;;
esac

printf "\n5. Cloudflare returns HTTP 200 with success:false -> treated as failure\n"
run_scenario patch_rejected
out=$(provider_update_record AAAA "2001:db8::1" 2>&1)
rc=$?
assert_eq "returns failure" "1" "$rc"
case "$out" in
    *"rejected"*) printf "  ok   - prints a rejection error\n"; pass=$((pass + 1)) ;;
    *) printf "  FAIL - expected a rejection error message, got: %s\n" "$out"; fail=$((fail + 1)) ;;
esac

rm -rf "$MOCK_DIR" "$LOG_FILE"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
