## iStoreOS for Link NN6000 (v1 / v2)

基于 [iStoreOS](https://github.com/istoreos) `25.12` 分支，适配 **Link NN6000 系列（IPQ6000，eMMC）** 
内核分区 12m，带满血NSS驱动。

## 推荐分区

需先刷入 GPT 分区镜像，再装固件：

- 适用于 4 GB eMMC 及以上：[`NN6000_UBOOT.bin`](https://raw.githubusercontent.com/wzdddyy/iStoreOS-NN6000/main/partition/NN6000_UBOOT.bin)
- 剩余空间自动分区（可选）：[`userdata-autosize`](https://raw.githubusercontent.com/wzdddyy/iStoreOS-NN6000/main/partition/userdata-autosize)

> `userdata-autosize` 是文本文件，GitHub 默认打开显示内容，要保存成文件请右键链接选「将链接另存为」，保存类型选「所有文件」。

原厂分区与本仓库分区镜像的对比、注意事项：**[分区说明（README.md）](partition/README.md)**

## 默认登录

| 项目 | 值 |
| --- | --- |
| 管理地址 | http://192.168.100.1 |
| 用户名 | root |
| 密码 | 空 |

## 内置软件

* **iStoreOS 应用商店**：luci-app-store，store商店；
* **dockerman**：luci-app-dockerman，Docker 容器管理；
* **quickstart**：luci-app-quickstart，开机向导，自动配置上网；
* **autoreboot**：luci-app-autoreboot，定时重启；
* **ttyd**：luci-app-ttyd，网页终端；
* **AdGuardHome**：luci-app-adguardhome，广告过滤 DNS 服务器；
* **lucky**：luci-app-lucky，端口转发 + 反向代理 + DDNS + Web服务 + 网络唤醒；
* **mini-diskmanager**：luci-app-mini-diskmanager，磁盘管理工具；
* **smartdns**：luci-app-smartdns，本地 DNS 服务器，支持分组、分流、缓存与多上游并发查询；
* **upnp**：luci-app-upnp，UPnP IGD 和 PCP/NAT-PMP 服务；
* **hd-idle**：luci-app-hd-idle，硬盘休眠；
* **samba4**：luci-app-samba4，网络共享；
* **tailscale**：luci-app-tailscale，VPN异地组网；
* 内核侧已经具备 dae/daed 运行所需的 eBPF/BTF 条件；


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
├── config/
│   ├── nn6000.seed                      # 个性化配置
│   └── devices/                         # 设备定义 (v1 / v2，各含 wifi + no-wifi)
├── files/                               # 覆盖到源码树的文件
├── patches/                             # 源码树补丁
├── scripts/                             # 应用与校验脚本
```

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

## 界面预览

![固件界面预览](Preview.png)
