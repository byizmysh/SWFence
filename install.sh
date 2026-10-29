#!/bin/sh
# Run on OpenWrt after connecting over SSH. A real repository is required.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}
export PATH
usage() { echo 'Usage: sh install.sh OWNER/SWFence v0.3.0'; }
case "${1:-}" in -h|--help|'') usage; exit 0 ;; esac
[ "$#" = 2 ] || { usage >&2; exit 1; }
repo=$1
tag=$2
printf '%s\n' "$repo" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || { echo 'Invalid GitHub repository.' >&2; exit 1; }
printf '%s\n' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || { echo 'Use a version tag such as v0.3.0.' >&2; exit 1; }
[ "$(id -u)" = 0 ] && [ -f /etc/openwrt_release ] || { echo 'Run this on OpenWrt as root.' >&2; exit 1; }
command -v fw4 >/dev/null || { echo 'OpenWrt with firewall4 is required.' >&2; exit 1; }
if command -v opkg >/dev/null; then flavor=24.10; ext=ipk
elif command -v apk >/dev/null; then flavor=25.12; ext=apk
else echo 'Unsupported package manager.' >&2; exit 1
fi
# Require the release family the package was built for; never assume manager alone.
release=$(. /etc/openwrt_release; printf '%s' "$DISTRIB_RELEASE")
case "$release" in "$flavor".*) ;; *) echo "This installer has packages for OpenWrt 24.10.x and 25.12.x; detected $release." >&2; exit 1 ;; esac
for cmd in uclient-fetch sha256sum; do command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" >&2; exit 1; }; done
work=$(mktemp -d /tmp/swfence-install.XXXXXX)
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
base=https://github.com/$repo/releases/download/$tag
cd "$work"
uclient-fetch -q -O SHA256SUMS "$base/SHA256SUMS"
for pkg in swfence luci-app-swfence; do
    name=$pkg-$flavor.$ext
    uclient-fetch -q -O "$name" "$base/$name"
    # Verify only the exact selected asset, not arbitrary filenames from a manifest.
    awk -v file="$name" '$2==file && length($1)==64 && $1 !~ /[^0-9a-fA-F]/ {print $1 "  " file; n++} END {if(n!=1) exit 1}' SHA256SUMS > "$name.sha256"
    sha256sum -c "$name.sha256"
done
if [ "$ext" = ipk ]; then
    opkg update
    opkg install ./swfence-24.10.ipk ./luci-app-swfence-24.10.ipk
else
    apk update
    apk add --allow-untrusted ./swfence-25.12.apk ./luci-app-swfence-25.12.apk
fi
mkdir -p /etc/swfence
printf '%s\n' "$repo" > /etc/swfence/repository
swfence setup
