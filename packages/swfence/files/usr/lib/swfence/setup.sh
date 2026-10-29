#!/bin/sh
set -eu
. "${SWFENCE_ROOT:-}/usr/lib/swfence/common.sh"
root_required
json_lib
state=$(ubus call network.interface.lan status 2>/dev/null || true)
router=$(printf '%s\n' "$state" | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null || true)
prefix=$(printf '%s\n' "$state" | jsonfilter -e '@["ipv4-address"][0].mask' 2>/dev/null || true)
subnet=
if [ -n "$router" ] && [ -n "$prefix" ]; then
    calc=$(ipcalc.sh "$router/$prefix" 2>/dev/null || true)
    network=$(printf '%s\n' "$calc" | sed -n 's/^NETWORK=//p')
    bits=$(printf '%s\n' "$calc" | sed -n 's/^PREFIX=//p')
    [ -z "$network$bits" ] || subnet=$network/$bits
fi
echo 'SWFence — Keep it local.'
echo 'External console traffic is blocked except for configured internet exceptions. Local IPv4 access remains available.'
echo 'Wi-Fi MAC: System Settings > Internet > System MAC Address.'
echo 'Ethernet uses the dock/adapter MAC. Keep WAN disconnected while identifying an unprotected device.'
if [ -f "$R/tmp/dhcp.leases" ]; then awk '{print "Lease: " $2 " " $3 " " $4}' "$R/tmp/dhcp.leases"; fi
printf 'Wi-Fi MAC (empty if unused): '; IFS= read -r wifi
printf 'Ethernet MAC (empty if unused): '; IFS= read -r wired
printf 'Router LAN IPv4 [%s]: ' "$router"; IFS= read -r answer; router=${answer:-$router}
printf 'Allowed home IPv4 subnet [%s]: ' "$subnet"; IFS= read -r answer; subnet=${answer:-$subnet}
[ -n "$subnet" ] || { echo 'A local IPv4 subnet in CIDR notation is required.' >&2; exit 1; }
macs=$(printf '%s %s\n' "$wifi" "$wired" | tr 'A-Z' 'a-z' | tr '-' ':' | awk '{$1=$1; print}')
json_init
json_add_string enabled 1
json_add_string macs "$macs"
json_add_string router_ip "$router"
json_add_string lan_subnet "$subnet"
json_add_string local_host ''
json_add_string local_port ''
result=$(json_dump | "$R/usr/sbin/swfence" configure)
echo "$result"
json_load "$result"
json_get_var ok ok
[ "$ok" = 1 ] || [ "$ok" = true ] || exit 1
echo "Set BOTH console DNS addresses to $router, disable console proxy settings, and reconnect."
echo 'LuCI: Services > SWFence. Run local diagnostics, then verify console traffic.'
