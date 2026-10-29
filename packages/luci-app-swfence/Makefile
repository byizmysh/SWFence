include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-swfence
PKG_VERSION:=0.3.0
PKG_RELEASE:=4
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-swfence
  PKGARCH:=all
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI panel for SWFence
  DEPENDS:=+swfence +luci-base +rpcd
endef

define Build/Compile
endef

define Package/luci-app-swfence/install
	$(INSTALL_DIR) $(1)/www $(1)/usr
	$(CP) ./htdocs/* $(1)/www/
	$(CP) ./root/* $(1)/
endef

define Package/luci-app-swfence/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	rm -f /tmp/luci-indexcache
	/etc/init.d/rpcd restart
fi
exit 0
endef

$(eval $(call BuildPackage,luci-app-swfence))
