include $(TOPDIR)/rules.mk

PKG_NAME:=swfence
PKG_VERSION:=0.3.0
PKG_RELEASE:=3
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/swfence
  PKGARCH:=all
  SECTION:=net
  CATEGORY:=Network
  TITLE:=LAN-only firewall for Nintendo Switch and Switch 2
  DEPENDS:=+firewall4 +kmod-nft-bridge +dnsmasq +uhttpd +jsonfilter +jshn +uclient-fetch
endef

define Package/swfence/description
  MAC-scoped IPv4 LAN access, external traffic blocking, IPv6 blocking,
  and isolated local Nintendo connection-check responses.
endef

define Package/swfence/conffiles
/etc/config/swfence
/etc/swfence/
endef

define Build/Compile
endef

define Package/swfence/install
	$(INSTALL_DIR) $(1)/etc $(1)/usr $(1)/lib/upgrade/keep.d
	$(CP) ./files/* $(1)/
	printf '%s\n' '/etc/config/swfence' '/etc/swfence/' '/etc/nftables.d/90-swfence.nft' '/usr/share/nftables.d/ruleset-post/90-swfence.nft' > $(1)/lib/upgrade/keep.d/swfence
endef

define Package/swfence/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	/etc/init.d/swfence enable
fi
exit 0
endef

define Package/swfence/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	/usr/sbin/swfence remove || exit 1
	/etc/init.d/swfence stop
	/etc/init.d/swfence disable
fi
exit 0
endef

$(eval $(call BuildPackage,swfence))
