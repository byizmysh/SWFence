#!/bin/sh
# SWFENCE_ROOT is an isolated filesystem prefix for development/tests only.
R=${SWFENCE_ROOT:-}
PATH=/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}
export PATH
LIB=$R/usr/lib/swfence
STATE=$R/etc/swfence
RUN=$R/var/run/swfence
uc() { uci -c "$R/etc/config" -t "$R/tmp/.uci" "$@"; }
get() { uc -q get "swfence.main.$1" 2>/dev/null || true; }
read_config() {
    ENABLED=$(get enabled)
    MACS=$(get mac)
    ROUTER_IP=$(get router_ip)
    LAN_SUBNET=$(get lan_subnet)
    LOCAL_HOST=$(get local_host)
    LOCAL_PORT=$(get local_port)
    ALLOWED_IPS=$(get allowed_ip)
    ALLOWED_DOMAINS=$(get allowed_domain)
    case "$ENABLED" in 0|1) ;; *) echo 'enabled must be 0 or 1' >&2; return 1 ;; esac
}
write_env() {
    printf 'ENABLED=%s\nMACS=%s\nROUTER_IP=%s\nLAN_SUBNET=%s\nLOCAL_HOST=%s\nLOCAL_PORT=%s\nALLOWED_IPS=%s\nALLOWED_DOMAINS=%s\n' \
        "$ENABLED" "$MACS" "$ROUTER_IP" "$LAN_SUBNET" "$LOCAL_HOST" "$LOCAL_PORT" "$ALLOWED_IPS" "$ALLOWED_DOMAINS"
}
render_config() {
    write_env | sed '/^ENABLED=/d' > "$1/config.conf"
    SWFENCE_FOR_INSTALL=1 sh "$LIB/render.sh" "$1/config.conf" "$1/generated"
}
json_lib() {
    # OpenWrt jshn intentionally reads optional unset shell variables.
    set +u
    . "$R/usr/share/libubox/jshn.sh"
}
as_bool() { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
root_required() {
    [ -n "$R" ] || [ "$(id -u)" = 0 ] || { echo 'Run as root on OpenWrt.' >&2; return 1; }
}
