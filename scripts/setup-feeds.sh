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

rm -rf feeds/luci/applications/luci-app-dockerman \
	feeds/luci/libs/luci-lib-docker \
	feeds/luci/applications/luci-app-ttyd \
	feeds/luci/applications/luci-app-hd-idle \
	feeds/luci/applications/luci-app-samba4 \
	feeds/luci/applications/luci-app-smartdns \
	feeds/luci/applications/luci-app-adguardhome
rm -rf feeds/packages/net/tailscale feeds/packages/lang/golang/golang1.26

rm -rf feeds/packages/lang/golang/golang1.27
mv package/lang/golang/golang1.27 feeds/packages/lang/golang/

for p in "$REPO_DIR"/patches/*.patch; do
	patch -p1 -i "$p"
done
