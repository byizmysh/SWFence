#!/bin/sh
set -eu
. "${SWFENCE_ROOT:-}/usr/lib/swfence/common.sh"
root_required
mkdir -p "$RUN" "$STATE" "$R/var/lock" "$R/tmp/.uci"
lock=$R/var/lock/swfence-apply
mkdir "$lock" 2>/dev/null || { echo 'Another apply is running.' >&2; exit 1; }
work=$(mktemp -d "$R/tmp/swfence-apply.XXXXXX")
changed=0
committed=0
paths='etc/nftables.d/90-swfence.nft
usr/share/nftables.d/ruleset-post/90-swfence.nft
etc/swfence/runtime/dnsmasq.conf
etc/swfence/runtime/httpd.conf
etc/swfence/runtime/web/index.cgi
var/run/swfence/allowed-hosts
etc/swfence/active.env
etc/swfence/applied.uci
etc/swfence/previous.uci'
cleanup() {
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$changed" = 1 ] && [ "$committed" = 0 ]; then
        printf '%s\n' "$paths" | while IFS= read -r path; do
            rm -f "$R/$path"
            if [ -f "$work/backup/$path" ]; then cp -p "$work/backup/$path" "$R/$path"; fi
        done
        if ! fw4 reload >> "$work/error" 2>&1; then
            echo 'Restoring the previous firewall failed; inspect the router immediately.' >> "$work/error"
        fi
        if [ ! -f "$R/usr/share/nftables.d/ruleset-post/90-swfence.nft" ]; then
            nft delete table bridge swfence 2>/dev/null || true
        fi
    fi
    if [ "$result" != 0 ]; then
        tail -c 4096 "$work/error" > "$RUN/last-error" 2>/dev/null || echo 'Apply failed.' > "$RUN/last-error"
        cat "$RUN/last-error" >&2
    fi
    rm -rf "$work"
    rmdir "$lock"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
: > "$work/error"
read_config 2> "$work/error"
if [ "${SWFENCE_REMOVE:-0}" = 1 ]; then ENABLED=0; fi
write_env > "$work/active.env"
if [ "$ENABLED" = 1 ]; then
    for cmd in fw4 nft dnsmasq uhttpd; do
        command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" > "$work/error"; exit 1; }
    done
    [ "$(uc -q get 'firewall.@defaults[0].auto_includes' || true)" != 0 ] || { echo 'Enable fw4 auto_includes.' > "$work/error"; exit 1; }
    [ ! -f "$R/etc/nftables.d/92-ns2-local-only.nft" ] || { echo 'Legacy ns2 guard detected. Remove/migrate it before enabling SWFence.' > "$work/error"; exit 1; }
    render_config "$work" > /dev/null 2> "$work/error"
    dnsmasq --test --conf-file="$work/generated/dnsmasq.conf" >> "$work/error" 2>&1
fi
printf '%s\n' "$paths" | while IFS= read -r path; do
    mkdir -p "$work/backup/$(dirname "$path")" "$R/$(dirname "$path")"
    [ ! -f "$R/$path" ] || cp -p "$R/$path" "$work/backup/$path"
done
changed=1
if [ "$ENABLED" = 1 ]; then
    cp "$work/generated/inet.nft" "$R/etc/nftables.d/90-swfence.nft"
    cp "$work/generated/bridge.nft" "$R/usr/share/nftables.d/ruleset-post/90-swfence.nft"
    cp "$work/generated/dnsmasq.conf" "$STATE/runtime/dnsmasq.conf"
    cp "$work/generated/httpd.conf" "$STATE/runtime/httpd.conf"
    cp "$work/generated/index.cgi" "$STATE/runtime/web/index.cgi"
    chmod 755 "$STATE/runtime/web/index.cgi"
    : > "$RUN/allowed-hosts"
else
    rm -f "$R/etc/nftables.d/90-swfence.nft" "$R/usr/share/nftables.d/ruleset-post/90-swfence.nft"
fi
fw4 check >> "$work/error" 2>&1
fw4 reload >> "$work/error" 2>&1
if [ "$ENABLED" = 0 ] && nft list table bridge swfence >/dev/null 2>&1; then
    nft delete table bridge swfence >> "$work/error" 2>&1
fi
if [ -f "$STATE/applied.uci" ] && ! cmp -s "$work/active.env" "$STATE/active.env"; then
    cp "$STATE/applied.uci" "$STATE/previous.uci"
fi
cp "$work/active.env" "$STATE/active.env"
uc export swfence > "$STATE/applied.uci"
chmod 600 "$STATE/active.env" "$STATE/applied.uci"
[ ! -f "$STATE/previous.uci" ] || chmod 600 "$STATE/previous.uci"
rm -f "$RUN/last-error"
rm -f "$RUN/allowlist-state" "$RUN/allowlist.env" "$RUN/allowlist-error"
committed=1
