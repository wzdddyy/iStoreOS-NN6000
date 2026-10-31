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

SELECTED=$(grep -o '^CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_link_nn6000-[a-z0-9_-]*=y' .config | sed 's/.*DEVICE_//; s/=y$//')
if [ -z "$SELECTED" ]; then
	echo "::error::no link_nn6000 device was selected by defconfig"
	grep -o 'TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_[a-z0-9_.-]*' tmp/.config-target.in 2>/dev/null | sort -u || true
	FAIL=1
else
	for d in $SELECTED; do
		echo "::notice::device selected: $d"
	done
fi
if grep -q '^CONFIG_TARGET_MULTI_PROFILE=y' .config; then
	echo "::notice::multi-profile mode enabled"
else
	echo "::error::TARGET_MULTI_PROFILE is not set; cannot build multiple devices"
	FAIL=1
fi

for sym in $(sed -n 's/^\(CONFIG_TARGET_DEVICE_[^=]*\)=y$/\1/p' "$REPO_DIR"/config/devices/*.seed); do
	if grep -q "^${sym}=y" .config; then
		echo "  ok      $sym"
	else
		echo "::error::$sym was dropped by defconfig"
		FAIL=1
	fi
done

HARD=$(sed -n 's/^CONFIG_PACKAGE_\([^=]*\)=y$/\1/p' \
	"$REPO_DIR/config/nn6000.seed" \
	"$REPO_DIR/config/devices/"*.seed)
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

HARD_KERNEL=$(sed -n 's/^\(CONFIG_KERNEL_[^=]*\)=y$/\1/p' \
	"$REPO_DIR/config/nn6000.seed")
MISSING_KERNEL=""
for k in $HARD_KERNEL; do
	if grep -q "^${k}=y" .config; then
		echo "  ok      $k"
	else
		echo "  MISSING $k"
		MISSING_KERNEL="$MISSING_KERNEL $k"
	fi
done
if [ -n "$MISSING_KERNEL" ]; then
	echo "::error::Required kernel symbols were dropped by defconfig:$MISSING_KERNEL"
	FAIL=1
fi

exit $FAIL
