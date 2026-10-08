#!/bin/sh

set -eu

if [ $# -ne 2 ]; then
	echo "usage: $0 <istoreos-tree-root> <blocks-dir>" >&2
	exit 1
fi

ROOT="$1"
BLOCKS="$2"

if [ ! -f "$ROOT/target/linux/qualcommax/Makefile" ]; then
	echo "ERROR: $ROOT does not look like an OpenWrt/iStoreOS tree" >&2
	exit 1
fi

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t nn6000)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/prog.awk" <<'AWKEOF'
BEGIN {
	bmark = sprintf("# >>> NN6000 %s >>>", TAG)
	emark = sprintf("# <<< NN6000 %s <<<", TAG)

	nb = 0
	while ((getline b < BLOCK) > 0) {
		sub(/\r$/, "", b)
		blk[++nb] = b
		if (b != "")
			blkset[b] = 1
	}
	close(BLOCK)

	na = 0
	if (ANCHFILE != "") {
		while ((getline a < ANCHFILE) > 0) {
			sub(/\r$/, "", a)
			anc[++na] = a
		}
		close(ANCHFILE)
	}
}

{ sub(/\r$/, ""); ln[NR] = $0 }

END {
	# 1. strip previous insertion
	m = 0
	i = 1
	while (i <= NR) {
		if (INLINE == 0 && ln[i] == bmark) {
			while (i <= NR && ln[i] != emark)
				i++
			i++		# drop the END marker too
			continue
		}
		if (INLINE == 1 && (ln[i] in blkset)) {
			i++
			continue
		}
		out[++m] = ln[i]
		i++
	}

	# 2. build the new insertion
	ins = 0
	if (INLINE == 0)
		insarr[++ins] = bmark
	for (k = 1; k <= nb; k++)
		insarr[++ins] = blk[k]
	if (INLINE == 0)
		insarr[++ins] = emark

	# 3. locate the anchor
	if (MODE == "append") {
		pos = m + 1
	} else {
		pos = 0
		for (j = 1; j + na - 1 <= m; j++) {
			hit = 1
			for (k = 1; k <= na; k++) {
				if (out[j + k - 1] != anc[k]) {
					hit = 0
					break
				}
			}
			if (hit) {
				pos = j
				break
			}
		}
		if (pos == 0) {
			printf "ERROR: anchor not found for tag %s\n", TAG > "/dev/stderr"
			exit 2
		}
		if (MODE == "after")
			pos = pos + na
	}

	# 4. emit
	for (j = 1; j < pos; j++)
		print out[j]
	for (k = 1; k <= ins; k++)
		print insarr[k]
	for (j = pos; j <= m; j++)
		print out[j]
}
AWKEOF

cat > "$TMP/a_iface" <<'EOF'
	8devices,mango-dvk|\
	glinet,gl-axt1800)
		ucidef_set_interfaces_lan_wan "lan1 lan2" "wan"
		;;
EOF

cat > "$TMP/a_wax214" <<'EOF'
	netgear,wax214)
EOF

cat > "$TMP/a_default" <<'EOF'
	*)
EOF

cat > "$TMP/a_iodata_list" <<'EOF'
	iodata_wn-dax3000gr \
EOF

cat > "$TMP/a_iodata_eval" <<'EOF'
$(eval $(call generate-ipq-wifi-package,iodata_wn-dax3000gr,I-O DATA WN-DAX3000GR))
EOF

cat > "$TMP/a_ubootenv" <<'EOF'
	ubootenv_add_mtd "u_env" "0x0" "0x40000" "0x20000"
	;;
EOF

# Anchors on the tail of the kmod-ipt-ipopt definition in modules/netfilter.mk:
# inserting before it places the fragment after `$(call AddDepends/ipt)` and
# still inside the define body, so DEPENDS+= survives the AddDepends := assign.
cat > "$TMP/a_ipt_ipopt" <<'EOF'
endef

define KernelPackage/ipt-ipopt/description
EOF

P() {
	_rel=$1; _tag=$2; _mode=$3; _anch=$4; _blk=$5; _inline=$6
	_path="$ROOT/$_rel"
	if [ ! -f "$_path" ]; then
		echo "ERROR: target file not found (wrong iStoreOS version?): $_rel" >&2
		exit 1
	fi
	if [ ! -f "$BLOCKS/$_blk" ]; then
		echo "ERROR: block fragment not found: $BLOCKS/$_blk" >&2
		exit 1
	fi
	_ancharg=""
	[ "$_anch" != "-" ] && _ancharg="$TMP/$_anch"
	if awk -v TAG="$_tag" -v MODE="$_mode" -v INLINE="$_inline" \
	      -v BLOCK="$BLOCKS/$_blk" -v ANCHFILE="$_ancharg" \
	      -f "$TMP/prog.awk" "$_path" > "$TMP/out"; then
		cat "$TMP/out" > "$_path"
	else
		echo "ERROR: failed patching [$_tag] $_rel" >&2
		exit 1
	fi
	echo "  patched [$_tag] $_rel"
}

echo "Inserting NN6000 fragments into: $ROOT"

P "target/linux/qualcommax/image/ipq60xx.mk" \
  "device-defs" "append" "-" "ipq60xx.mk.block" 0

P "target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network" \
  "iface" "after" "a_iface" "net-02.block" 0

P "target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata" \
  "caldata" "before" "a_wax214" "caldata.block" 0

P "target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh" \
  "emmc-upgrade" "before" "a_default" "platform.block" 0

P "package/firmware/ipq-wifi/Makefile" \
  "wifi-board-list" "after" "a_iodata_list" "ipqwifi-boards.block" 1

P "package/firmware/ipq-wifi/Makefile" \
  "wifi-board-eval" "after" "a_iodata_eval" "ipqwifi-eval.block" 0

P "package/boot/uboot-tools/uboot-envtools/files/qualcommax_ipq60xx" \
  "ubootenv" "after" "a_ubootenv" "ubootenv.block" 0

P "package/kernel/linux/modules/netfilter.mk" \
  "ipt-ipopt-conntrack" "before" "a_ipt_ipopt" "iptipopt.block" 0

P "target/linux/qualcommax/config-6.12" \
  "nss-kconfig" "append" "-" "kconfig.block" 0

echo "All NN6000 fragments applied."
