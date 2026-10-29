#!/bin/sh
set -eu
. "${SWFENCE_ROOT:-}/usr/lib/swfence/common.sh"
json_lib
work=$(mktemp -d "$R/tmp/swfence-diag.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
json_init
json_add_string scope 'Router-local checks only; not an end-to-end console isolation test.'
json_add_array checks
check() {
    json_add_object ''
    json_add_string name "$1"
    json_add_string result "$2"
    json_add_string detail "$3"
    json_close_object
}
if read_config && [ "$ENABLED" = 1 ]; then
    if render_config "$work" > "$work/render.log" 2>&1; then
        check configuration pass 'MACs and selected destinations are valid.'
    else
        check configuration fail "$(tail -c 1000 "$work/render.log")"
    fi
else
    check configuration skipped 'Protection is disabled or configuration is invalid.'
fi
if fw4 check > "$work/fw4.log" 2>&1; then
    check firewall_syntax pass 'firewall4 accepts the current ruleset.'
else
    check firewall_syntax fail "$(tail -c 1000 "$work/fw4.log")"
fi
if nft list chain inet fw4 swfence_early >/dev/null 2>&1 && nft list chain bridge swfence early_guard >/dev/null 2>&1; then
    check firewall_hooks pass 'Both inet and bridge guard chains are loaded.'
else
    check firewall_hooks fail 'One or both guard chains are absent.'
fi
if [ -f "$STATE/active.env" ] && write_env | cmp -s - "$STATE/active.env"; then
    check applied_configuration pass 'Saved settings match the last successful apply.'
else
    check applied_configuration fail 'Saved settings have not been successfully applied.'
fi
if [ "$ENABLED" = 1 ] && [ -f "$STATE/runtime/dnsmasq.conf" ] && dnsmasq --test --conf-file="$STATE/runtime/dnsmasq.conf" > "$work/dns.log" 2>&1; then
    check dns_configuration pass 'The isolated resolver configuration parses.'
else
    check dns_configuration skipped 'No valid active resolver configuration.'
fi
# Use only the last validated/applied router IP as a diagnostic target.
router=$(sed -n 's/^ROUTER_IP=//p' "$STATE/active.env" 2>/dev/null || true)
if [ "$ENABLED" = 1 ] && [ -n "$router" ] && command -v nslookup >/dev/null; then
    if nslookup -port=5357 -timeout=1 -retry=1 -type=A ctest.cdn.nintendo.net "$router" > "$work/dns.log" 2>&1 && \
       awk -v ip="$router" '/^Name:/ {answer=1} answer && $NF==ip {found=1} END {exit !found}' "$work/dns.log"; then
        check dns_local_answer pass 'The local connection-check name resolves to the router.'
    else
        check dns_local_answer fail 'The isolated resolver did not return the expected router IPv4.'
    fi
    for kind in A AAAA; do
        nslookup -port=5357 -timeout=1 -retry=1 -type="$kind" swfence-unlisted.invalid "$router" > "$work/nxdomain.log" 2>&1 || true
        if grep -q NXDOMAIN "$work/nxdomain.log"; then
            check "dns_external_$kind" pass 'The isolated resolver returns NXDOMAIN.'
        else
            check "dns_external_$kind" fail 'Expected NXDOMAIN was not observed.'
        fi
    done
else
    check dns_local_answer skipped 'Enable protection; nslookup with custom-port support is required.'
fi
if [ "$ENABLED" = 1 ] && [ -n "$router" ] && command -v uclient-fetch >/dev/null; then
    if uclient-fetch -q -Y off -T 3 --header='Host: ctest.cdn.nintendo.net' -O "$work/http" "http://$router:18087/" 2>/dev/null && [ "$(cat "$work/http")" = ok ]; then
        check http_connection_check pass 'The local HTTP endpoint returns the expected ok body.'
    else
        check http_connection_check fail 'The local HTTP endpoint did not return ok.'
    fi
else
    check http_connection_check skipped 'Enable protection; uclient-fetch is required.'
fi
check console_external_isolation manual 'Verify from the console that only configured internet exceptions are reachable; observe counters or capture WAN traffic.'
json_close_array
json_dump
