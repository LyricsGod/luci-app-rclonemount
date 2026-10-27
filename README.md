# luci-app-rclonemount

OpenWrt / iStoreOS 上的 LuCI 网盘挂载管理界面。

把「网盘 → Alist/OpenList(WebDAV) → rclone mount → Jellyfin」这条链路做成可视化管理：
挂载点、WebDAV 地址、缓存、并发、重试等参数全部在界面里改，不用再手敲命令、不用手动改 `rclone.conf`。

## 功能

**运行状态页**（状态 → 网盘挂载 → 运行状态）

- 挂载状态、文件系统、读写模式、allow_other、PID、进程内存、已运行时长
- 当前生效的配置（挂载点、WebDAV 地址、缓存上限、目录缓存时间、请求上限）
- 缓存占用、磁盘剩余、日志大小、挂载点顶层目录
- OpenList / Jellyfin 容器 / 定时任务状态
- 最近 6 条日志

**四个操作按钮**

| 按钮 | 作用 |
|---|---|
| 立即刷新 | 发 SIGHUP 清目录缓存，几秒完成，不中断播放。网盘新增了片子 Jellyfin 扫不到时用 |
| 重新挂载 | 重新挂载让配置生效，完成后自动重启 Jellyfin 容器 |
| 重启容器 | 修复容器内 `Transport endpoint is not connected` |
| 卸载 | 只卸载不删数据 |

**看门狗**

每 10 分钟检查一次，挂载掉了自动挂回去。主动执行 `rclonemount stop` 或界面点「卸载」
会留下标记，不会被自动挂回 —— 只有崩溃、重启后没挂上这类情况才自愈。

**配置页**（状态 → 网盘挂载 → 配置）

| 分组 | 可改项 |
|---|---|
| 基础设置 | 启用、Remote 名称、**挂载点路径**、缓存目录、日志文件、rclone 配置文件、OpenList 根地址 |
| WebDAV 设置 | 是否自动同步、**WebDAV 地址**、后端类型、用户名、密码 |
| 缓存与读取 | 缓存上限、最小保留空间、有效期、预读、缓冲区、分块大小与上限、目录缓存、属性缓存 |
| 并发与重试 | 并发传输/检查数、每秒请求上限与突发、超时、重试次数与间隔、底层重试、日志级别 |
| 挂载选项 | 只读、allow_other、允许非空目录、mmap、清空 Referer |
| Jellyfin 集成 | 启用、容器名、挂载后是否重启容器 |

改完保存后点「重新挂载」生效。

## 安装

### 方式一：免编译（推荐先试这个）

把整个目录拷到路由器上，然后：

```sh
sh install.sh
```

卸载：

```sh
sh install.sh uninstall
```

### 方式二：用 OpenWrt SDK 编译 ipk

```sh
# 把本目录放到 SDK 的 package/ 下
cp -r luci-app-rclonemount ~/openwrt-sdk/package/
cd ~/openwrt-sdk
make package/luci-app-rclonemount/compile V=s
# 产物在 bin/packages/*/luci/
```

作为 feed 使用时，把目录放进 `feeds/luci/applications/`，Makefile 里的
`include ../../luci.mk` 就正确；放在自建 feed 则要改成
`include $(TOPDIR)/feeds/luci/luci.mk`。

## 目录结构

```
luci-app-rclonemount/
├── Makefile                              # OpenWrt 包定义（luci.mk）
├── README.md
├── LICENSE
├── install.sh                            # 免编译安装
├── luasrc/                               # → /usr/lib/lua/luci/
│   ├── controller/rclonemount.lua        # 菜单与动作
│   ├── model/cbi/rclonemount.lua         # 配置表单
│   └── view/rclonemount/status.htm       # 状态页
└── root/                                 # → 文件系统根
    ├── etc/
    │   ├── config/rclonemount            # UCI 默认配置
    │   ├── init.d/rclonemount            # 服务脚本
    │   └── uci-defaults/zzz-rclonemount  # 首次启动：enable + 加定时任务
    └── usr/bin/rclonemount               # 挂载控制脚本
```

## 命令行

```sh
rclonemount start      # 挂载（会先同步 WebDAV 配置、等 OpenList 就绪）
rclonemount stop       # 卸载
rclonemount restart    # 重新挂载
rclonemount refresh    # 刷新目录缓存（SIGHUP）
rclonemount status     # 看状态
rclonemount sync       # 只把 WebDAV 配置同步到 rclone.conf

/etc/init.d/rclonemount {start|stop|restart|reload|status|enable|disable}
```

配置文件 `/etc/config/rclonemount`：

```sh
uci set rclonemount.main.mountpoint='/mnt/nvme0n1p5/Alist'
uci set rclonemount.webdav.url='http://127.0.0.1:5244/dav'
uci commit rclonemount
/etc/init.d/rclonemount restart
```

## 依赖

- `rclone`（必需）
- `fuse-utils` / 内核 FUSE 支持（必需）
- Alist 或 OpenList（提供 WebDAV）
- Docker + Jellyfin（可选，用于「挂载后重启容器」）

## 几个设计上的坑

开发过程中踩到并已在代码里规避的问题，改代码时注意：

1. **WebDAV 密码千万别二次混淆**：`rclone.conf` 里的 `pass` 存的**就是混淆后的密文**。
   界面密码留空时要原样写回，如果再跑一次 `rclone obscure`，会变成「密文的密文」，
   表现是挂载成功但一读就 `401 Unauthorized`，紧接着疯狂重试把网盘打到 `429`。
   （这个坑作者踩过，代码里已注释警告。）
2. **探测 OpenList 要打根地址**：`/dav/` 对 GET/HEAD 回 401/405，会被误判成服务没起来。
   同理 busybox 的 `nc` 不带 `-z`，`wget --spider` 也不可靠。
3. **不能对挂载点做 `df`**：量到的是 rclone 挂载本身（会显示 1.0P），
   必须用物理分区上的路径（代码里用的是缓存目录）。
4. **挂载后必须重启 Jellyfin 容器**：容器通常比挂载脚本更早启动，
   容器内绑定的是挂载前的旧实例，不重启就会报 `Transport endpoint is not connected`。
5. **rclone 早期版本没有 `--log-file-max-size`**：日志轮转靠 cron 做
   （先 cp 备份一份再截断），不要加那两个参数，否则挂载直接失败。
6. **LuCI 里 `string.gsub` 返回两个值**：直接 `tonumber(sh(...))` 会把替换次数
   当成进制基数报错，`sh()` 里用外层括号截断成单值。

## 排障：WebDAV 全部返回 429，但 OpenList 网页能正常访问

现象：rclone 挂载读不到任何内容，日志刷 `429 Too Many Requests`，
可 OpenList 网页端浏览网盘却一切正常 —— 看起来像网盘被限流，其实不是。

**一条命令就能区分**，用错误密码访问 WebDAV：

```sh
curl -u 用户名:故意写错的密码 -X PROPFIND -H 'Depth: 1' http://127.0.0.1:5244/dav/
```

- 返回 **429** → 请求在认证之前就被拦了，是 OpenList 对 `/dav/` 的限流，跟网盘无关
- 返回 **401** → 认证链路正常，问题在别处

也可以直接看 OpenList 日志，对比来源 IP：

```
429 | 127.0.0.1     | PROPFIND "/dav/"   ← rclone 走的，被限流
207 | 192.168.2.170 | PROPFIND "/dav/"   ← 浏览器走的，正常
```

**原因**：OpenList 对 `/dav/` 有按 IP 的限流钩子，rclone 的高频请求触发后，
计数不会自动恢复，于是所有来自该 IP 的 WebDAV 请求（连错误密码的也是）一律 429。

**解决**：

```sh
/etc/init.d/openlist restart   # 重启 OpenList 重置限流
```

同时把 `network.tpslimit` 调低（默认 8，遇到限流可降到 5 或 3），减少触发概率。
必要时去 OpenList 后台调整或关闭 WebDAV 限流。

## 关于 Jellyfin

光有挂载不够，刮削慢的元凶常在 Jellyfin 这边，建议：

- 关闭「提取章节图片」和「缩略图/Trickplay 提取」——这两项会把整个视频文件从头读到尾
- 关闭「启用实时监听」，改用定时扫描
- 元数据不要存到媒体所在文件夹（网盘是只读挂载，写会失败）
- 开启硬件转码

媒体库路径填容器内的路径，例如 `/Alist/夸克云盘/电影`。

## 许可证

MIT
