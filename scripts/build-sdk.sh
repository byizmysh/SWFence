#!/bin/sh
set -eu
[ "$#" = 1 ] || { echo 'Usage: sh scripts/build-sdk.sh /path/to/openwrt-sdk' >&2; exit 1; }
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk=$(CDPATH= cd -- "$1" && pwd)
[ -f "$sdk/rules.mk" ] && [ -d "$sdk/staging_dir" ] || { echo 'Not an OpenWrt SDK.' >&2; exit 1; }
mkdir -p "$sdk/package/swfence-local"
cp -R "$base/packages/swfence" "$base/packages/luci-app-swfence" "$sdk/package/swfence-local/"
cd "$sdk"
# Use shallow official feeds when the SDK has no user-specific feed config.
if [ ! -f feeds.conf ]; then
    sed -e 's/^src-git-full base /src-git base /' \
        -e 's|https://git.openwrt.org/openwrt/openwrt.git|https://github.com/openwrt/openwrt.git|' \
        -e 's|https://git.openwrt.org/feed/packages.git|https://github.com/openwrt/packages.git|' \
        -e 's|https://git.openwrt.org/project/luci.git|https://github.com/openwrt/luci.git|' feeds.conf.default > feeds.conf
fi
./scripts/feeds update base packages luci
./scripts/feeds install -a
[ -f .config ] || make defconfig
cp .config .config.swfence-backup
# SDK defaults can select every kernel module. Keep the target/toolchain but
# build only the application packages and their dependencies in this SDK.
sed -E 's/^(CONFIG_PACKAGE_[^=]+)=.*/# \1 is not set/;/^CONFIG_ALL/d;/^# CONFIG_ALL/d' .config > .config.swfence
cat >> .config.swfence <<'EOF'
# CONFIG_ALL is not set
# CONFIG_ALL_NONSHARED is not set
# CONFIG_ALL_KMODS is not set
CONFIG_PACKAGE_swfence=m
CONFIG_PACKAGE_luci-app-swfence=m
EOF
mv .config.swfence .config
make defconfig
# Both packages contain only scripts/JS. Build their native package recipes
# directly: runtime dependencies are installed from the user's firmware feed,
# and do not need to be recompiled in this SDK.
make -C package/swfence-local/swfence TOPDIR="$sdk" compile V=s
make -C package/swfence-local/luci-app-swfence TOPDIR="$sdk" compile V=s
echo "Packages are in $sdk/bin/packages/"
