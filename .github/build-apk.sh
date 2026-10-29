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
adduser -D "$BUILDER" 2>&1; echo "    adduser exit=$?"
addgroup "$BUILDER" "$BUILDER" 2>&1; echo "    addgroup exit=$?"

echo "==> [3] 准备 abuild 配置"
mkdir -p "/home/$BUILDER/.abuild"
echo 'PACKAGER="CI <ci@noreply.local>"' > "/home/$BUILDER/.abuild/abuild.conf"
echo "$BUILDER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
cat "/home/$BUILDER/.abuild/abuild.conf"
echo "    exit=$?"

echo "==> [4] 调整属主"
chown -R "$BUILDER" "/home/$BUILDER"; echo "    home exit=$?"
chown -R "$BUILDER" "$WORKDIR"; echo "    workdir exit=$?"

echo "==> [5] 生成签名密钥"
su "$BUILDER" -c "cd $WORKDIR/apk && abuild-keygen -a -n" 2>&1; echo "    exit=$?"
ls -la "/home/$BUILDER/.abuild/" 2>&1 | head -5

echo "==> [6] 校验 ABUILD 元数据"
su "$BUILDER" -c "cd $WORKDIR/apk && abuild -F checksum" 2>&1; echo "    exit=$?"

echo "==> [7] 构建"
su "$BUILDER" -c "cd $WORKDIR/apk && abuild -F" 2>&1; echo "    exit=$?"

echo "==> [8] 产物"
find "$WORKDIR" -name '*.apk' 2>/dev/null | head -5
ls -laR "$WORKDIR/apk/packages" 2>&1 | head -20
echo "==> 结束"
