# NN6000 分区说明

| 文件 | 适用机型 | `rootfs_data` |
| --- | --- | --- |
| [`NN6000_UBOOT.bin`](https://raw.githubusercontent.com/wzdddyy/iStoreOS-NN6000/main/partition/NN6000_UBOOT.bin) | NN6000 v1 / v2，4 GB eMMC 及以上 | 2 GiB |
| [`uboot-ipq60xx-link_nn6000-261119_213729_b95b887.bin`](https://raw.githubusercontent.com/wzdddyy/iStoreOS-NN6000/main/partition/uboot-ipq60xx-link_nn6000-261119_213729_b95b887.bin) | 已刷旧版镜像，仅单独升级 U-Boot | — |

GPT 条目数 20（14 个已用，第 15 个之后为空槽，可直接新建分区）

MAC / UBOOT 修改工具（Windows）：[`M+U修改工具 v1.0.0.exe`](https://raw.githubusercontent.com/wzdddyy/iStoreOS-NN6000/main/partition/M%2BU%E4%BF%AE%E6%94%B9%E5%B7%A5%E5%85%B7%20v1.0.0.exe)

注意：使用此分区镜像，请自行修改MAC地址

## 自动分配剩余空间

下载：[`userdata-autosize`](https://raw.githubusercontent.com/wzdddyy/iStoreOS-NN6000/main/partition/userdata-autosize)

> GitHub 对文本文件默认打开显示内容而不是下载；要保存成文件，右键链接选「将链接另存为」，保存类型选「所有文件」。

自动检测最大空闲区，把 GPT 扩到磁盘末尾，新建 `UserData` 分区、格式化并挂载：


### 用法

放入 /tmp

chmod +x /tmp/userdata-autosize

sh /tmp/userdata-autosize


## 分区表

| # | 分区名称 | 起始 LBA | 结束 LBA | 大小 |
| --- | --- | --- | --- | --- |
| 1 | `0:SBL1` | 34 | 1569 | 768 KiB |
| 2 | `0:BOOTCONFIG` | 1570 | 2081 | 256 KiB |
| 3 | `0:QSEE` | 2082 | 5665 | 1792 KiB |
| 4 | `0:DEVCFG` | 5666 | 6177 | 256 KiB |
| 5 | `0:RPM` | 6178 | 6689 | 256 KiB |
| 6 | `0:CDT` | 6690 | 7201 | 256 KiB |
| 7 | `0:APPSBLENV` | 7202 | 7713 | 256 KiB |
| 8 | `0:APPSBL` | 7714 | 8993 | 640 KiB |
| 9 | `0:ART` | 8994 | 9505 | 256 KiB |
| 10 | `0:HLOS` | 9506 | 75041 | 32 MiB |
| 11 | `0:HLOS_1` | 75042 | 140577 | 32 MiB |
| 12 | `rootfs` | 140578 | 1189153 | 512 MiB |
| 13 | `rootfs_1` | 1189154 | 2237729 | 512 MiB |
| 14 | `rootfs_data` | 2238464 | 6432767 | 2 GiB |

## 分区作用

| 分区 | 作用 |
| --- | --- |
| `0:SBL1` | 二级引导程序，初始化 DDR 后加载 U-Boot |
| `0:BOOTCONFIG` | U-Boot 启动槽位标志（偏移 148 决定读 `0:HLOS` 还是 `0:HLOS_1`） |
| `0:QSEE` | Qualcomm 安全执行环境固件 |
| `0:DEVCFG` | 设备配置 |
| `0:RPM` | 资源与功耗管理固件 |
| `0:CDT` | 板级配置 |
| `0:APPSBLENV` | U-Boot 环境变量（`bootargs`、`bootcmd`），分区内两份互为备份 |
| `0:APPSBL` | U-Boot 本体（uBootKit，自带 Web 刷机界面） |
| `0:ART` | MAC 地址与 WiFi 校准数据（镜像内为示例 MAC，刷入后请自行修改） |
| `0:HLOS` / `0:HLOS_1` | Linux 内核，A/B 双槽 |
| `rootfs` / `rootfs_1` | squashfs 只读根文件系统（固件本体），A/B 双槽 |
| `rootfs_data` | overlay 可写层，存用户配置、插件、数据 |

## 调整说明

- `0:HLOS` / `0:HLOS_1` 内核分区：统一 32 MiB
- `rootfs` / `rootfs_1` 固件分区：统一 512 MiB
- 已内置 26.11.19 版 uBootKit（`U-Boot 2016.01-b95b887`，支持热重启），刷入分区镜像即可直接进入 UBOOT
- `rootfs_data` overlay 分区： 2 GiB，可自行调整
- 没有 `rootfs_data` 分区时，用户数据自动挂载到 `rootfs` 的剩余空间
- 支持此设备的固件源码都可以使用本分区表；其中 OpenWrt / immortalwrt 原生支持，iStoreOS 需配套 `istoreos-boot.sh` 补丁（优先使用 `rootfs_data`）。
- eMMC 剩余空间可自行分配（需先把 GPT 扩到磁盘末尾），或使用 `userdata-autosize` 自动分配。

## 单独更新 U-Boot

已经刷过旧版分区镜像、只想升级 U-Boot（26.11.19 版，新增热重启支持）的，不用重刷整盘，直接写 `0:APPSBL` 分区即可：

下载：[`uboot-ipq60xx-link_nn6000-261119_213729_b95b887.bin`](https://raw.githubusercontent.com/wzdddyy/iStoreOS-NN6000/main/partition/uboot-ipq60xx-link_nn6000-261119_213729_b95b887.bin)（640 KiB，SHA-256 `1406cb73dac3466c973c10b40cfabdc36b82cd07d6476652c73aab4227eddedf`）

1. 上传到设备 `/tmp`，确认分区对应设备：

```sh
grep -H PARTNAME /sys/class/block/mmcblk0p*/uevent | grep APPSBL
```

2. 备份原 U-Boot（把下面命令中的 `mmcblk0p8` 换成上一步查到的设备）：

```sh
dd if=/dev/mmcblk0p8 of=/tmp/uboot-backup.bin bs=64k
```

3. 写入并读回校验：

```sh
dd if=/tmp/uboot-ipq60xx-link_nn6000-261119_213729_b95b887.bin of=/dev/mmcblk0p8 bs=64k conv=fsync
dd if=/dev/mmcblk0p8 bs=64k count=10 | sha256sum
```

读回值与上面的 SHA-256 一致即写入成功。重启进入 U-Boot，版本应显示 `U-Boot 2016.01-b95b887`。

> 注意：必须确认目标是 `PARTNAME=0:APPSBL` 的分区，写错分区会导致设备无法启动。