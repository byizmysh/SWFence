#!/bin/sh
# Render locally without root, network access, or changes to the router.
set -eu
set -f
base=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ "$#" = 2 ] || { echo "Usage: sh render.sh CONFIG OUTPUT_DIR" >&2; exit 1; }
config=$1
out=$2
MACS= ROUTER_IP= LOCAL_HOST= LOCAL_PORT= LAN_SUBNET= ALLOWED_IPS= ALLOWED_DOMAINS=
. "$base/validation.sh"
fail() { echo "$*" >&2; exit 1; }
while IFS='=' read -r key value || [ -n "$key" ]; do
    case "$key" in ''|'#'*) continue ;; esac
    case "$key" in
        MACS) MACS=$value ;;
        ROUTER_IP) ROUTER_IP=$value ;;
        LOCAL_HOST) LOCAL_HOST=$value ;;
        LOCAL_PORT) LOCAL_PORT=$value ;;
        LAN_SUBNET) LAN_SUBNET=$value ;;
        ALLOWED_IPS) ALLOWED_IPS=$value ;;
        ALLOWED_DOMAINS) ALLOWED_DOMAINS=$value ;;
        *) fail "Unknown configuration key: $key" ;;
    esac
done < "$config"
validate_exceptions || exit 1
allowed_set=$(printf '%s\n' "$ALLOWED_IPS" | awk '{for(i=1;i<=NF;i++) printf "%s%s", (i>1 ? ", " : ""), $i}')
ipv4() {
    printf '%s\n' "$1" | awk -F. 'NF != 4 {exit 1} {for(i=1;i<=4;i++) if ($i !~ /^(0|[1-9][0-9]*)$/ || $i>255) exit 1}'
}
private_ipv4() {
    ipv4 "$1" && printf '%s\n' "$1" | awk -F. '{exit !(($1==10) || ($1==172 && $2>=16 && $2<=31) || ($1==192 && $2==168))}'
}
private_ipv4 "$ROUTER_IP" || fail 'Use a private RFC1918 router IPv4 address'
if [ -n "$LOCAL_HOST$LOCAL_PORT" ]; then
    private_ipv4 "$LOCAL_HOST" || fail 'Use a private RFC1918 local host address'
    [ "$ROUTER_IP" != "$LOCAL_HOST" ] || fail 'LOCAL_HOST must not be the router'
    case "$LOCAL_PORT" in ''|*[!0-9]*) fail 'Invalid local port' ;; esac
    [ "${#LOCAL_PORT}" -le 5 ] && [ "$LOCAL_PORT" -ge 1 ] && [ "$LOCAL_PORT" -le 65535 ] || fail 'Invalid local port'
fi
printf '%s\n' "$MACS" | awk 'NF==0 {exit 1} {for(i=1;i<=NF;i++) {n=split($i,a,":"); if(n!=6) exit 1; for(j=1;j<=n;j++) if(a[j] !~ /^[0-9a-fA-F][0-9a-fA-F]$/) exit 1; if(tolower(substr(a[1],2,1)) ~ /[13579bdf]/ || $i=="00:00:00:00:00:00") exit 1}}' || fail 'Enter at least one valid unicast MAC address'
# Generate an nft set, also for a single address; no executable config input.
mac_set=$(printf '%s\n' "$MACS" | awk '{printf "{ "; for(i=1;i<=NF;i++) printf "%s%s", (i>1 ? ", " : ""), tolower($i); printf " }"}')
if [ "${SWFENCE_FOR_INSTALL:-0}" = 1 ] && printf '%s\n' "$mac_set" | grep -Eiq '02:7e:93:4c:a8:61|02:b4:6f:21:d9:30'; then
    fail 'Example MAC detected. Run setup.sh or enter your actual console MACs in config.conf.'
fi
if [ -n "$LAN_SUBNET" ]; then
    net=${LAN_SUBNET%/*}
    mask=${LAN_SUBNET##*/}
    ipv4 "$net" || fail 'Invalid LAN subnet'
    case "$mask" in ''|*[!0-9]*) fail 'Invalid subnet mask' ;; esac
    [ "${#mask}" -le 2 ] && [ "$mask" -le 32 ] || fail 'Invalid subnet mask'
    # Only explicitly selected RFC1918 destinations may be opened broadly.
    printf '%s\n' "$net" | awk -F. -v m="$mask" '{exit !(($1==10 && m>=8) || ($1==172 && $2>=16 && $2<=31 && m>=12) || ($1==192 && $2==168 && m>=16))}' || fail 'LAN_SUBNET must be an RFC1918 subnet'
fi
mkdir -p "$out"
for file in inet.nft bridge.nft dnsmasq.conf index.cgi; do
    awk -v macs="$mac_set" -v router="$ROUTER_IP" -v host="$LOCAL_HOST" -v port="$LOCAL_PORT" -v subnet="$LAN_SUBNET" -v allowed="$allowed_set" '
        /@IP_EXCEPTIONS@/ {if(allowed!="") print "        ip daddr { " allowed " } counter return comment \"SWFence explicit IPv4 exception\""; next}
        /@LOCAL_HOST@/ && host=="" {next}
        /@LAN_RULES@/ {
            if(subnet!="") {
                print "        ip daddr " router " counter drop comment \"SWFence block router proxies\""
                print "        ip daddr " subnet " counter return comment \"SWFence trusted LAN\""
            }
            next
        }
        {
            gsub(/@MACS@/,macs); gsub(/@ROUTER_IP@/,router)
            gsub(/@LOCAL_HOST@/,host); gsub(/@LOCAL_PORT@/,port)
            print
        }
    ' "$base/templates/$file" > "$out/$file"
done
: > "$out/httpd.conf"
chmod 755 "$out/index.cgi"
echo "Generated: $out"
