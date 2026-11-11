_get_overlay_partition_loop()
{
	local rootdev kbytes devsize off loopdev mm
	rootdev=`readlink -f /dev/root 2>/dev/null`
	if [ ! -b "$rootdev" ]; then
		mm=`awk '$5 == "/" && $0 ~ / - squashfs / { print $3; exit }' /proc/self/mountinfo 2>/dev/null`
		if [ -n "$mm" ]; then
			rootdev=`readlink -f /sys/dev/block/$mm 2>/dev/null`
			rootdev="/dev/${rootdev##*/}"
		fi
	fi
	[ -b "$rootdev" ] || rootdev=`blkid -t PARTLABEL=rootfs -o device 2>/dev/null | head -n1`
	[ -b "$rootdev" ] || {
		log "get_overlay_partition_loop: root device not found"
		return 1
	}
	kbytes=`df -k /rom 2>/dev/null | awk 'NR==2 {print $2}'`
	[ -n "$kbytes" ] && [ "$kbytes" -gt 0 ] 2>/dev/null || \
		kbytes=`df -k / 2>/dev/null | awk 'NR==2 {print $2}'`
	[ -n "$kbytes" ] && [ "$kbytes" -gt 0 ] 2>/dev/null || {
		log "get_overlay_partition_loop: cannot read squashfs size"
		return 1
	}
	off=$(( (kbytes * 1024 + 4095) / 4096 * 4096 ))
	devsize=`cat /sys/class/block/${rootdev##*/}/size 2>/dev/null`
	[ -n "$devsize" ] && devsize=$(( devsize * 512 ))
	[ -n "$devsize" ] && [ $(( devsize - off )) -ge 16777216 ] || {
		log "get_overlay_partition_loop: free space too small"
		return 1
	}
	loopdev=`losetup -f 2>/dev/null`
	[ -n "$loopdev" ] || {
		log "get_overlay_partition_loop: no free loop device"
		return 1
	}
	case "$loopdev" in
	/dev/*) ;;
	*) loopdev="/dev/${loopdev##*/}" ;;
	esac
	losetup -o "$off" "$loopdev" "$rootdev" 2>/dev/null || return 1
	OVERLAY_DEV="$loopdev"
	log "get_overlay_partition_loop: using $loopdev root=$rootdev offset=$off"
	return 0
}

_get_overlay_partition_rootfs_data()
{
	local dev
	dev=`blkid -t PARTLABEL=rootfs_data -o device 2>/dev/null`
	[ -z "$dev" ] && return 1
	OVERLAY_DEV="$dev"
	log "get_overlay_partition_rootfs_data: using $dev"
	return 0
}

_get_overlay_partition_existing()
{
	local dev
	dev=`awk '$2 == "/overlay" { print $1; exit }' /proc/mounts 2>/dev/null`
	case "$dev" in
		/dev/loop*)
			OVERLAY_DEV="$dev"
			log "get_overlay_partition_existing: using $dev"
			return 0
			;;
	esac
	return 1
}

get_overlay_partition()
{
	[ -e /.dockerenv ] && {
		log "No overlay partition in Docker"
		return 1
	}
	_get_overlay_partition_existing || _get_overlay_partition_rootfs_data || _get_overlay_partition_loop || {
		log "Unable to determine overlay partition"
		return 1
	}
	return 0
}
