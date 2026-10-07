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

echo "==> [1/3] Copying overlay files (DTS + vendored packages)"
mkdir -p "$TREE/files"
for entry in "$REPO_DIR/files"/*; do
	case "$(basename "$entry")" in
		usr|www) cp -a "$entry" "$TREE/files/" ;;
		*)       cp -a "$entry" "$TREE/" ;;
	esac
done
chmod 0755 "$TREE/package/quickstart/files/"*.init \
           "$TREE/package/quickstart/files/"*.hotplug \
           "$TREE/package/quickstart/files/"*.uci-default \
           "$TREE/package/quickstart/files/dhcpvalid.sh" \
           "$TREE/package/luci-app-quickstart/root/etc/uci-defaults/50_luci-quickstart" \
           "$TREE/package/luci-app-quickstart/root/usr/libexec/quickstart/auto_setup.sh" 2>/dev/null || true

chmod 0755 "$TREE/files/usr/bin/cpuinfo" \
           "$TREE/files/usr/bin/tempinfo" \
           "$TREE/files/usr/bin/cpuusage" 2>/dev/null || true

echo "==> [2/3] Patching existing tree files"
sh "$SCRIPT_DIR/patch_tree.sh" "$TREE" "$REPO_DIR/blocks"

echo "==> [3/3] Verifying"
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
check "vendored luci-app-dockerman"  test -f "$TREE/package/luci-app-dockerman/Makefile"
check "vendored luci-lib-docker"     test -f "$TREE/package/luci-lib-docker/Makefile"
check "overview cpuinfo script"     test -f "$TREE/files/usr/bin/cpuinfo"
check "overview tempinfo script"    test -f "$TREE/files/usr/bin/tempinfo"
check "overview cpuusage script"    test -f "$TREE/files/usr/bin/cpuusage"
check "overview 10_system.js"       grep -q 'getCPUUsage' "$TREE/files/www/luci-static/resources/view/status/include/10_system.js"
check "vendored qca-nss-drv"         test -f "$TREE/package/qca-nss-drv/Makefile"
check "vendored qca-nss-ecm"         test -f "$TREE/package/qca-nss-ecm/Makefile"
check "vendored qca-nss-crypto"      test -f "$TREE/package/qca-nss-crypto/Makefile"
check "vendored nss-firmware"        test -f "$TREE/package/nss-firmware/Makefile"
check "vendored nss-eip-firmware"    test -f "$TREE/package/nss-eip-firmware/Makefile"
check "NSS kernel patches copied"    test -f "$TREE/target/linux/qualcommax/patches-6.12/0600-1-qca-nss-ecm-support-CORE.patch" \
                              -a -f "$TREE/target/linux/qualcommax/patches-6.12/0602-1-qca-nss-drv-add-qdisc-support.patch" \
                              -a -f "$TREE/target/linux/qualcommax/patches-6.12/0606-1-qca-nss-ecm-bridge-Fixes-for-Bridge-VLAN-Filtering.patch" \
                              -a -f "$TREE/target/linux/qualcommax/patches-6.12/0981-1-qca-skb_recycler-support.patch"
check "NSS kernel config fragment"   grep -q 'NN6000 nss-kconfig' "$TREE/target/linux/qualcommax/config-6.12"
check "skb recycler header"          test -f "$TREE/target/linux/qualcommax/files/net/core/skbuff_recycle.h"
check "skb recycler source"          test -f "$TREE/target/linux/qualcommax/files/net/core/skbuff_recycle.c"
check "skb debug header"             test -f "$TREE/target/linux/qualcommax/files/net/core/skbuff_debug.h"
check "nf_conntrack_dscpremark_ext header" test -f "$TREE/target/linux/qualcommax/files/include/net/netfilter/nf_conntrack_dscpremark_ext.h"
check "nf_conntrack_dscpremark_ext source" test -f "$TREE/target/linux/qualcommax/files/net/netfilter/nf_conntrack_dscpremark_ext.c"
CR=$(printf '\r')
if grep -rIl "$CR" "$TREE/package/quickstart" "$TREE/package/luci-app-quickstart" \
              "$TREE/package/qca-nss-drv" "$TREE/package/qca-nss-ecm" \
              "$TREE/package/qca-nss-crypto" "$TREE/package/nss-firmware" \
              "$TREE/package/nss-eip-firmware" \
              "$TREE/package/luci-app-dockerman" "$TREE/package/luci-lib-docker" \
              "$TREE/target/linux/qualcommax/files/net/core" \
              "$TREE/target/linux/qualcommax/files/net/netfilter" \
              "$TREE/target/linux/qualcommax/files/include/net/netfilter" >/dev/null 2>&1; then
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
