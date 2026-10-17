#
# Copyright (c) 2018-2023 Nick Peng (pymumu@gmail.com)
# This is free software, licensed under the GNU General Public License v3.
#
# Vendored from the iStoreOS packages feed (net/smartdns), version bumped from
# 46.1 to 48.4 to match the vendored luci-app-smartdns (1.2026.48.2) -- the
# 48.x UI expects configuration surfaces the 46.1 core does not provide.
# +libatomic is a new dependency since 48.x (per upstream package/openwrt).
# The source tarball sits next to this file and is staged into dl/ by
# apply-nn6000.sh.

include $(TOPDIR)/rules.mk

PKG_NAME:=smartdns
PKG_VERSION:=48.4
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-Release$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/pymumu/smartdns/tar.gz/refs/tags/Release$(PKG_VERSION)?
PKG_HASH:=b07abba99e921f262ba47588e12f5b36dd849f79c0145542440eb6b7eed80553
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-Release$(PKG_VERSION)

PKG_MAINTAINER:=Nick Peng <pymumu@gmail.com>
PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

MAKE_VARS += VER=$(PKG_VERSION)
MAKE_PATH:=src

define Package/smartdns
  SECTION:=net
  CATEGORY:=Network
  TITLE:=smartdns server
  SUBMENU:=IP Addresses and Names
  DEPENDS:=+libpthread +libopenssl +libatomic
  URL:=https://www.github.com/pymumu/smartdns/
endef

define Package/smartdns/description
SmartDNS is a local DNS server which accepts DNS query requests from local network clients,
gets DNS query results from multiple upstream DNS servers concurrently, and returns the fastest IP to clients.
Unlike dnsmasq's all-servers, smartdns returns the fastest IP, and encrypt DNS queries with DoT or DoH.
endef

define Package/smartdns/conffiles
/etc/config/smartdns
/etc/smartdns/address.conf
/etc/smartdns/blacklist-ip.conf
/etc/smartdns/custom.conf
/etc/smartdns/domain-block.list
/etc/smartdns/domain-forwarding.list
endef

define Package/smartdns/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/config $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/smartdns $(1)/etc/smartdns/domain-set $(1)/etc/smartdns/conf.d/
	$(INSTALL_DIR) $(1)/etc/smartdns/ip-set $(1)/etc/smartdns/download
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/smartdns $(1)/usr/sbin/smartdns
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/package/openwrt/files/etc/init.d/smartdns $(1)/etc/init.d/smartdns
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/package/openwrt/address.conf $(1)/etc/smartdns/address.conf
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/package/openwrt/blacklist-ip.conf $(1)/etc/smartdns/blacklist-ip.conf
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/package/openwrt/custom.conf $(1)/etc/smartdns/custom.conf
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/package/openwrt/domain-block.list $(1)/etc/smartdns/domain-block.list
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/package/openwrt/domain-forwarding.list $(1)/etc/smartdns/domain-forwarding.list
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/package/openwrt/files/etc/config/smartdns $(1)/etc/config/smartdns
endef

$(eval $(call BuildPackage,smartdns))
