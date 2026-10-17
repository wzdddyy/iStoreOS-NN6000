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
		etc|usr|www) cp -a "$entry" "$TREE/files/" ;;
		*)            cp -a "$entry" "$TREE/" ;;
	esac
done
chmod 0755 "$TREE/package/luci/quickstart/files/"*.init \
           "$TREE/package/luci/quickstart/files/"*.hotplug \
           "$TREE/package/luci/quickstart/files/"*.uci-default \
           "$TREE/package/luci/quickstart/files/dhcpvalid.sh" \
           "$TREE/package/luci/luci-app-quickstart/root/etc/uci-defaults/50_luci-quickstart" \
           "$TREE/package/luci/luci-app-quickstart/root/usr/libexec/quickstart/auto_setup.sh" 2>/dev/null || true

chmod 0755 "$TREE/files/usr/bin/cpuinfo" \
           "$TREE/files/usr/bin/tempinfo" \
           "$TREE/files/usr/bin/cpuusage" \
           "$TREE/files/etc/hotplug.d/iface/"* \
           "$TREE/files/etc/uci-defaults/"* \
           "$TREE/package/luci/luci-app-mini-diskmanager/root/etc/uci-defaults/setup_prm.sh" \
           "$TREE/package/luci/luci-app-mini-diskmanager/root/usr/libexec/rpcd/minidiskmanager" \
           "$TREE/package/luci/luci-app-adguardhome/root/etc/init.d/AdGuardHome" \
           "$TREE/package/luci/luci-app-adguardhome/root/etc/uci-defaults/40_luci-AdGuardHome" \
           "$TREE/package/luci/luci-app-adguardhome/root/usr/share/AdGuardHome/"*.sh \
           "$TREE/package/luci/luci-app-tailscale-community/root/etc/init.d/tailscale-settings" \
           "$TREE/package/luci/luci-app-tailscale-community/root/etc/uci-defaults/99-tailscale-settings" \
           "$TREE/package/luci/luci-app-dockerman/root/etc/init.d/dockerman" \
           "$TREE/package/luci/luci-app-autoreboot/root/etc/init.d/autoreboot" 2>/dev/null || true

for _tgz in "$TREE/package/luci/smartdns"/smartdns-*.tar.gz \
            "$TREE/package/luci/tailscale"/tailscale-*.tar.gz; do
	[ -e "$_tgz" ] || continue
	mkdir -p "$TREE/dl"
	cp -f "$_tgz" "$TREE/dl/"
	echo "  staged $(basename "$_tgz") into dl/"
done

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

refute() {
	desc="$1"; shift
	if "$@" >/dev/null 2>&1; then
		echo "  FAIL  $desc" >&2
		exit 1
	else
		echo "  ok    $desc"
	fi
}
check "DTS v1 present"               test -f "$TREE/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-nn6000-v1.dts"
check "DTS v2 present"               test -f "$TREE/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-nn6000-v2.dts"
check "DTS shared dtsi present"      test -f "$TREE/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-link.dtsi"
check "DTS nss dtsi present"         test -f "$TREE/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-nss.dtsi"
check "image definition v1"          grep -q 'Device/link_nn6000-v1' "$TREE/target/linux/qualcommax/image/ipq60xx.mk"
check "image definition v2"          grep -q 'TARGET_DEVICES += link_nn6000-v2' "$TREE/target/linux/qualcommax/image/ipq60xx.mk"
check "image definition v2-nowifi"    grep -q 'TARGET_DEVICES += link_nn6000-v2-nowifi' "$TREE/target/linux/qualcommax/image/ipq60xx.mk"
check "wifi stack in v1/v2 DEVICE_PACKAGES" grep -q 'kmod-ath11k-ahb ath11k-firmware-ipq6018 wpad-basic-mbedtls' "$TREE/target/linux/qualcommax/image/ipq60xx.mk"
check "02_network v1 case"           grep -q 'link,nn6000-v1' "$TREE/target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network"
check "02_network v2 case"           grep -q 'link,nn6000-v2' "$TREE/target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network"
check "caldata extraction"           grep -q 'caldata_extract_mmc "0:ART" 0x1000 0x10000' "$TREE/target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata"
check "wifi MAC patching"            grep -q 'mmc_get_mac_binary 0:ART 18' "$TREE/target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata"
check "eMMC A/B sysupgrade branch"   grep -q 'link,nn6000-v1' "$TREE/target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh"
check "ipq-wifi board registered"    grep -q 'ipq-wifi-package,link_nn6000' "$TREE/package/firmware/ipq-wifi/Makefile"
check "uboot-envtools mmc entry"     grep -q 'ubootenv_add_mmc "0:APPSBLENV"' "$TREE/package/boot/uboot-tools/uboot-envtools/files/qualcommax_ipq60xx"
check "vendored quickstart package"  test -f "$TREE/package/luci/quickstart/Makefile"
check "vendored luci-app-quickstart" test -f "$TREE/package/luci/luci-app-quickstart/Makefile"
check "loop overlay boot script"    grep -q '_get_overlay_partition_loop' "$TREE/package/base-files/files/lib/functions/istoreos-boot.sh"
check "vendored luci-app-dockerman"  test -f "$TREE/package/luci/luci-app-dockerman/Makefile"
check "vendored luci-lib-docker"     test -f "$TREE/package/luci/luci-lib-docker/Makefile"
check "vendored luci-app-ttyd"       test -f "$TREE/package/luci/luci-app-ttyd/Makefile"
check "vendored luci-app-mini-diskmanager" test -f "$TREE/package/luci/luci-app-mini-diskmanager/Makefile"
check "vendored luci-app-hd-idle"    test -f "$TREE/package/luci/luci-app-hd-idle/Makefile"
check "vendored luci-app-samba4"     test -f "$TREE/package/luci/luci-app-samba4/Makefile"
check "overview cpuinfo script"     test -f "$TREE/files/usr/bin/cpuinfo"
check "overview tempinfo script"    test -f "$TREE/files/usr/bin/tempinfo"
check "overview cpuusage script"    test -f "$TREE/files/usr/bin/cpuusage"
check "overview 10_system.js"       grep -q 'getCPUUsage' "$TREE/files/www/luci-static/resources/view/status/include/10_system.js"
check "apk signing key (25.12)"     test -f "$TREE/files/etc/apk/keys/immortalwrt-25.12.pem"
check "apk mirror uci-default"      test -f "$TREE/files/etc/uci-defaults/99-apk-mirror"
check "argon theme uci-default"     test -f "$TREE/files/etc/uci-defaults/99-argon-theme"
check "vendored qca-nss-drv"         test -f "$TREE/package/nss/qca-nss-drv/Makefile"
check "vendored qca-nss-ecm"         test -f "$TREE/package/nss/qca-nss-ecm/Makefile"
check "vendored qca-nss-crypto"      test -f "$TREE/package/nss/qca-nss-crypto/Makefile"
check "vendored nss-firmware"        test -f "$TREE/package/nss/nss-firmware/Makefile"
check "vendored nss-eip-firmware"    test -f "$TREE/package/nss/nss-eip-firmware/Makefile"
check "NSS kernel patches copied"    test -f "$TREE/target/linux/qualcommax/patches-6.12/0600-1-qca-nss-ecm-support-CORE.patch" \
                              -a -f "$TREE/target/linux/qualcommax/patches-6.12/0600-2-qca-nss-ecm-support-PPPOE-offload.patch" \
                              -a -f "$TREE/target/linux/qualcommax/patches-6.12/0602-1-qca-nss-drv-add-qdisc-support.patch" \
                              -a -f "$TREE/target/linux/qualcommax/patches-6.12/0606-1-qca-nss-ecm-bridge-Fixes-for-Bridge-VLAN-Filtering.patch" \
                              -a -f "$TREE/target/linux/qualcommax/patches-6.12/0981-1-qca-skb_recycler-support.patch"
check "0600-2 lockless ppp symbols"  grep -q '__ppp_is_multilink' "$TREE/target/linux/qualcommax/patches-6.12/0600-2-qca-nss-ecm-support-PPPOE-offload.patch"
check "0600-2 lockless ppp channels" grep -q '__ppp_hold_channels' "$TREE/target/linux/qualcommax/patches-6.12/0600-2-qca-nss-ecm-support-PPPOE-offload.patch"
check "ECM PPTP gated by kmod-pptp"  grep -qF 'CONFIG_PACKAGE_kmod-pptp' "$TREE/package/nss/qca-nss-ecm/Makefile"
refute "ECM PPTP decoupled from pppoe"  grep -qF 'PACKAGE_kmod-pppoe:kmod-pptp' "$TREE/package/nss/qca-nss-ecm/Makefile"
refute "ECM L2TPv2 decoupled from pppoe" grep -qF 'PACKAGE_kmod-pppoe:kmod-pppol2tp' "$TREE/package/nss/qca-nss-ecm/Makefile"
check "NSS kernel config fragment"   grep -q 'NN6000 nss-kconfig' "$TREE/target/linux/qualcommax/config-6.12"
refute "ath11k-ahb remains in target defaults"  grep -q 'kmod-ath11k-ahb' "$TREE/target/linux/qualcommax/Makefile"
refute "wpad remains in target defaults"        grep -q 'wpad-basic-mbedtls' "$TREE/target/linux/qualcommax/Makefile"
refute "ath11k-firmware in subtarget defaults"  grep -q 'ath11k-firmware-ipq6018' "$TREE/target/linux/qualcommax/ipq60xx/target.mk"
check "qcom default nss-dp recovered" grep -q 'kmod-qca-nss-dp' "$TREE/target/linux/qualcommax/Makefile"
check "qcom default uboot-envtools recovered" grep -q 'uboot-envtools' "$TREE/target/linux/qualcommax/Makefile"
check "ipt-ipopt conntrack dep"      grep -q 'NN6000 ipt-ipopt-conntrack' "$TREE/package/kernel/linux/modules/netfilter.mk"
check "skb recycler header"          test -f "$TREE/target/linux/qualcommax/files/net/core/skbuff_recycle.h"
check "skb recycler source"          test -f "$TREE/target/linux/qualcommax/files/net/core/skbuff_recycle.c"
check "skb debug header"             test -f "$TREE/target/linux/qualcommax/files/net/core/skbuff_debug.h"
check "nf_conntrack_dscpremark_ext header" test -f "$TREE/target/linux/qualcommax/files/include/net/netfilter/nf_conntrack_dscpremark_ext.h"
check "nf_conntrack_dscpremark_ext source" test -f "$TREE/target/linux/qualcommax/files/net/netfilter/nf_conntrack_dscpremark_ext.c"
check "vendored qca-nss-clients"     test -f "$TREE/package/nss/qca-nss-clients/Makefile"
check "vendored qca-mcs"             test -f "$TREE/package/nss/qca-mcs/Makefile"
check "vendored nss-ifb"             test -f "$TREE/package/nss/nss-ifb/Makefile"
check "vendored qca-nss-cfi"         test -f "$TREE/package/nss/qca-nss-cfi/Makefile"
check "nss-clients bridge-mgr subpkg" grep -q 'qca-nss-drv-bridge-mgr' "$TREE/package/nss/qca-nss-clients/Makefile"
check "nss-clients vlan-mgr subpkg"  grep -q 'qca-nss-drv-vlan-mgr' "$TREE/package/nss/qca-nss-clients/Makefile"
check "nss-clients front-end patches" test -f "$TREE/target/linux/qualcommax/patches-6.12/0603-1-qca-nss-clients-add-qdisc-support.patch" \
                              -a -f "$TREE/target/linux/qualcommax/patches-6.12/0603-6-qca-nss-clients-add-bridge-mgr-support.patch" \
                              -a -f "$TREE/target/linux/qualcommax/patches-6.12/0604-1-qca-add-mcs-support.patch" \
                              -a -f "$TREE/target/linux/qualcommax/patches-6.12/0605-1-qca-nss-cfi-support.patch" \
                              -a -f "$TREE/target/linux/qualcommax/patches-6.12/0607-1-qca-nss-clients-iptunnel-fixes.patch"
check "skb notifier header"          test -f "$TREE/target/linux/qualcommax/files/net/core/skbuff_notifier.h"
check "skb notifier source"          test -f "$TREE/target/linux/qualcommax/files/net/core/skbuff_notifier.c"
check "skb debug source"             test -f "$TREE/target/linux/qualcommax/files/net/core/skbuff_debug.c"
check "nss mirred uapi header"       test -f "$TREE/target/linux/qualcommax/files/include/uapi/linux/tc_act/tc_nss_mirred.h"
check "qca-nss-dp pinned to 6.12 ref" grep -q '6a5c4716ca258d67202fc7964c9294dfefa3ccfa' "$TREE/package/kernel/qca-nss-dp/Makefile"
check "qca-ssdk log patch"           test -f "$TREE/package/kernel/qca-ssdk/patches/0012-suppress-noisy-error-log.patch"
check "seed ships nss front-ends"    grep -q 'CONFIG_PACKAGE_kmod-qca-nss-drv-bridge-mgr=y' "$REPO_DIR/config/nn6000.seed"
check "seed selects v2-nowifi device" grep -q 'CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_link_nn6000-v2-nowifi=y' "$REPO_DIR/config/nn6000.seed"
check "seed enables bridge feature"  grep -q 'CONFIG_NSS_DRV_BRIDGE_ENABLE=y' "$REPO_DIR/config/nn6000.seed"
check "seed enables vlan feature"    grep -q 'CONFIG_NSS_DRV_VLAN_ENABLE=y' "$REPO_DIR/config/nn6000.seed"
check "nf_conntrack exp_event guard"  test -f "$TREE/target/linux/qualcommax/patches-6.12/0608-1-nf_conntrack-guard-null-expect-event-cb.patch"
check "ecm conntrack_max raised to 65535" grep -q 'nf_conntrack_max=65535' "$TREE/package/nss/qca-nss-ecm/files/qca-nss-ecm.sysctl"
check "vendored smartdns package"     test -f "$TREE/package/luci/smartdns/Makefile"
check "smartdns pinned to 48.4"       grep -q 'PKG_VERSION:=48.4' "$TREE/package/luci/smartdns/Makefile"
check "smartdns source staged to dl/" test -f "$TREE/dl/smartdns-Release48.4.tar.gz"
check "vendored luci-app-smartdns"    test -f "$TREE/package/luci/luci-app-smartdns/Makefile"
check "vendored luci-app-adguardhome" test -f "$TREE/package/luci/luci-app-adguardhome/Makefile"
check "adguardhome core updater"      test -f "$TREE/package/luci/luci-app-adguardhome/root/usr/share/AdGuardHome/update_core.sh"
check "vendored tailscale package"    test -f "$TREE/package/luci/tailscale/Makefile"
check "tailscale pinned to 1.104.1"   grep -q 'PKG_VERSION:=1.104.1' "$TREE/package/luci/tailscale/Makefile"
check "tailscale builds with golang1.27" grep -q 'PKG_BUILD_DEPENDS:=golang1.27/host' "$TREE/package/luci/tailscale/Makefile"
check "tailscale source staged to dl/" test -f "$TREE/dl/tailscale-1.104.1.tar.gz"
check "vendored golang1.27 (Go 1.27.2)" grep -q 'GO_VERSION_PATCH:=2' "$TREE/package/lang/golang/golang1.27/Makefile"
check "golang1.27 feed-relative include" grep -q '^include \.\./golang-version\.mk$' "$TREE/package/lang/golang/golang1.27/Makefile"
CR=$(printf '\r')
if grep -rIl "$CR" "$TREE/package/nss" "$TREE/package/luci" "$TREE/files/etc" \
              "$TREE/target/linux/qualcommax/patches-6.12" \
              "$TREE/target/linux/qualcommax/files/net/core" \
              "$TREE/target/linux/qualcommax/files/net/netfilter" \
              "$TREE/target/linux/qualcommax/files/include/net/netfilter" \
              "$TREE/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom" \
              "$REPO_DIR/blocks" "$SCRIPT_DIR" >/dev/null 2>&1; then
	echo "  FAIL  vendored packages/patches contain CRLF line endings" >&2
	exit 1
else
	echo "  ok    vendored packages/patches/scripts use LF line endings"
fi

echo
echo "NN6000 port applied successfully."
echo "Next steps (in $TREE):"
echo "  ./scripts/feeds update -a"
echo "  sh $SCRIPT_DIR/setup-feeds.sh ."
echo "  ./scripts/feeds update -i && ./scripts/feeds install -a"
echo "  cat $REPO_DIR/config/nn6000.seed > .config && make defconfig"
echo "  sh $SCRIPT_DIR/verify-config.sh ."
echo "  make -j\$(nproc)"
