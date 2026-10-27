#!/bin/sh
# ============================================================
# 免编译安装脚本 —— 直接在路由器/iStoreOS 上运行
#
#   sh install.sh           安装
#   sh install.sh uninstall 卸载（保留 /etc/config/rclonemount）
#
# 正常做法是用 OpenWrt SDK 编译出 ipk，这个脚本给不想编译的人用。
# ============================================================

set -e

SRC=$(cd "$(dirname "$0")" && pwd)

uninstall() {
	/etc/init.d/rclonemount stop 2>/dev/null || true
	/etc/init.d/rclonemount disable 2>/dev/null || true
	rm -f  /usr/bin/rclonemount
	rm -f  /etc/init.d/rclonemount
	rm -rf /usr/lib/lua/luci/controller/rclonemount.lua
	rm -rf /usr/lib/lua/luci/model/cbi/rclonemount.lua
	rm -rf /usr/lib/lua/luci/view/rclonemount
	rm -f  /etc/uci-defaults/zzz-rclonemount
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
	# 从 crontab 里去掉本项目的任务
	[ -f /etc/crontabs/root ] && \
		grep -v 'rclonemount' /etc/crontabs/root > /tmp/cron.tmp 2>/dev/null && \
		mv /tmp/cron.tmp /etc/crontabs/root
	echo "已卸载（配置文件 /etc/config/rclonemount 保留）"
	exit 0
}

[ "$1" = "uninstall" ] && uninstall

# ---------- 安装 ----------
echo "安装 luci-app-rclonemount ..."

# 控制脚本与服务
mkdir -p /usr/bin /etc/init.d /etc/config /etc/uci-defaults
cp -a "$SRC/root/usr/bin/rclonemount"        /usr/bin/rclonemount
cp -a "$SRC/root/etc/init.d/rclonemount"     /etc/init.d/rclonemount
cp -a "$SRC/root/etc/uci-defaults/zzz-rclonemount" /etc/uci-defaults/zzz-rclonemount
chmod 755 /usr/bin/rclonemount /etc/init.d/rclonemount

# UCI 默认配置（已存在则不覆盖，避免改好的配置被冲掉）
if [ ! -f /etc/config/rclonemount ]; then
	cp -a "$SRC/root/etc/config/rclonemount" /etc/config/rclonemount
	echo "  已写入默认配置 /etc/config/rclonemount"
else
	echo "  已存在 /etc/config/rclonemount，保留现有配置"
fi

# LuCI 文件
mkdir -p /usr/lib/lua/luci/controller /usr/lib/lua/luci/model/cbi /usr/lib/lua/luci/view/rclonemount
cp -a "$SRC/luasrc/controller/rclonemount.lua"        /usr/lib/lua/luci/controller/
cp -a "$SRC/luasrc/model/cbi/rclonemount.lua"         /usr/lib/lua/luci/model/cbi/
cp -a "$SRC/luasrc/view/rclonemount/status.htm"       /usr/lib/lua/luci/view/rclonemount/

# 清 LuCI 缓存
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache

/etc/init.d/rclonemount enable

echo
echo "安装完成。"
echo "  界面入口：LuCI -> 状态 -> 网盘挂载"
echo "  命令行  ：rclonemount {start|stop|restart|refresh|status}"
echo "  配置    ：uci show rclonemount  或  /etc/config/rclonemount"
echo
echo "提示：先确认 /etc/config/rclonemount 里的挂载点和 WebDAV 地址，"
echo "      然后执行 /etc/init.d/rclonemount start"
