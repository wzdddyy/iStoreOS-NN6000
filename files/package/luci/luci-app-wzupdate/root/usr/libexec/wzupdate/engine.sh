#!/bin/sh

BASE=/tmp/wzupdate
STATE=$BASE/state
REMOTE=$BASE/remote.env
LOG=$BASE/update.log
FW=$BASE/firmware.bin
WORK=$BASE/work
PENDING=/etc/wzupdate/pending

REPO_DEFAULT=wzdddyy/iStoreOS-NN6000
MIRROR_DEFAULT='https://ghfast.top/,https://gh-proxy.com/'

UBOOT_URL='https://raw.githubusercontent.com/wzdddyy/iStoreOS-NN6000/main/partition/uboot-ipq60xx-link_nn6000-261119_213729_b95b887.bin'
UBOOT_SUM='1406cb73dac3466c973c10b40cfabdc36b82cd07d6476652c73aab4227eddedf'
UBOOT_SIZE=655360
UBOOT_TAG='b95b887'
UBOOT_FW=$BASE/uboot.bin

mkdir -p "$BASE" /etc/wzupdate 2>/dev/null


log() {
	printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG"
}

do_reboot() {
	log '准备重启设备'
	sync
	reboot
}

kv_write() {
	[ -f "$1" ] || : >"$1"
	sed -i "/^$2=/d" "$1" 2>/dev/null
	printf '%s=%s\n' "$2" "$3" >>"$1"
}

kv_read() {
	local v=""
	[ -f "$1" ] && v=$(sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1)
	[ -n "$v" ] && printf '%s' "$v" || printf '%s' "${3:-}"
}

set_state() {
	printf 'phase=%s\npercent=%s\nmessage=%s\n' "$1" "$2" "$3" >"$STATE.tmp" 2>/dev/null
	mv "$STATE.tmp" "$STATE" 2>/dev/null
}

get_state() {
	local v=""
	v=$(sed -n "s/^$1=//p" "$STATE" 2>/dev/null | head -n1)
	[ -n "$v" ] && printf '%s' "$v" || printf '%s' "${2:-}"
}

uci_get() {
	local v=""
	v=$(uci -q get "wzupdate.settings.$1" 2>/dev/null)
	[ -n "$v" ] || v=$(uci -q get "wzupdate.@wzupdate[0].$1" 2>/dev/null)
	[ -n "$v" ] || v=$(uci -q get "wzupdate.$1" 2>/dev/null)
	[ -n "$v" ] && printf '%s' "$v" || printf '%s' "${2:-}"
}

json_esc() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\r\t' '   '
}

file_size() {
	local n=""
	n=$(wc -c <"$1" 2>/dev/null | tr -d ' \n')
	[ -n "$n" ] || n=0
	printf '%s' "$n"
}


board_id() {
	local b="" m=""
	[ -r /tmp/sysinfo/board_name ] && b=$(tr -d '\r\n ' </tmp/sysinfo/board_name 2>/dev/null)
	if [ -z "$b" ] && [ -r /proc/device-tree/compatible ]; then
		b=$(tr '\000' '\n' </proc/device-tree/compatible 2>/dev/null |
			grep -E '^link,nn6000-v[12]$' | head -n1)
	fi
	if [ -z "$b" ] && [ -r /tmp/sysinfo/model ]; then
		m=$(tr -d '\r\n' </tmp/sysinfo/model 2>/dev/null)
		case "$m" in
			*NN6000*v2*|*nn6000*v2*) b='link,nn6000-v2' ;;
			*NN6000*v1*|*nn6000*v1*) b='link,nn6000-v1' ;;
		esac
	fi
	case "$b" in
		*link,nn6000-v2*) printf 'link_nn6000-v2' ;;
		*link,nn6000-v1*) printf 'link_nn6000-v1' ;;
		*) printf '' ;;
	esac
}

has_wifi() {
	[ -n "$(ls /sys/class/ieee80211/ 2>/dev/null)" ]
}

local_version() {
	local v=""
	[ -r /etc/nn6000-build-time ] && v=$(tr -d '\r\n' </etc/nn6000-build-time)
	printf '%s' "$v"
}

pending_state() {
	local pk="" ck="" ps="" cur=""
	[ -f "$PENDING" ] || { printf 'none'; return 0; }
	ps=$(kv_read "$PENDING" slot '')
	cur=$(current_slot 2>/dev/null)
	if [ -n "$ps" ] && [ -n "$cur" ]; then
		[ "$ps" = "$cur" ] && printf 'applied' || printf 'pending'
		return 0
	fi
	pk=$(version_key "$(kv_read "$PENDING" version '')")
	ck=$(version_key "$(local_version)")
	[ -n "$pk" ] || { printf 'pending'; return 0; }
	if [ -n "$ck" ] && [ "$pk" = "$ck" ]; then
		printf 'applied'
	else
		printf 'pending'
	fi
}

norm_stamp() {
	printf '%s' "$1" | tr -d '\r\n' | tr ' -' '._'
}

version_key() {
	printf '%s' "$1" | tr -cd '0-9'
}

firmware_type() {
	if has_wifi; then printf 'wifi'; else printf 'nowifi'; fi
}

image_target() {
	local base mode
	base=$(board_id)
	case "$base" in
		link_nn6000-v1|link_nn6000-v2) ;;
		*) return 1 ;;
	esac
	mode=$(uci_get image auto)
	case "$mode" in
		wifi) printf '%s' "$base" ;;
		nowifi) printf '%s-nowifi' "$base" ;;
		*)
			if has_wifi; then printf '%s' "$base"; else printf '%s-nowifi' "$base"; fi
			;;
	esac
}

part_dev() {
	local name=$1 p label dev
	p="/dev/disk/by-partlabel/$1"
	if [ -e "$p" ]; then
		readlink -f "$p"
		return 0
	fi
	for p in /sys/class/block/*; do
		[ -r "$p/uevent" ] || continue
		label=$(sed -n 's/^PARTNAME=//p' "$p/uevent" 2>/dev/null | head -n1)
		[ "$label" = "$name" ] || continue
		dev=$(sed -n 's/^DEVNAME=//p' "$p/uevent" 2>/dev/null | head -n1)
		[ -n "$dev" ] || continue
		printf '/dev/%s' "$dev"
		return 0
	done
	return 1
}

part_labels() {
	local p label out=""
	for p in /sys/class/block/*; do
		[ -r "$p/uevent" ] || continue
		label=$(sed -n 's/^PARTNAME=//p' "$p/uevent" 2>/dev/null | head -n1)
		[ -n "$label" ] && out="$out $label"
	done
	printf '%s' "${out# }"
}

ab_missing() {
	local miss=""
	[ -n "$(part_dev '0:BOOTCONFIG')" ] || miss="$miss 0:BOOTCONFIG"
	[ -n "$(part_dev '0:HLOS_1')" ] || miss="$miss 0:HLOS_1"
	[ -n "$(part_dev 'rootfs_1')" ] || miss="$miss rootfs_1"
	printf '%s' "${miss# }"
}

ab_supported() {
	[ -n "$(part_dev '0:BOOTCONFIG')" ] &&
	[ -n "$(part_dev '0:HLOS_1')" ] &&
	[ -n "$(part_dev 'rootfs_1')" ]
}

read_byte() {
	local cnt ch
	cnt=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | wc -c)
	[ "$cnt" = "1" ] || return 1
	ch=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null)
	case "$ch" in
		'') printf '0' ;;
		"'") printf '39' ;;
		'\') printf '92' ;;
		*) printf '%d' "'$ch" ;;
	esac
}

read_uint() {
	local i=0 b val=0 mul=1
	while [ "$i" -lt "$3" ]; do
		b=$(read_byte "$1" $(( $2 + i ))) || return 1
		val=$(( val + b * mul ))
		mul=$(( mul * 256 ))
		i=$(( i + 1 ))
	done
	printf '%s' "$val"
}

current_slot() {
	local cfg a b s root dev uuid
	root=$(sed -n 's/.*root=PARTUUID=\([^ ]*\).*/\1/p' /proc/cmdline 2>/dev/null)
	if [ -n "$root" ]; then
		for s in 0 1; do
			dev=$(part_dev "$(slot_root "$s")" 2>/dev/null)
			[ -n "$dev" ] || continue
			uuid=$(blkid -s PARTUUID -o value "$dev" 2>/dev/null)
			[ -n "$uuid" ] && [ "$uuid" = "$root" ] && { printf '%s' "$s"; return 0; }
		done
	fi
	cfg=$(part_dev '0:BOOTCONFIG') || return 1
	a=$(read_byte "$cfg" 128) || return 1
	b=$(read_byte "$cfg" 148) || return 1
	case "$a:$b" in
		0:0) printf '0' ;;
		1:1) printf '1' ;;
		*) return 1 ;;
	esac
}

slot_kern() {
	case "$1" in
		0) printf '0:HLOS' ;;
		1) printf '0:HLOS_1' ;;
		*) return 1 ;;
	esac
}

slot_root() {
	case "$1" in
		0) printf 'rootfs' ;;
		1) printf 'rootfs_1' ;;
		*) return 1 ;;
	esac
}

write_byte() {
	printf "\\$(printf '%03o' "$3")" | dd of="$1" bs=1 seek="$2" conv=notrunc 2>/dev/null
}

set_slot() {
	local cfg val oa ob ra rb
	val=$1
	case "$val" in
		0|1) ;;
		*) return 1 ;;
	esac
	cfg=$(part_dev '0:BOOTCONFIG') || return 1
	oa=$(read_byte "$cfg" 128) || return 1
	ob=$(read_byte "$cfg" 148) || return 1
	if ! write_byte "$cfg" 128 "$val" || ! write_byte "$cfg" 148 "$val"; then
		write_byte "$cfg" 128 "$oa"
		write_byte "$cfg" 148 "$ob"
		sync
		log '启动槽位写入失败，已恢复原值'
		return 1
	fi
	sync
	command -v blockdev >/dev/null 2>&1 && blockdev --flushbufs "$cfg" >/dev/null 2>&1
	ra=$(read_byte "$cfg" 128) || ra=255
	rb=$(read_byte "$cfg" 148) || rb=255
	if [ "$ra" != "$val" ] || [ "$rb" != "$val" ]; then
		log "启动槽位写入校验失败（回读 $ra/$rb，期望 $val），已恢复原值"
		write_byte "$cfg" 128 "$oa"
		write_byte "$cfg" 148 "$ob"
		sync
		return 1
	fi
	return 0
}


curl_try() {
	curl -fsSL --connect-timeout 10 --max-time 3600 --retry 1 -o "$2" "$1" 2>/dev/null
}

http_get() {
	local url=$1 out=$2 ch mirrors m direct_ok=0
	ch=$(uci_get channel auto)
	mirrors=$(uci_get mirror "$MIRROR_DEFAULT")

	case "$ch" in
		mirror) ;;
		*)
			if curl_try "$url" "$out"; then direct_ok=1; fi
			;;
	esac
	[ "$direct_ok" = "1" ] && return 0
	[ "$ch" = "github" ] && return 1

	IFS=,
	for m in $mirrors; do
		[ -n "$m" ] || continue
		if curl_try "${m}${url}" "$out"; then
			unset IFS
			return 0
		fi
	done
	unset IFS
	return 1
}


check_update() {
	local repo api json tag stamp target name url size notes line checked newer remote_ver cur_ver local_key remote_key sha sha_url sha_idx digest names_cnt digest_cnt i an au ad as body commit rkernel branch rbuild
	repo=$(uci_get repo "$REPO_DEFAULT")
	api="https://api.github.com/repos/$repo/releases/latest?ts=$(date +%s)-$$"
	json="$BASE/release.json"

	set_state checking 3 '正在查询在线版本'
	log "查询在线版本：$repo"
	if ! ab_supported; then
		log "分区检测未通过，缺少：$(ab_missing)；已识别：$(part_labels)"
	fi

	rm -f "$REMOTE"
	if ! http_get "$api" "$json"; then
		set_state error 0 '检查更新失败：无法访问 GitHub'
		log '检查更新失败：无法访问 GitHub Releases'
		return 1
	fi

	tag=$(jsonfilter -i "$json" -e '@.tag_name' 2>/dev/null | head -n1)
	stamp=$(printf '%s' "$tag" | sed 's/.*-//')
	if [ -z "$tag" ] || [ -z "$stamp" ]; then
		set_state error 0 '检查更新失败：发布信息不完整'
		log '检查更新失败：发布信息不完整'
		return 1
	fi

	target=$(image_target)
	case "$target" in
		link_nn6000-v1|link_nn6000-v1-nowifi|link_nn6000-v2|link_nn6000-v2-nowifi) ;;
		*)
			set_state error 0 '当前设备不在支持列表中'
			log "当前设备不在支持列表中（board_name=$(tr -d '\r\n' </tmp/sysinfo/board_name 2>/dev/null | head -n1)，model=$(tr -d '\r\n' </tmp/sysinfo/model 2>/dev/null | head -n1)，目标：$target）"
			return 1
			;;
	esac
	log "当前设备目标：$target"

	jsonfilter -i "$json" -e '@.assets[*].name' >"$BASE/assets.name" 2>/dev/null
	jsonfilter -i "$json" -e '@.assets[*].browser_download_url' >"$BASE/assets.url" 2>/dev/null
	jsonfilter -i "$json" -e '@.assets[*].digest' >"$BASE/assets.digest" 2>/dev/null
	jsonfilter -i "$json" -e '@.assets[*].size' >"$BASE/assets.size" 2>/dev/null

	if [ ! -s "$BASE/assets.name" ]; then
		i=0
		: >"$BASE/assets.name"
		: >"$BASE/assets.url"
		: >"$BASE/assets.digest"
		: >"$BASE/assets.size"
		while [ "$i" -lt 50 ]; do
			an=$(jsonfilter -i "$json" -e "@.assets[$i].name" 2>/dev/null)
			[ -n "$an" ] || break
			au=$(jsonfilter -i "$json" -e "@.assets[$i].browser_download_url" 2>/dev/null)
			ad=$(jsonfilter -i "$json" -e "@.assets[$i].digest" 2>/dev/null)
			as=$(jsonfilter -i "$json" -e "@.assets[$i].size" 2>/dev/null)
			printf '%s\n' "$an" >>"$BASE/assets.name"
			printf '%s\n' "$au" >>"$BASE/assets.url"
			printf '%s\n' "$ad" >>"$BASE/assets.digest"
			printf '%s\n' "$as" >>"$BASE/assets.size"
			i=$((i + 1))
		done
	fi

	name=$(grep -F "$target-squashfs-factory.bin" "$BASE/assets.name" 2>/dev/null | head -n1)
	if [ -z "$name" ]; then
		set_state error 0 '该版本没有适用于当前设备的固件'
		log "该版本没有适用于当前设备的固件（目标：$target，发布：$tag）"
		log "发布固件列表：$(tr '\n' ' ' <"$BASE/assets.name" 2>/dev/null | cut -c1-400)"
		return 1
	fi

	line=$(grep -n -F "$name" "$BASE/assets.name" 2>/dev/null | head -n1 | cut -d: -f1)
	url=""
	[ -n "$line" ] && url=$(sed -n "${line}p" "$BASE/assets.url" 2>/dev/null)
	if [ -z "$url" ]; then
		set_state error 0 '检查更新失败：固件下载地址缺失'
		log '检查更新失败：固件下载地址缺失'
		return 1
	fi

	size=""
	[ -n "$line" ] && size=$(sed -n "${line}p" "$BASE/assets.size" 2>/dev/null)
	case "$size" in ''|*[!0-9]*) size=0 ;; esac
	if [ "$size" = "0" ]; then
		size=$(curl -fsIL --max-time 30 "$url" 2>/dev/null | tr -d '\r')
		size=$(printf '%s' "$size" | sed -n 's/^[Cc]ontent-[Ll]ength: *//p')
		size=$(printf '%s' "$size" | tail -n1)
		case "$size" in ''|*[!0-9]*) size=0 ;; esac
	fi

	sha=""
	names_cnt=$(awk 'END{print NR}' "$BASE/assets.name" 2>/dev/null)
	digest_cnt=$(awk 'END{print NR}' "$BASE/assets.digest" 2>/dev/null)
	if [ -n "$digest_cnt" ] && [ "$names_cnt" = "$digest_cnt" ]; then
		digest=$(sed -n "${line}p" "$BASE/assets.digest" 2>/dev/null)
		case "$digest" in
			sha256:*) sha=${digest#sha256:} ;;
		esac
	fi
	if [ -z "$sha" ]; then
		sha_idx=$(grep -n -F 'sha256sums' "$BASE/assets.name" 2>/dev/null | head -n1 | cut -d: -f1)
		if [ -n "$sha_idx" ]; then
			sha_url=$(sed -n "${sha_idx}p" "$BASE/assets.url" 2>/dev/null)
			if [ -n "$sha_url" ] && http_get "$sha_url" "$BASE/sha256sums"; then
				sha=$(grep -F " $name" "$BASE/sha256sums" 2>/dev/null | awk '{print $1}' | head -n1)
			fi
		fi
	fi
	case "$sha" in ''|*[!0-9a-f]*) sha='' ;; esac

	body=$(jsonfilter -i "$json" -e '@.body' 2>/dev/null)
	notes=$(printf '%s\n' "$body" | head -n1 | cut -c1-400)
	commit=$(printf '%s\n' "$body" | grep -F '提交' | grep -oE '[0-9a-f]{7,40}' | head -n1)
	rkernel=$(printf '%s\n' "$body" | sed -n 's/.*内核版本[^:：]*[:：] *//p' | head -n1 | tr -d '\r')
	branch=$(printf '%s\n' "$body" | sed -n 's/.*iStoreOS 分支[^:：]*[:：] *//p' | head -n1 | tr -d '\r')
	rbuild=$(printf '%s\n' "$body" | sed -n 's/.*编译日期[^:：]*[:：] *//p' | head -n1 | tr -d '\r')
	rbuild=$(norm_stamp "$rbuild")
	checked=$(date '+%H:%M')

	remote_ver=$(printf '%s' "$stamp" | sed 's/_/ /; s/\./-/g')
	cur_ver=$(local_version)
	local_key=$(version_key "$cur_ver")
	remote_key=$(version_key "$stamp")
	newer=0
	if [ -n "$remote_key" ]; then
		if [ -z "$local_key" ] || [ "$remote_key" -gt "$local_key" ] 2>/dev/null; then
			newer=1
		fi
	fi

	kv_write "$REMOTE" REMOTE_TAG "$tag"
	kv_write "$REMOTE" REMOTE_STAMP "$stamp"
	kv_write "$REMOTE" REMOTE_VER "$remote_ver"
	kv_write "$REMOTE" REMOTE_NAME "$name"
	kv_write "$REMOTE" REMOTE_URL "$url"
	kv_write "$REMOTE" REMOTE_SIZE "$size"
	kv_write "$REMOTE" REMOTE_SHA "$sha"
	kv_write "$REMOTE" REMOTE_NEWER "$newer"
	kv_write "$REMOTE" REMOTE_NOTE "$notes"
	kv_write "$REMOTE" REMOTE_COMMIT "$commit"
	kv_write "$REMOTE" REMOTE_KERNEL "$rkernel"
	kv_write "$REMOTE" REMOTE_BRANCH "$branch"
	kv_write "$REMOTE" REMOTE_BUILD "$rbuild"
	kv_write "$REMOTE" CHECKED_AT "$checked"

	log "在线版本：$remote_ver（$tag）"
	if [ "$newer" = "1" ]; then
		log '发现新版本'
	else
		log '当前已是最新版本'
	fi
	return 0
}


download_image() {
	local url expected ch mirrors cands c pid size pct rc part_url part_size
	url=$(kv_read "$REMOTE" REMOTE_URL '')
	expected=$(kv_read "$REMOTE" REMOTE_SIZE 0)
	ch=$(uci_get channel auto)
	mirrors=$(uci_get mirror "$MIRROR_DEFAULT")

	[ -n "$url" ] || { set_state error 0 '未找到匹配的固件'; return 1; }

	part_url=$(kv_read "$BASE/partial" URL '')
	part_size=$(kv_read "$BASE/partial" SIZE 0)
	if [ "$part_url" != "$url" ] || { [ "$expected" -gt 0 ] && [ "$part_size" != "$expected" ]; }; then
		rm -f "$FW"
	fi
	kv_write "$BASE/partial" URL "$url"
	kv_write "$BASE/partial" SIZE "$expected"

	size=$(file_size "$FW")
	if [ "$expected" -gt 0 ] 2>/dev/null && [ "$size" -lt "$expected" ]; then
		local avail need
		avail=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}')
		case "$avail" in ''|*[!0-9]*) avail=0 ;; esac
		need=$(( (expected - size) / 1024 + 16384 ))
		if [ "$avail" -gt 0 ] && [ "$avail" -lt "$need" ]; then
			set_state error 0 '临时空间不足，无法下载固件'
			log "临时空间不足：还需 $((need / 1024))MB，/tmp 可用 $((avail / 1024))MB"
			return 1
		fi
	fi
	if [ "$expected" -gt 0 ] 2>/dev/null && [ "$size" = "$expected" ]; then
		set_state downloading 60 '使用已下载的固件'
		log '检测到完整固件，跳过下载'
		return 0
	fi

	case "$ch" in
		github) cands="$url" ;;
		mirror)
			cands=""
			IFS=,
			for c in $mirrors; do [ -n "$c" ] && cands="$cands ${c}${url}"; done
			unset IFS
			;;
		*)
			cands="$url"
			IFS=,
			for c in $mirrors; do [ -n "$c" ] && cands="$cands ${c}${url}"; done
			unset IFS
			;;
	esac

	for c in $cands; do
		size=$(file_size "$FW")
		if [ "$size" -gt 0 ]; then
			set_state downloading 6 "正在续传（已下载 $((size / 1048576)) MB）"
			log "断点续传：从 $((size / 1048576)) MB 继续，下载：$c"
			curl -fsSL -C - --connect-timeout 10 --max-time 3600 --retry 1 -o "$FW" "$c" 2>/dev/null &
		else
			set_state downloading 6 '正在下载固件'
			log "下载：$c"
			curl -fsSL --connect-timeout 10 --max-time 3600 --retry 1 -o "$FW" "$c" 2>/dev/null &
		fi
		pid=$!
		while kill -0 "$pid" 2>/dev/null; do
			touch "$BASE/lock" 2>/dev/null
			size=$(file_size "$FW")
			if [ "$expected" -gt 0 ] 2>/dev/null; then
				pct=$(( 6 + size * 54 / expected ))
				[ "$pct" -gt 60 ] && pct=60
				set_state downloading "$pct" "下载中 $((size / 1048576)) MB / $((expected / 1048576)) MB"
			else
				set_state downloading 40 "下载中 $((size / 1048576)) MB"
			fi
			sleep 1
		done
		wait "$pid"
		rc=$?
		if [ "$rc" = "0" ] && [ -s "$FW" ]; then
			size=$(file_size "$FW")
			if [ "$expected" -gt 0 ] 2>/dev/null && [ "$size" != "$expected" ]; then
				log "下载大小不符（$size / $expected），清除分片重试"
				rm -f "$FW"
				continue
			fi
			set_state downloading 60 '下载完成'
			log '下载完成'
			return 0
		fi
		if [ "$rc" = "33" ]; then
			log '服务器不支持断点续传，已清除分片'
			rm -f "$FW"
		fi
		log "下载中断（$rc），保留分片，尝试下一个地址"
	done

	set_state error 0 '下载失败，已保留分片，可重新检查更新续传'
	log '下载失败，分片已保留，可重试续传'
	return 1
}

is_squashfs_at() {
	local file=$1 off=$2 bs maj bs_off maj_off
	[ "$(dd if="$file" bs=1 skip="$off" count=4 2>/dev/null)" = "hsqs" ] || return 1
	bs_off=$((off + 12))
	maj_off=$((off + 28))
	bs=$(read_uint "$file" "$bs_off" 4) || return 1
	maj=$(read_uint "$file" "$maj_off" 2) || return 1
	case "$bs" in
		4096|8192|16384|32768|65536|131072|262144|524288|1048576) ;;
		*) return 1 ;;
	esac
	[ "$maj" = "4" ] || return 1
	return 0
}

prepare_image() {
	local size off sha cand expect_sha magic
	set_state verifying 63 '正在校验固件'
	size=$(file_size "$FW")
	if [ "$size" -lt 1048576 ]; then
		set_state error 0 '固件文件不完整'
		log '固件文件不完整'
		return 1
	fi

	off=""
	magic=$(hexdump -v -n 4 -e '1/1 "%02x"' "$FW" 2>/dev/null)
	if [ "$magic" != "d00dfeed" ]; then
		rm -f "$FW" "$BASE/partial"
		set_state error 0 '固件格式无法识别'
		log "固件格式无法识别：内核不是 FIT 镜像（magic=$magic）"
		return 1
	fi
	for cand in $(grep -abo 'hsqs' "$FW" 2>/dev/null | cut -d: -f1 |
			awk '$1 > 1048576 {print}' | head -n 30); do
		if is_squashfs_at "$FW" "$cand"; then
			off=$cand
			break
		fi
	done
	if [ -z "$off" ]; then
		for cand in $((12288 * 1024)) $((131072)); do
			if is_squashfs_at "$FW" "$cand"; then
				off=$cand
				break
			fi
		done
	fi
	if [ -z "$off" ] || [ "$off" -ge $((size - 65536)) ]; then
		set_state error 0 '固件格式无法识别'
		log '固件格式无法识别：未找到 squashfs 文件系统'
		return 1
	fi

	sha=$(sha256sum "$FW" 2>/dev/null | cut -d' ' -f1)
	expect_sha=$(kv_read "$REMOTE" REMOTE_SHA '')
	if [ -n "$expect_sha" ] && [ "$expect_sha" != "$sha" ]; then
		rm -f "$FW" "$BASE/partial"
		set_state error 0 '固件校验失败：SHA-256 不一致'
		log '固件校验失败：SHA-256 与发布校验值不一致'
		return 1
	fi
	if [ -z "$expect_sha" ]; then
		log '发布未提供校验值，仅做写入回读校验'
	fi

	rm -rf "$WORK"
	mkdir -p "$WORK" || return 1
	kv_write "$WORK/meta" OFFSET "$off"
	kv_write "$WORK/meta" SIZE "$size"
	kv_write "$WORK/meta" SHA "$sha"

	log "固件解析：内核 $((off / 1024)) KiB / 系统文件 $(((size - off) / 1024)) KiB"
	log "SHA-256：$sha"
	set_state verifying 66 '固件校验通过'
	return 0
}

verify_dev() {
	local dev=$1 size=$2 want=$3 blocks got
	blocks=$(( (size + 1048575) / 1048576 ))
	got=$(dd if="$dev" bs=1M count="$blocks" 2>/dev/null | head -c "$size" | sha256sum | cut -d' ' -f1)
	[ -n "$want" ] && [ "$want" = "$got" ]
}

uboot_version() {
	local dev
	dev=$(part_dev '0:APPSBL') || return 1
	dd if="$dev" bs=64k count=10 2>/dev/null |
		grep -a -o 'U-Boot 2016\.01-[0-9A-Za-z._-]*' | head -n1
}

uboot_check() {
	local dev cur cur_sha is_new=0 size sha try=0
	dev=$(part_dev '0:APPSBL') || { log '未找到 0:APPSBL 分区，跳过 U-Boot 检查'; return 0; }
	cur=$(uboot_version)
	cur_sha=$(dd if="$dev" bs=1M count=1 2>/dev/null | head -c "$UBOOT_SIZE" | sha256sum | cut -d' ' -f1)
	if [ -z "$cur_sha" ]; then
		log '无法读取 0:APPSBL 内容，跳过 U-Boot 更新'
		return 1
	fi
	case "$cur" in
		*"$UBOOT_TAG"*) is_new=1 ;;
	esac
	if [ "$cur_sha" = "$UBOOT_SUM" ] || [ "$is_new" = "1" ]; then
		return 0
	fi
	log '当前 U-Boot 不支持热重启，正在更新'
	while :; do
		rm -f "$UBOOT_FW"
		http_get "$UBOOT_URL" "$UBOOT_FW" && break
		try=$((try + 1))
		if [ "$try" -ge 3 ]; then
			log 'U-Boot 下载失败'
			return 1
		fi
		log "U-Boot 下载失败，60 秒后重试（$try/3）"
		sleep 60
	done
	size=$(file_size "$UBOOT_FW")
	sha=$(sha256sum "$UBOOT_FW" 2>/dev/null | cut -d' ' -f1)
	if [ "$size" != "$UBOOT_SIZE" ] || [ "$sha" != "$UBOOT_SUM" ]; then
		log "U-Boot 校验失败（大小 $size，SHA-256 ${sha:-空}），已放弃"
		rm -f "$UBOOT_FW"
		return 1
	fi
	log "写入 U-Boot 到 $dev"
	if ! dd if="$UBOOT_FW" of="$dev" bs=64k conv=fsync 2>/dev/null; then
		log 'U-Boot 写入失败'
		return 1
	fi
	if ! verify_dev "$dev" "$UBOOT_SIZE" "$UBOOT_SUM"; then
		log 'U-Boot 写入校验失败'
		return 1
	fi
	rm -f "$UBOOT_FW"
	log 'U-Boot 更新完成，重启后生效'
	return 0
}

write_image() {
	local active inactive kname rname kdev rdev ksize fsize rsize ksha rsha skip ver stamp prev
	active=$(current_slot) || {
		set_state error 0 '无法读取当前启动槽位'
		log '无法读取当前启动槽位，已中止写入'
		return 1
	}
	inactive=$((1 - active))
	kname=$(slot_kern "$inactive")
	rname=$(slot_root "$inactive")
	kdev=$(part_dev "$kname")
	rdev=$(part_dev "$rname")
	if [ "$(pending_state)" = "pending" ]; then
		set_state error 0 '已有待重启的更新'
		log '已有待重启的更新，请先重启或撤回'
		return 1
	fi
	[ -n "$kdev" ] && [ -n "$rdev" ] || {
		set_state error 0 '找不到可写入的备份分区'
		log '找不到可写入的备份分区'
		return 1
	}

	ksize=$(kv_read "$WORK/meta" OFFSET 0)
	fsize=$(kv_read "$WORK/meta" SIZE 0)
	rsize=$((fsize - ksize))
	skip=$((ksize + 1))
	[ "$ksize" -gt 0 ] && [ "$rsize" -gt 0 ] || {
		set_state error 0 '固件信息缺失'
		return 1
	}

	set_state writing 70 '正在写入备份分区（内核）'
	log "写入内核到 $kname（$((ksize / 1024)) KiB）"
	ksha=$(head -c "$ksize" "$FW" 2>/dev/null | sha256sum | cut -d' ' -f1)
	if ! head -c "$ksize" "$FW" 2>/dev/null | dd of="$kdev" bs=65536 conv=fsync 2>/dev/null; then
		set_state error 0 '写入内核失败'
		log '写入内核失败'
		return 1
	fi
	if ! verify_dev "$kdev" "$ksize" "$ksha"; then
		set_state error 0 '内核写入校验失败'
		log '内核写入校验失败'
		return 1
	fi
	log '内核写入校验通过'

	set_state writing 84 '正在写入备份分区（系统文件）'
	log "写入系统文件到 $rname（$((rsize / 1024)) KiB）"
	rsha=$(tail -c +"$skip" "$FW" 2>/dev/null | sha256sum | cut -d' ' -f1)
	if ! tail -c +"$skip" "$FW" 2>/dev/null | dd of="$rdev" bs=1M conv=fsync 2>/dev/null; then
		set_state error 0 '写入系统文件失败'
		log '写入系统文件失败'
		return 1
	fi
	set_state writing 90 '正在校验写入内容'
	log '回读备份分区校验写入结果'
	if ! verify_dev "$rdev" "$rsize" "$rsha"; then
		set_state error 0 '系统文件写入校验失败'
		log '系统文件写入校验失败'
		return 1
	fi
	log '系统文件写入校验通过'

	ver=$(kv_read "$REMOTE" REMOTE_VER '')
	stamp=$(kv_read "$REMOTE" REMOTE_STAMP '')
	prev=$(local_version)
	rm -rf /etc/wzupdate
	mkdir -p /etc/wzupdate
	kv_write "$PENDING" slot "$inactive"
	kv_write "$PENDING" prev_slot "$active"
	kv_write "$PENDING" version "$ver"
	kv_write "$PENDING" stamp "$stamp"
	kv_write "$PENDING" prev_version "$prev"
	kv_write "$PENDING" sha "$(kv_read "$WORK/meta" SHA '')"
	kv_write "$PENDING" time "$(date '+%Y-%m-%d %H:%M')"
	rm -rf "$WORK"
	rm -f "$FW" "$BASE/partial"

	set_state done 100 '已写入，等待重启'
	log '新版本已写入备份分区并完成校验，等待手动重启'
	return 0
}


lock_take() {
	local i=0
	while ! mkdir "$BASE/lock" 2>/dev/null; do
		if [ -n "$(find "$BASE/lock" -mmin +120 2>/dev/null)" ]; then
			rm -rf "$BASE/lock"
			continue
		fi
		i=$((i + 1))
		[ "$i" -gt 5 ] && return 1
		sleep 1
	done
	echo $$ >"$BASE/lock/pid" 2>/dev/null
	return 0
}

lock_release() {
	rm -rf "$BASE/lock"
}

run_manual() {
	lock_take || { log '已有任务在运行'; return 1; }
	: >"$LOG"
	log '开始手动检查更新'
	if ! uboot_check; then
		set_state error 0 'U-Boot 更新失败，已中止固件更新'
		log 'U-Boot 更新失败，已中止固件更新'
		lock_release
		return 1
	fi
	check_update || { lock_release; return 1; }
	if [ "$(kv_read "$REMOTE" REMOTE_NEWER 0)" != "1" ]; then
		set_state idle 0 '已是最新版本'
		lock_release
		return 0
	fi
	if ! ab_supported; then
		set_state error 0 '分区不支持在线更新'
		log "分区检测未通过，缺少：$(ab_missing)；已识别：$(part_labels)"
		lock_release
		return 1
	fi
	if download_image && prepare_image && write_image; then
		:
	else
		[ -f "$STATE" ] || set_state error 0 '更新失败'
	fi
	lock_release
}

run_auto() {
	[ "$(uci_get enabled 0)" = "1" ] || return 0
	[ "$(uci_get auto 0)" = "1" ] || return 0
	[ "$(pending_state)" = "pending" ] && return 0
	lock_take || return 0
	: >"$LOG"
	log '自动检查更新'
	if ! uboot_check; then
		set_state error 0 'U-Boot 更新失败，已暂缓固件更新'
		log 'U-Boot 更新失败，已暂缓固件更新'
		lock_release
		return 0
	fi
	if check_update && [ "$(kv_read "$REMOTE" REMOTE_NEWER 0)" = "1" ]; then
		if ! ab_supported; then
			set_state error 0 '分区不支持在线更新'
			log "分区检测未通过，缺少：$(ab_missing)；已识别：$(part_labels)"
		else
			log '自动更新：开始下载、校验并写入备份分区'
			if download_image && prepare_image && write_image; then
				:
			fi
		fi
	else
		[ "$(get_state phase)" = "error" ] || set_state idle 0 '已是最新版本'
	fi
	lock_release
}

cancel_update() {
	local cur
	if [ ! -f "$PENDING" ]; then
		set_state idle 0 '没有待处理的更新'
		log '没有待处理的更新'
		return 0
	fi
	cur=$(current_slot 2>/dev/null)
	if [ -n "$cur" ] && ! set_slot "$cur"; then
		set_state error 0 '撤回失败：无法恢复启动分区'
		log '无法写回当前启动槽位'
		return 1
	fi
	rm -f "$PENDING"
	rm -rf "$WORK" "$FW" "$BASE/partial"
	set_state idle 0 '已撤回待重启的更新'
	log '已撤回待重启的更新'
	return 0
}

wipe_overlay() {
	local ovl=""
	if command -v factoryreset >/dev/null 2>&1 && factoryreset -y >/dev/null 2>&1; then
		log '已标记 overlay 为重置，重启后重新格式化'
		return 0
	fi
	if [ -r /lib/functions/istoreos-boot.sh ]; then
		. /lib/functions/istoreos-boot.sh
		get_overlay_partition >/dev/null 2>&1
		ovl="$OVERLAY_DEV"
	fi
	[ -n "$ovl" ] || return 1
	echo "RESET000" | dd of="$ovl" bs=512 count=1 conv=notrunc,sync,fsync 2>/dev/null || return 1
	log "已标记 $ovl 为重置，重启后重新格式化"
	return 0
}

cleanup_stale_fstab() {
	local romdev romuuid ovldev ovluuid sec target want euuid edev found changed=0
	romdev=$(awk '$2 == "/rom" { print $1; exit }' /proc/mounts 2>/dev/null)
	ovldev=$(awk '$2 == "/overlay" { print $1; exit }' /proc/mounts 2>/dev/null)
	romuuid=$(blkid -s UUID -o value "$romdev" 2>/dev/null)
	ovluuid=$(blkid -s UUID -o value "$ovldev" 2>/dev/null)
	while :; do
		found=""
		for sec in $(uci -q show fstab 2>/dev/null | sed -n 's/^\(fstab\.[^=]*\)=mount$/\1/p'); do
			target=$(uci -q get "$sec.target")
			case "$target" in
				/rom) want="$romuuid" ;;
				/overlay) want="$ovluuid" ;;
				*) continue ;;
			esac
			[ -n "$want" ] || continue
			euuid=$(uci -q get "$sec.uuid")
			edev=$(uci -q get "$sec.device")
			if [ -n "$euuid" ]; then
				[ "$euuid" = "$want" ] && continue
				found=$sec
				break
			elif [ -n "$edev" ]; then
				case "$target" in
					/rom) [ "$edev" = "$romdev" ] && continue ;;
					/overlay) [ "$edev" = "$ovldev" ] && continue ;;
				esac
				found=$sec
				break
			fi
		done
		[ -n "$found" ] || break
		uci -q delete "$found"
		changed=1
	done
	if [ "$changed" = "1" ]; then
		uci -q commit fstab
		log '已清理失效的系统挂载点配置'
	fi
	return 0
}

apply_update() {
	local slot
	if [ ! -f "$PENDING" ]; then
		log '没有待应用的更新'
		return 1
	fi
	slot=$(kv_read "$PENDING" slot 1)
	if ! set_slot "$slot"; then
		set_state error 0 '切换启动分区失败'
		log '切换启动分区失败'
		return 1
	fi
	if [ "$(uci_get keep_config 1)" = "0" ]; then
		log '更新不保留配置：清除 overlay 数据'
		wipe_overlay || log '清除配置失败，本次仍保留配置'
	fi
	log "已切换到槽位 $slot，即将重启"
	(sleep 2; do_reboot) >/dev/null 2>&1 &
	return 0
}

if [ "$(pending_state)" = "applied" ]; then
	cleanup_stale_fstab
	rm -f "$PENDING"
fi

if [ "${WZU_LIB:-0}" != "1" ]; then
	case "${1:-}" in
		manual) run_manual ;;
		check) run_manual ;;
		auto) run_auto ;;
		cancel) cancel_update ;;
		apply) apply_update ;;
		uboot) uboot_check ;;
		*) echo "usage: $0 {manual|check|auto|cancel|apply|uboot}" >&2; exit 1 ;;
	esac
fi
