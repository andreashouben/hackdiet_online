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
for f in hackdiet/online/hdiet.css hackdiet/online/figures/prev.png favicon.ico; do
    code=$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/$f")
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

# 9. XML export and import: an imported month must carry the trend over
#    from the previous month, as it does for the account it came from
y=${MONTH%-*}; m=$((10#${MONTH#*-} - 1))
(( m == 0 )) && { m=12; y=$((y - 1)); }
PREV=$(printf '%04d-%02d' "$y" "$m")
post -d "q=update_log&s=$SESSION&m=$PREV&HDiet_tzoffset=0&w1=90.0&w8=89.5&w15=89.0&w22=88.5&w28=88.0"
expect "$TMP/out" 'class="monthyear"' "previous month saved"
curl -sS -o "$TMP/export.xml" "$CGI?q=do_exportdb&s=$SESSION&format=xml"
expect "$TMP/export.xml" '<hackersdiet' "XML export"

USER2="${USER}i"
post -d "q=new_account&HDiet_username=$USER2&HDiet_password=$PASS&HDiet_rpassword=$PASS" \
     -d "HDiet_email=smoke@example.com&HDiet_wunit=0&HDiet_dunit=0&HDiet_eunit=0" \
     -d "HDiet_dchar=.&HDiet_height_cm=180&HDiet_tzoffset=0"
post -d "q=validate_user&login=x&HDiet_username=$USER2&HDiet_password=$PASS&HDiet_tzoffset=0"
SESSION2=$(grep -oE 's=[0-9FGJKQW]{40}' "$TMP/out" | head -1 | cut -c3-)
[[ -n "$SESSION2" ]] || fail "login of import account failed"
post -F q=csv_import_data -F s="$SESSION2" -F uploaded_file=@"$TMP/export.xml"
expect "$TMP/out" 'Log items imported: [1-9]' "XML import"

trend1() { curl -sS "$CGI?q=log&s=$1&m=$MONTH&HDiet_tzoffset=0" | grep -oE 'id="T1" value="[^"]*"' | cut -d'"' -f4; }
t_orig=$(trend1 "$SESSION"); t_imp=$(trend1 "$SESSION2")
[[ -n "$t_orig" && -n "$t_imp" ]] && awk -v a="$t_orig" -v b="$t_imp" 'BEGIN { d = a - b; exit !(d < 0.01 && d > -0.01) }' \
    || fail "imported trend differs on day 1: original '$t_orig', imported '$t_imp'"
ok "imported month carries the trend forward ($t_imp)"

echo "All smoke tests passed."
