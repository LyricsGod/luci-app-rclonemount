#!/bin/sh
# ============================================================
# 构建 luci-app-rclonemount.ipk
#
# 本包是 PKGARCH=all（纯 Lua + shell 脚本，没有需要交叉编译的东西），
# 所以不需要 OpenWrt SDK，直接按 ipk 规范打包即可。
# 本地和 GitHub Actions 用的是同一个脚本。
#
# 用法:
#   sh build-ipk.sh                      # 输出 build/*.ipk
#   PKG_VERSION=1.1 sh build-ipk.sh      # 指定版本
# ============================================================

set -e

PKG_NAME="luci-app-rclonemount"
PKG_VERSION="${PKG_VERSION:-1.1.0}"
PKG_RELEASE="${PKG_RELEASE:-1}"
ARCH="all"
FULL_VER="$PKG_VERSION-$PKG_RELEASE"

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
OUTDIR="$ROOT_DIR/build"
IPK="$OUTDIR/${PKG_NAME}_${FULL_VER}_${ARCH}.ipk"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

echo "构建 $PKG_NAME $FULL_VER ($ARCH)"

# ---------------- data ----------------
D="$STAGE/data"
mkdir -p "$D/usr/lib/lua/luci/controller" \
         "$D/usr/lib/lua/luci/model/cbi" \
         "$D/usr/lib/lua/luci/view/rclonemount" \
         "$D/usr/bin" \
         "$D/etc/config" \
         "$D/etc/init.d" \
         "$D/etc/uci-defaults"

cp "$ROOT_DIR/luasrc/controller/rclonemount.lua"          "$D/usr/lib/lua/luci/controller/"
cp "$ROOT_DIR/luasrc/model/cbi/rclonemount.lua"           "$D/usr/lib/lua/luci/model/cbi/"
cp "$ROOT_DIR/luasrc/view/rclonemount/status.htm"         "$D/usr/lib/lua/luci/view/rclonemount/"
cp "$ROOT_DIR/root/usr/bin/rclonemount"                   "$D/usr/bin/"
cp "$ROOT_DIR/root/etc/init.d/rclonemount"                "$D/etc/init.d/"
cp "$ROOT_DIR/root/etc/uci-defaults/zzz-rclonemount"      "$D/etc/uci-defaults/"
cp "$ROOT_DIR/root/etc/config/rclonemount"                "$D/etc/config/"

chmod 755 "$D/usr/bin/rclonemount" \
          "$D/etc/init.d/rclonemount" \
          "$D/etc/uci-defaults/zzz-rclonemount"
chmod 644 "$D/usr/lib/lua/luci/controller/rclonemount.lua" \
          "$D/usr/lib/lua/luci/model/cbi/rclonemount.lua" \
          "$D/usr/lib/lua/luci/view/rclonemount/status.htm" \
          "$D/etc/config/rclonemount"

# ---------------- control ----------------
C="$STAGE/control"
mkdir -p "$C"
SIZE=$(du -sk "$D" | awk '{print $1}')

cat > "$C/control" <<EOF
Package: $PKG_NAME
Version: $FULL_VER
Depends: libc, luci-base, rclone
License: MIT
Section: luci
Architecture: $ARCH
Installed-Size: $SIZE
Maintainer: LyricsGod <https://github.com/LyricsGod>
Source: https://github.com/LyricsGod/luci-app-rclonemount
Description:  LuCI 网盘挂载管理界面 (rclone + Alist/OpenList WebDAV + Jellyfin)
 在 LuCI 中管理网盘挂载：查看挂载状态与缓存，刷新目录缓存、重新挂载、卸载，
 并可配置挂载点、WebDAV 地址、缓存策略、并发与重试参数。
 菜单入口：状态 -> 网盘挂载
EOF

# 声明为配置文件，升级时保留用户已改过的内容
cat > "$C/conffiles" <<EOF
/etc/config/rclonemount
EOF

cat > "$C/postinst" <<'EOF'
#!/bin/sh
chmod 755 /usr/bin/rclonemount /etc/init.d/rclonemount 2>/dev/null
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
if [ -z "$IPKG_INSTROOT" ]; then
	/etc/init.d/rclonemount enable
	# 升级时 prerm 会先 stop，装完这里要主动挂回去，
	# 否则用户升级完发现网盘没了（配置里停用的除外）
	# 必须后台跑：挂载要等 OpenList 就绪，同步执行会把 opkg 安装流程整个卡住
	if [ "$(uci -q get rclonemount.main.enabled)" = "1" ]; then
		(/etc/init.d/rclonemount start >/dev/null 2>&1 &)
	fi
fi
exit 0
EOF

cat > "$C/prerm" <<'EOF'
#!/bin/sh
if [ -z "$IPKG_INSTROOT" ]; then
	/etc/init.d/rclonemount stop 2>/dev/null
	/etc/init.d/rclonemount disable 2>/dev/null
fi
exit 0
EOF

chmod 755 "$C/postinst" "$C/prerm"

# ---------------- 打包 ----------------
mkdir -p "$OUTDIR"
(cd "$D" && tar czf "$STAGE/data.tar.gz" .)
(cd "$C" && tar czf "$STAGE/control.tar.gz" .)
echo "2.0" > "$STAGE/debian-binary"
(cd "$STAGE" && tar czf "$IPK" debian-binary control.tar.gz data.tar.gz)

echo
echo "已生成: $IPK"
echo "大小  : $(ls -lh "$IPK" | awk '{print $5}')"
