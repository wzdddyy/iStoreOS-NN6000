include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-wzupdate
PKG_VERSION:=1.2.0
PKG_RELEASE:=1
PKG_MAINTAINER:=wzdddyy
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-wzupdate
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=在线更新 (wzupdate)
  DEPENDS:=+luci-base +curl +ca-bundle +jsonfilter
  PKGARCH:=all
endef

define Package/luci-app-wzupdate/description
 Link NN6000 固件在线更新：检查新版本、写入备份分区、校验后手动重启生效，支持撤回。
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/luci-app-wzupdate/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/wzupdate $(1)/etc/config/wzupdate
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/wzupdate $(1)/etc/init.d/wzupdate
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/95-wzupdate $(1)/etc/uci-defaults/95-wzupdate
	$(INSTALL_DIR) $(1)/usr/libexec/wzupdate
	$(INSTALL_BIN) ./root/usr/libexec/wzupdate/engine.sh $(1)/usr/libexec/wzupdate/engine.sh
	$(INSTALL_BIN) ./root/usr/libexec/wzupdate/autocheck $(1)/usr/libexec/wzupdate/autocheck
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) ./root/usr/libexec/rpcd/wzupdate $(1)/usr/libexec/rpcd/wzupdate
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-wzupdate.json $(1)/usr/share/luci/menu.d/luci-app-wzupdate.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-wzupdate.json $(1)/usr/share/rpcd/acl.d/luci-app-wzupdate.json
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/wzupdate
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/wzupdate/overview.js $(1)/www/luci-static/resources/view/wzupdate/overview.js
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/wzupdate/style.css $(1)/www/luci-static/resources/view/wzupdate/style.css
endef

define Package/luci-app-wzupdate/conffiles
/etc/config/wzupdate
endef

define Package/luci-app-wzupdate/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/wzupdate enable
	rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/*
}
exit 0
endef

$(eval $(call BuildPackage,luci-app-wzupdate))
