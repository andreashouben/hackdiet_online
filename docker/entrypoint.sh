#!/bin/sh
set -e

DB=/server/pub/hackdiet
SECRETS="$DB/.secrets"

# Create the database directory tree (also on a fresh, empty volume)
for d in Users Sessions RememberMe Pubname Invitations Backups; do
    mkdir -p "$DB/$d"
done
chown -R www-data:www-data "$DB"

# Secrets: a value set in the environment wins; otherwise use the one
# stored in the volume, generating it on first start. Keeping them in the
# volume means embedded badge URLs and "remember me" cookies survive
# container updates.
mkdir -p "$SECRETS"
chmod 700 "$SECRETS"
secret() {  # secret <file>: print stored secret, create it if missing
    if [ ! -s "$SECRETS/$1" ]; then
        head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$SECRETS/$1"
        chmod 600 "$SECRETS/$1"
        echo "Generated new $1 in $SECRETS" >&2
    fi
    cat "$SECRETS/$1"
}
[ -n "$HDIET_BADGE_KEY" ] || HDIET_BADGE_KEY=$(secret badge_key)
[ -n "$HDIET_SALT" ]      || HDIET_SALT=$(secret salt)
export HDIET_BADGE_KEY HDIET_SALT
export HDIET_REGISTRATION="${HDIET_REGISTRATION:-open}"

# HackDiet.pl logs sign-in failures via syslog; give it a /dev/log
busybox syslogd -O /dev/stdout

exec apache2ctl -D FOREGROUND
