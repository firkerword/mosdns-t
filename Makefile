include $(TOPDIR)/rules.mk

PKG_NAME:=mosdns-t
PKG_VERSION:=0.7.1
PKG_RELEASE:=4

# 依赖 LEDE 自带 Go 宿主工具链（会在编译时自动构建）
PKG_BUILD_DEPENDS:=golang/host

CONFIG_COMMIT:=30a5e74d23a5d35ac4adc330382f4522d373755c
CONFIG_ARCHIVE:=mosdns-config-all-$(CONFIG_COMMIT).zip
CONFIG_HASH:=75ade81d74135a2bd02ad850c196d7558a2fc5fb3c476032fda34c16efb1942c

# mosdns 源码使用 OpenWrt 专用 tag
SOURCE_COMMIT:=openwrt-v0.7.1-r4
SOURCE_ARCHIVE:=mosdns-$(SOURCE_COMMIT).tar.gz
SOURCE_HASH:=de408c5475d46ac24d613dcc8ebe675e936e30bf9e814b59db1ed2bba94d0457

PKG_LICENSE:=GPL-3.0-only
PKG_MAINTAINER:=jasonxtt

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Download/mosdns-config
	URL:= \
		https://raw.githubusercontent.com/jasonxtt/file/$(CONFIG_COMMIT)/mosdns/config/ \
		https://cdn.jsdelivr.net/gh/jasonxtt/file@$(CONFIG_COMMIT)/mosdns/config/ \
		https://ghproxy.net/https://raw.githubusercontent.com/jasonxtt/file/$(CONFIG_COMMIT)/mosdns/config/
	URL_FILE:=config_all.zip
	FILE:=$(CONFIG_ARCHIVE)
	HASH:=$(CONFIG_HASH)
endef

define Download/mosdns-source
	URL:= \
		https://codeload.github.com/jasonxtt/mosdns/tar.gz/$(SOURCE_COMMIT) \
		https://ghproxy.net/https://codeload.github.com/jasonxtt/mosdns/tar.gz/$(SOURCE_COMMIT)
	FILE:=$(SOURCE_ARCHIVE)
	HASH:=$(SOURCE_HASH)
endef

define Package/mosdns-t
	SECTION:=net
	CATEGORY:=Network
	SUBMENU:=IP Addresses and Names
	TITLE:=MosDNS-T with embedded WebUI
	URL:=https://github.com/jasonxtt/mosdns
	DEPENDS:=+ca-bundle
endef

define Package/mosdns-t/description
	MosDNS-T packaged for OpenWrt with procd, dnsmasq integration and an
	embedded WebUI. Program upgrades are managed through LuCI or the system
	package manager.
endef

define Package/mosdns-t/conffiles
/etc/config/mosdns-t
/etc/mosdns-t/config_custom.yaml
/etc/mosdns-t/rule/
/etc/mosdns-t/webinfo/
/etc/apk/repositories.d/mosdns-t.list
endef

# 将源码解压到 src/，便于 go build
MOSDNS_SRC:=$(PKG_BUILD_DIR)/src

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/config
	$(INSTALL_DIR) $(MOSDNS_SRC)
	$(eval $(call Download,mosdns-config))
	$(eval $(call Download,mosdns-source))
	unzip -q $(DL_DIR)/$(CONFIG_ARCHIVE) -d $(PKG_BUILD_DIR)/config
	find $(PKG_BUILD_DIR)/config -name .DS_Store -delete
	rm -rf $(PKG_BUILD_DIR)/config/ui
	tar -xzf $(DL_DIR)/$(SOURCE_ARCHIVE) -C $(MOSDNS_SRC) --strip-components=1
endef

define Build/Compile
	# 使用 LEDE 自带 Go 1.26.5 编译（CGO 关闭，静态链接）
	$(GO_BIN_PATH) \
	cd $(MOSDNS_SRC) && \
	CGO_ENABLED=0 GOOS=$(GO_OS) GOARCH=$(GO_ARCH) GOPROXY=https://goproxy.cn,direct \
		go build -trimpath -ldflags "-s -w -X main.version=$(PKG_VERSION)" \
		-o $(PKG_BUILD_DIR)/mosdns-t ./
endef

define Package/mosdns-t/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/mosdns-t $(1)/usr/bin/mosdns-t

	$(INSTALL_DIR) $(1)/etc/mosdns-t
	$(CP) $(PKG_BUILD_DIR)/config/. $(1)/etc/mosdns-t/
	$(SED) 's/listen: ":53"/listen: "127.0.0.1:5335"/' $(1)/etc/mosdns-t/config_custom.yaml
	$(SED) 's|https://1.1.1.1/dns-query|223.5.5.5|; s|https://8.8.8.8/dns-query|223.6.6.6|' $(1)/etc/mosdns-t/sub_config/forward_nocn.yaml
	echo B > $(1)/etc/mosdns-t/rule/switch17.txt
	$(INSTALL_DATA) ./files/config_update_state.json $(1)/etc/mosdns-t/webinfo/config_update_state.json

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/mosdns-t.config $(1)/etc/config/mosdns-t

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/mosdns-t.init $(1)/etc/init.d/mosdns-t

	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./files/mosdns-t-dnsmasq $(1)/usr/libexec/mosdns-t-dnsmasq

	$(INSTALL_DIR) $(1)/etc/apk/keys
	$(INSTALL_DATA) ./files/mosdns-t.pem $(1)/etc/apk/keys/mosdns-t.pem
	$(INSTALL_DIR) $(1)/etc/apk/repositories.d
	$(INSTALL_CONF) ./files/mosdns-t.list $(1)/etc/apk/repositories.d/mosdns-t.list
endef

define Package/mosdns-t/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	if command -v apk >/dev/null 2>&1; then
		sed -i "s|@ARCH@|$$(apk --print-arch)|g" /etc/apk/repositories.d/mosdns-t.list
	fi
	/etc/init.d/mosdns-t enable
}
exit 0
endef

$(eval $(call BuildPackage,mosdns-t))
