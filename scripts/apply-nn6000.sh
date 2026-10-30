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

find "$REPO_DIR/files" -type f | while IFS= read -r _abs; do
	_rel=${_abs#"$REPO_DIR/files/"}
	case "$_rel" in
		etc/*|usr/*|www/*) _dst="$TREE/files/$_rel" ;;
		*)                 _dst="$TREE/$_rel" ;;
	esac
	if ! cmp -s "$REPO_DIR/files/$_rel" "$_dst"; then
		echo "  FAIL  overlay copy differs: $_rel" >&2
		exit 1
	fi
done
echo "  ok    overlay files match repo"

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

printf '%s\n' "$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M')" > "$TREE/files/etc/nn6000-build-time"
chmod 0644 "$TREE/files/etc/nn6000-build-time"

echo "==> [2/3] Patching existing tree files"
sh "$SCRIPT_DIR/patch_tree.sh" "$TREE" "$REPO_DIR/blocks"

echo "==> [3/3] Verifying"
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1" >&2; exit 1; }

for _f in \
	target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh \
	target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network \
	target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata; do
	sh -n "$TREE/$_f" || fail "shell syntax: $_f"
	ok "shell syntax: $_f"
done

CR=$(printf '\r')
while IFS='|' read -r _mode _desc _file _pattern; do
	_mode=${_mode%"$CR"}; _desc=${_desc%"$CR"}
	_file=${_file%"$CR"}; _pattern=${_pattern%"$CR"}
	case "$_mode" in ''|'#'*) continue ;; esac
	case "$_file" in
		R:*) _path="$REPO_DIR/${_file#R:}" ;;
		*)   _path="$TREE/$_file" ;;
	esac
	case "$_mode" in
		has)
			grep -qF -- "$_pattern" $_path >/dev/null 2>&1 || fail "$_desc"
			ok "$_desc"
			;;
		not)
			if grep -qF -- "$_pattern" $_path >/dev/null 2>&1; then
				fail "$_desc"
			else
				ok "$_desc"
			fi
			;;
		re)
			grep -qE -- "$_pattern" $_path >/dev/null 2>&1 || fail "$_desc"
			ok "$_desc"
			;;
		file)
			for _f in $_path; do
				[ -f "$_f" ] || fail "$_desc"
			done
			ok "$_desc"
			;;
		*)
			fail "unknown check mode: $_mode"
			;;
	esac
done < "$SCRIPT_DIR/checks.tsv"

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
echo "  cat $REPO_DIR/config/nn6000.seed $REPO_DIR/config/devices/*.seed > .config && make defconfig"
echo "  sh $SCRIPT_DIR/verify-config.sh ."
echo "  make -j\$(nproc)"
