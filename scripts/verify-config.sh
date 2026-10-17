#!/bin/sh

set -eu

if [ $# -ne 1 ]; then
	echo "usage: $0 <istoreos-dir>" >&2
	exit 1
fi

TREE=$1
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$TREE"

echo "::group::Selected device symbols"
grep -E '^CONFIG_TARGET_(BOARD|SUBTARGET|PROFILE)|DEVICE_link_nn6000' .config || true
echo "::endgroup::"
echo "::group::ccache config"
grep -E '^CONFIG_(DEVEL|CCACHE)' .config || true
echo "::endgroup::"

FAIL=0

if grep -q '^CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_link_nn6000-v2=y' .config; then
	echo "::notice::device selected: link_nn6000-v2"
else
	echo "::error::device link_nn6000-v2 was not selected by defconfig"
	grep -o 'TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_[a-z0-9_.-]*' tmp/.config-target.in 2>/dev/null | sort -u || true
	FAIL=1
fi
if grep -q '^CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_link_nn6000-v2-nowifi=y' .config; then
	echo "::notice::device selected: link_nn6000-v2-nowifi"
else
	echo "::error::device link_nn6000-v2-nowifi was not selected by defconfig"
	FAIL=1
fi
if grep -q '^CONFIG_TARGET_MULTI_PROFILE=y' .config; then
	echo "::notice::multi-profile mode enabled"
else
	echo "::error::TARGET_MULTI_PROFILE is not set; cannot build multiple devices"
	FAIL=1
fi
grep -q '^CONFIG_TARGET_ROOTFS_INITRAMFS=y' .config \
	|| { echo "::error::initramfs image is disabled; TFTP first-install image will be missing"; FAIL=1; }

HARD="
$(cat "$REPO_DIR/config/packages.list")
luci-app-store
luci-i18n-quickstart-zh-cn
taskd
luci-lib-taskd
luci-lib-xterm
mount-utils
block-mount
lsblk
parted
fdisk
luci
luci-app-firewall
luci-theme-argon
docker
ttyd
luci-app-ttyd
kmod-tun
iperf3
wireguard-tools
irqbalance
luci-app-sqm
kmod-ipt-nat6
"
MISSING=""
for p in $HARD; do
	if grep -q "^CONFIG_PACKAGE_${p}=y" .config; then
		echo "  ok      $p"
	else
		echo "  MISSING $p"
		MISSING="$MISSING $p"
	fi
done
if [ -n "$MISSING" ]; then
	echo "::error::Required packages were dropped by defconfig:$MISSING"
	FAIL=1
fi

exit $FAIL
