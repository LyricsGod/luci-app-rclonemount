#!/bin/sh
# ============================================================
# 在 Alpine 容器里用官方 abuild 构建 apk。
# 由 .github/workflows/build.yml 通过 docker://alpine 调用。
#
# abuild 不允许以 root 运行，所以这里建一个 abuild 用户再切过去执行。
# ============================================================
set -e

WORKDIR="${WORKDIR:-/github/workspace}"
BUILDER="abuild"

echo "==> 安装 abuild"
apk add --no-cache abuild sudo

echo "==> 准备构建用户"
adduser -D "$BUILDER" 2>/dev/null || true
addgroup "$BUILDER" "$BUILDER" 2>/dev/null || true
mkdir -p "/home/$BUILDER/.abuild"
# 预先写好 PACKAGER，避免 abuild-keygen 交互等待
echo 'PACKAGER="CI <ci@noreply.local>"' > "/home/$BUILDER/.abuild/abuild.conf"
echo "$BUILDER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

chown -R "$BUILDER" "/home/$BUILDER"
# abuild 需要在源码目录里产出 packages/，所以要给它写权限
chown -R "$BUILDER" "$WORKDIR"

echo "==> 生成临时签名密钥"
su "$BUILDER" -c "cd $WORKDIR/apk && abuild-keygen -a -n"

echo "==> 构建"
su "$BUILDER" -c "cd $WORKDIR/apk && abuild -F checksum && abuild -F"

echo "==> 产物"
find "$WORKDIR/apk/packages" -name '*.apk' -ls
