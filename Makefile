include $(TOPDIR)/rules.mk

# 包名取自目录名，目录必须是 luci-app-rclonemount
LUCI_TITLE:=LuCI for Rclone network disk mount
LUCI_DESCRIPTION:=Web UI to manage rclone mounting of Alist/OpenList WebDAV storage. \
	Shows mount status, cache usage and logs; provides refresh / remount / unmount \
	actions; allows editing mount point, WebDAV address and all rclone parameters. \
	Integrates with Jellyfin running in Docker.
LUCI_DEPENDS:=+rclone +fuse-utils
LUCI_PKGARCH:=all

# 若此包放在 feeds/luci/applications/ 下，用相对路径即可：
include ../../luci.mk
# 若放在自建 feed，改成：
# include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
