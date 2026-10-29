#!/bin/sh
set -eu
set -f
. "${SWFENCE_ROOT:-}/usr/lib/swfence/common.sh"
root_required
json_lib
work=$(mktemp -d "$R/tmp/swfence-config.XXXXXX")
lock=$R/var/lock/swfence-config
mkdir -p "$R/var/lock" "$R/tmp/.uci"
locked=0
trap '[ "$locked" = 0 ] || rmdir "$lock"; rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
reply() {
    json_init
    json_add_boolean ok "$1"
    json_add_string message "$2"
    json_dump
    exit 0
}
mkdir "$lock" 2>/dev/null || reply 0 'Another configuration update is running.'
locked=1
# Bound the request before parsing. Only ASCII configuration strings are accepted.
head -c 16385 > "$work/request"
[ "$(wc -c < "$work/request")" -le 16384 ] || reply 0 'Request too large.'
json_load "$(cat "$work/request")" 2>/dev/null || reply 0 'Invalid JSON.'
for key in enabled macs router_ip lan_subnet local_host local_port; do
    json_get_type kind "$key" || reply 0 "Missing field: $key."
    [ "$kind" = string ] || reply 0 "Expected a string for $key."
    json_get_var value "$key"
    [ "${#value}" -le 2048 ] || reply 0 'Configuration field too long.'
    [ "$(printf '%s' "$value" | wc -l)" = 0 ] || reply 0 'Newlines are not allowed in configuration fields.'
    if printf '%s' "$value" | LC_ALL=C grep -q '[^ -~]'; then reply 0 'Use printable ASCII configuration values.'; fi
done
# Optional fields retain compatibility with existing CLI/setup clients.
for key in allowed_ips allowed_domains; do
    if json_get_type kind "$key"; then
        [ "$kind" = string ] || reply 0 "Expected a string for $key."
        json_get_var value "$key"
        [ "${#value}" -le 2048 ] || reply 0 'Configuration field too long.'
        [ "$(printf '%s' "$value" | wc -l)" = 0 ] || reply 0 'Newlines are not allowed in configuration fields.'
        if printf '%s' "$value" | LC_ALL=C grep -q '[^ -~]'; then reply 0 'Use printable ASCII configuration values.'; fi
    fi
done
json_get_var ENABLED enabled
json_get_var MACS macs
json_get_var ROUTER_IP router_ip
json_get_var LAN_SUBNET lan_subnet
json_get_var LOCAL_HOST local_host
json_get_var LOCAL_PORT local_port
ALLOWED_IPS=$(get allowed_ip)
ALLOWED_DOMAINS=$(get allowed_domain)
if json_get_type kind allowed_ips; then json_get_var ALLOWED_IPS allowed_ips; fi
if json_get_type kind allowed_domains; then json_get_var ALLOWED_DOMAINS allowed_domains; fi
. "$LIB/validation.sh"
if ! validate_exceptions > "$work/exceptions.log" 2>&1; then reply 0 "$(tail -c 1000 "$work/exceptions.log")"; fi
case "$ENABLED" in 0|1) ;; *) reply 0 'enabled must be 0 or 1.' ;; esac
if [ "$ENABLED" = 1 ]; then
    if ! render_config "$work" > "$work/render.log" 2>&1; then reply 0 "$(tail -c 1000 "$work/render.log")"; fi
fi
write_env > "$work/expected.env"
cp "$R/etc/config/swfence" "$work/old.uci"
# These are fixed UCI paths; no user input is interpreted as shell code.
uc set swfence.main=swfence
uc set "swfence.main.enabled=$ENABLED"
uc set "swfence.main.router_ip=$ROUTER_IP"
uc set "swfence.main.lan_subnet=$LAN_SUBNET"
uc set "swfence.main.local_host=$LOCAL_HOST"
uc set "swfence.main.local_port=$LOCAL_PORT"
uc -q delete swfence.main.mac || true
for mac in $MACS; do uc add_list "swfence.main.mac=$mac"; done
uc -q delete swfence.main.allowed_ip || true
uc -q delete swfence.main.allowed_domain || true
for ip in $ALLOWED_IPS; do uc add_list "swfence.main.allowed_ip=$ip"; done
for domain in $ALLOWED_DOMAINS; do uc add_list "swfence.main.allowed_domain=$domain"; done
uc commit swfence
"$R/etc/init.d/swfence" reload > "$work/reload.log" 2>&1 || true
if [ -s "$RUN/last-error" ] || ! cmp -s "$work/expected.env" "$STATE/active.env"; then
    message=$(cat "$RUN/last-error" 2>/dev/null || tail -c 1000 "$work/reload.log")
    cp "$work/old.uci" "$R/etc/config/swfence"
    uc -q revert swfence || true
    "$R/etc/init.d/swfence" reload >> "$work/reload.log" 2>&1 || true
    reply 0 "Apply failed; previous settings restored. $message"
fi
reply 1 'Settings applied. Verify the local diagnostics and console traffic.'
