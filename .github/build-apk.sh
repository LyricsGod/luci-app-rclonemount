#!/bin/sh
# ============================================================
# 在 Alpine 容器里用官方 abuild 构建 apk。
# 由 .github/workflows/build.yml 通过 docker://alpine 调用。
#
# abuild 不允许以 root 运行，所以这里建一个 abuild 用户再切过去执行。
# 每步都打印 exit code，方便在 CI 日志里定位问题。
# ============================================================

WORKDIR="${WORKDIR:-/github/workspace}"
BUILDER="abuild"

echo "==> [0] 环境"
echo "    whoami=$(id -un) uid=$(id -u)"
echo "    workdir=$WORKDIR"
ls -la "$WORKDIR" 2>&1 | head -5
echo "    apk/ 内容:"
ls -la "$WORKDIR/apk" 2>&1 | head -10

echo "==> [1] 安装 abuild"
apk add --no-cache abuild sudo; echo "    exit=$?"

echo "==> [2] 创建构建用户"
# 注意：装完 abuild 后 abuild 组已经存在，必须用 -G 指定它，
# 否则 adduser 会再去建同名组，报 "group 'abuild' in use"
addgroup "$BUILDER" 2>/dev/null
adduser -D -G "$BUILDER" "$BUILDER" 2>&1; echo "    adduser exit=$?"

echo "==> [3] 准备 abuild 配置"
mkdir -p "/home/$BUILDER/.abuild"
cat > "/home/$BUILDER/.abuild/abuild.conf" <<EOF
PACKAGER="CI <ci@noreply.local>"
REPODEST="$WORKDIR/apk/packages"
EOF
echo "$BUILDER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
cat "/home/$BUILDER/.abuild/abuild.conf"

echo "==> [4] 调整属主"
chown -R "$BUILDER" "/home/$BUILDER"; echo "    home exit=$?"
chown -R "$BUILDER" "$WORKDIR"; echo "    workdir exit=$?"

echo "==> [5] 生成签名密钥"
su "$BUILDER" -c "cd $WORKDIR/apk && abuild-keygen -a -n" 2>&1; echo "    exit=$?"
ls -la "/home/$BUILDER/.abuild/" 2>&1 | head -5

echo "==> [5b] 安装公钥，让后续建索引时信任自己的签名"
# 不做这步，abuild 建仓库索引时会报 "UNTRUSTED signature" 而失败
mkdir -p /etc/apk/keys
cp /home/$BUILDER/.abuild/*.rsa.pub /etc/apk/keys/ 2>/dev/null
echo "    cp exit=$?"
ls /etc/apk/keys/ 2>&1 | head -3

echo "==> [6] 校验 ABUILD 元数据"
su "$BUILDER" -c "cd $WORKDIR/apk && abuild -F -d checksum" 2>&1; echo "    exit=$?"

echo "==> [7] 构建"
# -d 禁用依赖检查：rclone / luci-base 是 OpenWrt 的包，Alpine 仓库里没有，
# 不跳过的 abuild 会直接报 "Missing dependencies" 而失败。
# 依赖声明仍会写进包里，装到 OpenWrt 上时照常生效。
su "$BUILDER" -c "cd $WORKDIR/apk && abuild -F -d" 2>&1; echo "    exit=$?"

echo "==> [8] 收集产物"
# abuild 实际输出位置取决于 REPODEST 与仓库名，这里统一收集到固定路径，
# 免得 workflow 里写死路径对不上
OUT="$WORKDIR/apk/packages/noarch"
mkdir -p "$OUT"
find /home/$BUILDER/packages "$WORKDIR/apk/packages" -name '*.apk' 2>/dev/null |
while read -r f; do
	[ -f "$f" ] || continue
	[ "$(dirname "$f")" = "$OUT" ] && continue
	cp -f "$f" "$OUT/" && echo "    收集: $f"
done

echo "==> [9] 校验"
for f in "$OUT"/*.apk; do
	[ -f "$f" ] || continue
	echo "    --- $(basename "$f") ---"
	# apk info 会去查仓库缓存并在容器里报警告、返回非 0，
	# 这里用 manifest 直接读包本身，不做仓库解析
	apk manifest "$f" 2>&1 | head -15
done
ls -lh "$OUT" 2>&1 | head -5
echo "==> 结束"
