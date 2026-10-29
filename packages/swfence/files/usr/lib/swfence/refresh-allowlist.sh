#!/bin/sh
set -eu
set -f
. "${SWFENCE_ROOT:-}/usr/lib/swfence/common.sh"
. "$LIB/validation.sh"
root_required
if [ "${1:-}" = daemon ]; then
    while :; do
        /bin/sh "$LIB/refresh-allowlist.sh" once || true
        sleep 60
    done
fi
[ "${1:-}" = once ] || exit 1
mkdir -p "$RUN" "$R/tmp" "$R/var/lock"
[ -f "$STATE/active.env" ] || exit 0
work=$(mktemp -d "$R/tmp/swfence-domains.XXXXXX")
locked=0
lock=$R/var/lock/swfence-apply
trap '[ "$locked" = 0 ] || rmdir "$lock"; rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
cp "$STATE/active.env" "$work/applied.env"
ENABLED=0 ALLOWED_DOMAINS= ALLOWED_IPS= ROUTER_IP=
while IFS='=' read -r key value; do
    case "$key" in
        ENABLED) ENABLED=$value ;;
        ALLOWED_DOMAINS) ALLOWED_DOMAINS=$value ;;
        ALLOWED_IPS) ALLOWED_IPS=$value ;;
        ROUTER_IP) ROUTER_IP=$value ;;
    esac
done < "$work/applied.env"
[ "$ENABLED" = 1 ] || exit 0
validate_exceptions
: > "$work/hosts"
: > "$work/addresses"
resolved=0 failed=0
for domain in $ALLOWED_DOMAINS; do
    domain=$(printf '%s' "$domain" | tr 'A-Z' 'a-z')
    # Query only explicitly configured names through the router's normal DNS.
    # Never trust the server address printed before the answer section.
    if nslookup -type=A -timeout=2 -retry=1 "$domain" "$ROUTER_IP" > "$work/answer" 2>/dev/null; then
        awk '/^Name:/ {answer=1} answer && /^Address([[:space:]][0-9]+)?:/ {for(i=2;i<=NF;i++) print $i}' "$work/answer" | sort -u | head -n 64 > "$work/candidates"
    else
        : > "$work/candidates"
    fi
    found=0
    while IFS= read -r ip; do
        if internet_ipv4 "$ip"; then
            printf '%s %s\n' "$ip" "$domain" >> "$work/hosts"
            printf '%s\n' "$ip" >> "$work/addresses"
            found=1
        fi
    done < "$work/candidates"
    if [ "$found" = 1 ]; then resolved=$((resolved+1)); else failed=$((failed+1)); fi
done
sort -u "$work/addresses" > "$work/unique"
{
    for family in inet bridge; do
        table=swfence
        [ "$family" != inet ] || table=fw4
        printf 'flush set %s %s swfence_domain_v4\n' "$family" "$table"
        if [ -s "$work/unique" ]; then
            printf 'add element %s %s swfence_domain_v4 { ' "$family" "$table"
            awk '{printf "%s%s", (NR>1 ? ", " : ""), $0} END {print " }"}' "$work/unique"
        fi
    done
} > "$work/update.nft"
# DNS lookups happen outside the apply lock. Discard results if settings changed.
mkdir "$lock" 2>/dev/null || exit 0
locked=1
cmp -s "$work/applied.env" "$STATE/active.env" || exit 0
if ! nft -f "$work/update.nft" 2> "$work/error"; then
    tail -c 1000 "$work/error" > "$RUN/allowlist-error"
    exit 1
fi
# Open the validated IPs before advertising them to the console. Dynamic set
# entries expire after 180 seconds if this worker stops or cannot refresh them.
mv "$work/hosts" "$RUN/allowed-hosts"
if ! ubus call service signal '{"name":"swfence","instance":"dns","signal":1}' > /dev/null 2> "$work/error"; then
    echo 'Unable to reload the isolated DNS exception records.' > "$RUN/allowlist-error"
    exit 1
fi
printf '%s %s %s\n' "$(date +%s)" "$resolved" "$failed" > "$RUN/allowlist-state.tmp"
mv "$RUN/allowlist-state.tmp" "$RUN/allowlist-state"
cp "$work/applied.env" "$RUN/allowlist.env"
rm -f "$RUN/allowlist-error"
