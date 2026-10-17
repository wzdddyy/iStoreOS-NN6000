## iStoreOS for Link NN6000 v2

基于 [iStoreOS](https://github.com/istoreos) `25.12` 分支，适配 **Link NN6000 系列（IPQ6000，eMMC）** 
内核分区 12m，带满血NSS驱动。

## 推荐分区

[NN6000 GPT分区布局](https://www.right.com.cn/forum/forum.php?mod=viewthread&tid=8468237&extra=&page=1)

## 默认登录

| 项目 | 值 |
| --- | --- |
| 管理地址 | http://192.168.100.1 |
| 用户名 | root |
| 密码 | 空 |

## 内置软件

* **iStoreOS 应用商店**：luci-app-store，store商店；
* **Quickstart 快速引导**：开机向导，自动配置上网；
* **Docker**：docker / dockerd / luci-app-dockerman；
* **lucky**：端口转发 + 反向代理 + DDNS + Web服务 + 网络唤醒；
* **tailscale**：VPN异地组网；
* **smartdns**：本地 DNS 服务器，支持分组、分流、缓存与多上游并发查询；
* **AdGuardHome**：广告过滤 DNS 服务器；
* **mini-diskmanager**：磁盘管理工具；
* **磁盘工具**：lsblk / parted / e2fsprogs / smartmontools；
* **文件系统**：kmod-fs-f2fs / f2fs-tools / kmod-fs-ext4；

## 目录结构

```
istoreos-nn6000/
├── .github/workflows/build-nn6000.yml   # CI 工作流
├── blocks/                              # 补丁
│   ├── ipq60xx.mk.block                 # 设备定义 (v1/v2)
│   ├── platform.block                   # sysupgrade 升级逻辑
│   ├── caldata.block                    # ART 校准数据提取
│   ├── net-02.block                     # 网卡初始化
│   ├── ubootenv.block                   # uboot-envtools eMMC 配置
│   ├── ipqwifi-boards.block             # ipq-wifi 板级注册
│   └── ipqwifi-eval.block               # ipq-wifi 评估板数据
├── config/nn6000.seed                   # 个性化配置
├── files/                               # 覆盖到源码树的文件
├── patches/                             # 源码树补丁
└── scripts/                             # 应用与校验脚本
```

### sysupgrade 自适应

`platform.sh` 自动检测是否存在 `rootfs_1` 分区：单 rootfs 时内核写入活动 HLOS 槽、rootfs 固定写入 `rootfs`；双 rootfs 时内核和 rootfs 均写入当前活动槽。

## 免责声明

刷机有风险，自行承担后果；本仓库仅用于学习交流。

## 感谢

iStoreOS源码：[仓库链接](https://github.com/istoreos/)

NSS 组件的**包定义**取自 [qosmio/nss-packages](https://github.com/qosmio/nss-packages)
的 `NSS-12.5-K6.x` 分支（Qualcomm QSDK 12.5），驱动源码由这些 Makefile 从
Qualcomm CodeLinaro（`git.codelinaro.org/clo/qsdk/oss/lklm/*`）拉取；
`qca-nss-dp` 与 `qca-ssdk` 取自 [openwrt](https://github.com/openwrt) 的同名仓库
（各 pin 到一个内核 6.12 可用的提交），NSS 固件来自
[qosmio/qca-sdk-nss-fw](https://github.com/qosmio/qca-sdk-nss-fw)，
EIP-197 固件沿用 OpenWrt 的 `nss-eip-firmware`。
