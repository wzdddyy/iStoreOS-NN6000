#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

if [ $# -ne 1 ]; then
	echo "usage: $0 <istoreos-source-tree-root>" >&2
	exit 1
fi

TREE="$1"

if [ ! -f "$TREE/target/linux/qualcommax/Makefile" ]; then
	echo "ERROR: $TREE is not an OpenWrt/iStoreOS source tree (qualcommax target missing)" >&2
	exit 1
fi

if ! grep -q '^KERNEL_PATCHVER:=6\.12$' "$TREE/target/linux/qualcommax/Makefile"; then
	echo "ERROR: this port only targets iStoreOS 25.12 (qualcommax kernel 6.12)." >&2
	echo "       The DTS uses the QSDK NSS dataplane bindings and is not compatible" >&2
	echo "       with the newer PPE/DSA stack." >&2
	exit 1
fi

echo "==> [1/4] Copying overlay files (DTS + vendored packages)"
cp -a "$REPO_DIR/files/." "$TREE/"
chmod 0755 "$TREE/package/quickstart/files/"*.init \
           "$TREE/package/quickstart/files/"*.hotplug \
           "$TREE/package/quickstart/files/"*.uci-default \
           "$TREE/package/quickstart/files/dhcpvalid.sh" \
           "$TREE/package/luci-app-quickstart/root/etc/uci-defaults/50_luci-quickstart" \
           "$TREE/package/luci-app-quickstart/root/usr/libexec/quickstart/auto_setup.sh" 2>/dev/null || true

echo "==> [2/4] Appending dockerman feeds (lisaac originals)"
# lisaac's luci-app-dockerman registers a top-level "Docker" menu (admin/docker),
# unlike the luci-feed version which nests under admin/services. The luci feed
# copy is removed by CI before `feeds install` to avoid a duplicate definition.
# Feeds follow the upstream master branch; every build pulls the latest code.
FEEDS_FILE="$TREE/feeds.conf.default"
if ! grep -q 'lisaac/luci-app-dockerman' "$FEEDS_FILE"; then
	cat >> "$FEEDS_FILE" <<'EOF'
# NN6000 port: lisaac original dockerman (top-level menu) + luci-lib-docker
src-git dockerman https://github.com/lisaac/luci-app-dockerman.git;master
src-git lucidocker https://github.com/lisaac/luci-lib-docker.git;master
EOF
fi

echo "==> [3/4] Patching existing tree files"
sh "$SCRIPT_DIR/patch_tree.sh" "$TREE" "$REPO_DIR/blocks"

echo "==> [4/4] Verifying"
check() {
	desc="$1"; shift
	if "$@" >/dev/null 2>&1; then
		echo "  ok    $desc"
	else
		echo "  FAIL  $desc" >&2
		exit 1
	fi
}
check "DTS v1 present"               test -f "$TREE/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-nn6000-v1.dts"
check "DTS v2 present"               test -f "$TREE/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-nn6000-v2.dts"
check "DTS shared dtsi present"      test -f "$TREE/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-link.dtsi"
check "image definition v1"          grep -q 'Device/link_nn6000-v1' "$TREE/target/linux/qualcommax/image/ipq60xx.mk"
check "image definition v2"          grep -q 'TARGET_DEVICES += link_nn6000-v2' "$TREE/target/linux/qualcommax/image/ipq60xx.mk"
check "02_network v1 case"           grep -q 'link,nn6000-v1' "$TREE/target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network"
check "02_network v2 case"           grep -q 'link,nn6000-v2' "$TREE/target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network"
check "caldata extraction"           grep -q 'caldata_extract_mmc "0:ART" 0x1000 0x10000' "$TREE/target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata"
check "wifi MAC patching"            grep -q 'mmc_get_mac_binary 0:ART 18' "$TREE/target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata"
check "eMMC A/B sysupgrade branch"   grep -q 'link,nn6000-v1' "$TREE/target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh"
check "ipq-wifi board registered"    grep -q 'ipq-wifi-package,link_nn6000' "$TREE/package/firmware/ipq-wifi/Makefile"
check "uboot-envtools mmc entry"     grep -q 'ubootenv_add_mmc "0:APPSBLENV"' "$TREE/package/boot/uboot-tools/uboot-envtools/files/qualcommax_ipq60xx"
check "vendored quickstart package"  test -f "$TREE/package/quickstart/Makefile"
check "vendored luci-app-quickstart" test -f "$TREE/package/luci-app-quickstart/Makefile"
check "loop overlay boot script"    grep -q '_get_overlay_partition_loop' "$TREE/package/base-files/files/lib/functions/istoreos-boot.sh"
check "dockerman feed pinned"       grep -q 'lisaac/luci-app-dockerman' "$TREE/feeds.conf.default"
check "luci-lib-docker feed pinned" grep -q 'lisaac/luci-lib-docker' "$TREE/feeds.conf.default"
CR=$(printf '\r')
if grep -rIl "$CR" "$TREE/package/quickstart" "$TREE/package/luci-app-quickstart" >/dev/null 2>&1; then
	echo "  FAIL  vendored packages contain CRLF line endings" >&2
	exit 1
else
	echo "  ok    vendored packages use LF line endings"
fi

echo
echo "NN6000 port applied successfully."
echo "Next steps:"
echo "  cd $TREE"
echo "  ./scripts/feeds update -a && ./scripts/feeds install -a"
echo "  cat /path/to/nn6000.seed > .config && make defconfig"
echo "  make -j\$(nproc)"
