#!/usr/bin/env bash
#
# End-to-end smoke test for a running Hacker's Diet Online instance.
# Creates a throwaway account, logs in, enters weights, renders charts
# and fetches a badge.
#
# Usage: scripts/smoke-test.sh [base-url]   (default http://localhost:8080)
# With EXPECT_REGISTRATION=closed it only checks that sign-up is refused.

set -euo pipefail

BASE="${1:-http://localhost:8080}"
CGI="$BASE/cgi-bin/HackDiet"
USER="smoke$(date +%s)$RANDOM"
PASS="smoke-test-pw"
MONTH="$(date +%Y-%m)"
# Size of HDiet/Images/steenkin_badge.png, served for invalid badge IDs
PLACEHOLDER_BADGE_BYTES=9754

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok   $*"; }

post() { curl -sS -o "$TMP/out" "$CGI" "$@"; }
expect() {  # expect <file> <pattern> <description>
    grep -qE "$2" "$1" || fail "$3 (pattern '$2' not found)"
    ok "$3"
}

# 1. Redirect and login page
code=$(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' "$BASE/")
[[ "$code" == "302 $CGI" ]] || fail "GET / should redirect to $CGI, got '$code'"
ok "/ redirects to login"
curl -sS -o "$TMP/out" "$CGI"
expect "$TMP/out" 'Please Sign In' "login page"

# 2. Static files
for f in hdiet.css figures/prev.png figures/hdicon.ico; do
    code=$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/hackdiet/online/$f")
    [[ "$code" == 200 ]] || fail "$f returned $code"
done
ok "static files"

# Registration closed: only check that sign-up is refused, then stop
if [[ "${EXPECT_REGISTRATION:-open}" == closed ]]; then
    post -d "q=validate_user&new=x"
    expect "$TMP/out" 'Registration Closed' "sign-up form is disabled"
    post -d "q=new_account&HDiet_username=$USER&HDiet_password=$PASS&HDiet_rpassword=$PASS&HDiet_email=smoke@example.com"
    expect "$TMP/out" 'does not accept new accounts' "account creation is refused"
    echo "All smoke tests passed (registration closed)."
    exit 0
fi

# 3. Create account
post -d "q=new_account&HDiet_username=$USER&HDiet_password=$PASS&HDiet_rpassword=$PASS" \
     -d "HDiet_email=smoke@example.com&HDiet_wunit=0&HDiet_dunit=0&HDiet_eunit=0" \
     -d "HDiet_dchar=.&HDiet_height_cm=180&HDiet_tzoffset=0"
grep -q 'Errors in New Account Request' "$TMP/out" && fail "account creation rejected"
ok "account $USER created"

# 4. Log in
post -d "q=validate_user&login=x&HDiet_username=$USER&HDiet_password=$PASS&HDiet_tzoffset=0"
SESSION=$(grep -oE 's=[0-9FGJKQW]{40}' "$TMP/out" | head -1 | cut -c3-)
[[ -n "$SESSION" ]] || fail "login did not return a session"
ok "login"

# 4b. "Remember me": the cookie must be accepted for this host, and a
#     request carrying it must be signed in without a password.
#     The app sets the cookie from JavaScript: document.cookie = '...'
post -d "q=validate_user&login=x&HDiet_username=$USER&HDiet_password=$PASS&HDiet_remember=y"
COOKIE=$(grep -oE "document\.cookie = '[^']+'" "$TMP/out" | head -1 | cut -d"'" -f2)
[[ -n "$COOKIE" ]] || fail "no remember-me cookie set"
[[ "$COOKIE" != *Domain=* ]] || fail "remember-me cookie has a fixed Domain: $COOKIE"
curl -sS -o "$TMP/out" -H "Cookie: ${COOKIE%%;*}" "$CGI"
expect "$TMP/out" 'class="monthyear"' "remember-me cookie signs in"
# Signing in again replaces the previous session
SESSION=$(grep -oE 's=[0-9FGJKQW]{40}' "$TMP/out" | head -1 | cut -c3-)

# 5. Wrong password (also exercises the syslog path)
post -d "q=validate_user&login=x&HDiet_username=$USER&HDiet_password=wrong"
expect "$TMP/out" 'Sign In Invalid' "wrong password rejected"

# 6. Enter weights and render the monthly chart
post -d "q=update_log&s=$SESSION&m=$MONTH&HDiet_tzoffset=0&w1=85.2&w5=84.9&w10=84.5&w15=84.1&w20=83.8"
expect "$TMP/out" 'class="monthyear"' "weights saved"
ctype=$(curl -sS -o "$TMP/chart.png" -w '%{content_type}' "$CGI?q=chart&s=$SESSION&m=$MONTH&HDiet_tzoffset=0")
[[ "$ctype" == image/png* ]] || fail "monthly chart returned '$ctype'"
ok "monthly chart is a PNG"

# 7. Other pages
for page in "trendan:Trend Analysis" "histreq:Chart Workshop" \
            "dietcalc:Diet Calculator" "calendar:Choose Monthly Log"; do
    curl -sS -o "$TMP/out" "$CGI?q=${page%%:*}&s=$SESSION&HDiet_tzoffset=0"
    expect "$TMP/out" "${page#*:}" "page ${page%%:*}"
done

# 8. Badge: enabling it renders an image; fetching it proves the badge key
#    reaches both CGI programs (otherwise the placeholder comes back)
post -d "q=update_badge&s=$SESSION&badge_term=-1"
BADGE_ID=$(grep -oE 'b=[0-9FGJKQW]+' "$TMP/out" | head -1)
[[ -n "$BADGE_ID" ]] || fail "badge configuration returned no badge ID"
size=$(curl -sS -o /dev/null -w '%{size_download}' "$BASE/cgi-bin/HackDietBadge?t=1&$BADGE_ID")
[[ "$size" -gt 0 && "$size" -ne "$PLACEHOLDER_BADGE_BYTES" ]] \
    || fail "badge returned placeholder or nothing ($size bytes)"
ok "badge ($size bytes)"

echo "All smoke tests passed."
