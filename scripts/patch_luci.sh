#!/bin/sh
# NN6000 port: post-feeds patch that teaches the luci rpcd object about CPU

set -eu

if [ $# -ne 1 ]; then
	echo "usage: $0 <istoreos-source-tree-root>" >&2
	exit 1
fi
TREE="$1"

UCODE="$TREE/feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"
ACL="$TREE/feeds/luci/modules/luci-mod-status/root/usr/share/rpcd/acl.d/luci-mod-status-index.json"

[ -f "$UCODE" ] || { echo "ERROR: luci rpcd ucode not found: $UCODE" >&2; exit 1; }
[ -f "$ACL" ]   || { echo "ERROR: status ACL not found: $ACL" >&2; exit 1; }

if ! grep -q 'getCPUInfo' "$UCODE"; then
	TMP="$(mktemp)"
	trap 'rm -f "$TMP"' EXIT
	cat >"$TMP" <<'EOF'
	getCPUInfo: {
		call: function(request) {
			const fd = popen('/bin/sh /usr/bin/cpuinfo 2>/dev/null');
			const data = fd ? trim(fd.read('all')) : null;
			if (fd)
				fd.close();
			return { cpuinfo: data || null };
		}
	},
	getTempInfo: {
		call: function(request) {
			const fd = popen('/bin/sh /usr/bin/tempinfo 2>/dev/null');
			const data = fd ? trim(fd.read('all')) : null;
			if (fd)
				fd.close();
			return { tempinfo: data || null };
		}
	},
	getCPUUsage: {
		call: function(request) {
			const fd = popen('/bin/sh /usr/bin/cpuusage 2>/dev/null');
			const data = fd ? trim(fd.read('all')) : null;
			if (fd)
				fd.close();
			return { cpuusage: data || null };
		}
	},
EOF
	sed -i "/^const methods = {$/r $TMP" "$UCODE"
	rm -f "$TMP"
	trap - EXIT
	echo "  patched rpcd ucode (getCPUInfo/getTempInfo/getCPUUsage)"
fi

if ! grep -q 'getCPUUsage' "$ACL"; then
	sed -i 's/"luci": \[ "getVersion", "getUnixtime", "getOdhcp6cStats" \]/"luci": [ "getVersion", "getUnixtime", "getOdhcp6cStats", "getCPUInfo", "getTempInfo", "getCPUUsage" ]/' "$ACL"
	echo "  patched luci-mod-status-index ACL"
fi

grep -q 'getCPUInfo'  "$UCODE" || { echo "ERROR: rpcd ucode patch failed" >&2; exit 1; }
grep -q 'getCPUUsage' "$ACL"   || { echo "ERROR: ACL patch failed" >&2; exit 1; }

echo "luci rpcd/ACL patched for CPU info & temperature display."
