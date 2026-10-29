#!/bin/sh
set -eu
set -f
. "${SWFENCE_ROOT:-}/usr/lib/swfence/common.sh"
. "$LIB/statistics.sh"
json_lib
valid=1
read_config || { valid=0; ENABLED=0; }
inet=$(nft list chain inet fw4 swfence_early 2>/dev/null || true)
bridge=$(nft list chain bridge swfence early_guard 2>/dev/null || true)
active=0
[ -z "$inet" ] || [ -z "$bridge" ] || active=1
matches=0
if [ -f "$STATE/active.env" ] && write_env | cmp -s - "$STATE/active.env"; then matches=1; fi
inet_drops=$(count_drops inet fw4 swfence_policy)
bridge_drops=$(count_drops bridge swfence console)
sample_statistics "$bridge_drops" "$inet_drops"
read_statistics
dns=0
http=0
service=$(ubus call service list '{"name":"swfence"}' 2>/dev/null || true)
[ "$(printf '%s\n' "$service" | jsonfilter -e '@.swfence.instances.dns.running' 2>/dev/null || true)" != true ] || dns=1
[ "$(printf '%s\n' "$service" | jsonfilter -e '@.swfence.instances.http.running' 2>/dev/null || true)" != true ] || http=1
domain_state=not_configured
domain_updated=0 domain_resolved=0 domain_failed=0
if [ -n "$ALLOWED_DOMAINS" ]; then
    domain_state=pending
    if [ -f "$RUN/allowlist-state" ] && cmp -s "$STATE/active.env" "$RUN/allowlist.env"; then
        read -r domain_updated domain_resolved domain_failed < "$RUN/allowlist-state" || true
        if printf '%s\n' "$domain_updated $domain_resolved $domain_failed" | grep -Eq '^[0-9]+ [0-9]+ [0-9]+$'; then
            domain_state=updated
            if [ "$(( $(date +%s) - domain_updated ))" -ge 180 ]; then domain_state=expired; fi
        else
            domain_updated=0 domain_resolved=0 domain_failed=0
        fi
    fi
    [ ! -s "$RUN/allowlist-error" ] || domain_state=error
fi
project_url=
repository=$(cat "$STATE/repository" 2>/dev/null || true)
[ -n "$repository" ] || repository=$(cat "$R/usr/share/swfence/repository" 2>/dev/null || true)
if [ "${#repository}" -le 200 ] && printf '%s\n' "$repository" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
    project_url=https://github.com/$repository
fi
json_init
json_add_string version '0.3.0'
json_add_string project_url "$project_url"
json_add_boolean configured_enabled "$ENABLED"
json_add_boolean configuration_valid "$valid"
json_add_boolean guard_present "$active"
json_add_boolean config_matches "$matches"
json_add_boolean dns_running "$dns"
json_add_boolean http_running "$http"
json_add_boolean rollback_available "$(as_bool test -f "$STATE/previous.uci")"
json_add_string last_error "$(cat "$RUN/last-error" 2>/dev/null || true)"
json_add_object domain_status
json_add_string state "$domain_state"
json_add_string updated_at "$domain_updated"
json_add_string resolved "$domain_resolved"
json_add_string unresolved "$domain_failed"
json_add_string error "$(tail -c 1000 "$RUN/allowlist-error" 2>/dev/null || true)"
json_close_object
json_add_object counters
json_add_string inet_dropped "$inet_drops"
json_add_string bridge_dropped "$bridge_drops"
json_close_object
json_add_object daily_counters
json_add_boolean available "$STAT_AVAILABLE"
json_add_string day "$STAT_DAY"
json_add_string timezone "$STAT_ZONE"
json_add_string collected_since "$STAT_SINCE"
json_add_string collected_since_local "$STAT_SINCE_LOCAL"
json_add_string updated_at "$STAT_UPDATED"
json_add_string bridge_dropped "$STAT_BRIDGE"
json_add_string inet_dropped "$STAT_INET"
json_close_object
json_add_object config
json_add_string enabled "$ENABLED"
json_add_string router_ip "$ROUTER_IP"
json_add_string lan_subnet "$LAN_SUBNET"
json_add_string local_host "$LOCAL_HOST"
json_add_string local_port "$LOCAL_PORT"
json_add_array macs
for mac in $MACS; do json_add_string '' "$mac"; done
json_close_array
json_add_array allowed_ips
for ip in $ALLOWED_IPS; do json_add_string '' "$ip"; done
json_close_array
json_add_array allowed_domains
for domain in $ALLOWED_DOMAINS; do json_add_string '' "$domain"; done
json_close_array
json_close_object
json_dump
