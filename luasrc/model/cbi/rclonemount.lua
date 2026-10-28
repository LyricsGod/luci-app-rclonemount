--[[
LuCI - Lua Configuration Interface
Rclone 网盘挂载 - 配置页面
]]--

local m, s, o

m = Map("rclonemount", translate("Rclone 网盘挂载"),
	translate("配置网盘挂载参数。保存后需要「重新挂载」才会生效 —— 可到「运行状态」页点按钮，或执行 /etc/init.d/rclonemount restart。"))

-- ============================ 基础设置 ============================
s = m:section(NamedSection, "main", "rclonemount", translate("基础设置"))
s.addremove = false
s.anonymous = false

o = s:option(Flag, "enabled", translate("启用挂载"))
o.default = "1"
o.rmempty = false

o = s:option(Value, "remote", translate("Remote 名称"))
o.default = "alist:"
o.rmempty = false
o.description = translate("rclone 配置里的 remote 名。若网盘挂在子目录，写成 alist:/子目录")

o = s:option(Value, "mountpoint", translate("挂载点路径"))
o.default = "/mnt/nvme0n1p5/Alist"
o.rmempty = false
o.description = translate("网盘挂载到本地哪个目录，Jellyfin 的媒体库就填这个目录下的路径")

o = s:option(Value, "cachedir", translate("缓存目录"))
o.default = "/mnt/nvme0n1p5/Caches/Rclone"
o.description = translate("必须放在本地磁盘上，别放 /tmp（内存盘）。建议与挂载点同一块盘")

o = s:option(Value, "logfile", translate("日志文件"))
o.default = "/mnt/nvme0n1p5/Logs/rclone-alist.log"
o.description = translate("别放 /var/log，那是内存盘。日志会持续增长，靠定时任务轮转")

o = s:option(Value, "rclone_config", translate("rclone 配置文件"))
o.default = "/root/.config/rclone/rclone.conf"

o = s:option(Value, "alist_url", translate("OpenList 根地址"))
o.default = "http://127.0.0.1:5244"
o.description = translate("启动时探测服务是否就绪用，填根地址（不带 /dav）。同机务必用 127.0.0.1")

-- ============================ WebDAV ============================
s = m:section(NamedSection, "webdav", "webdav", translate("WebDAV 设置"))
s.addremove = false
s.anonymous = false

o = s:option(Flag, "sync", translate("启动时同步到 rclone.conf"))
o.default = "1"
o.description = translate("开启后，每次挂载前会把下面填的地址账号写回 rclone.conf，改这里就够了")

o = s:option(Value, "url", translate("WebDAV 地址"))
o.default = "http://127.0.0.1:5244/dav"
o.description = translate("Alist/OpenList 的 WebDAV 地址，同机用 127.0.0.1 比走局域网 IP 快")

o = s:option(ListValue, "vendor", translate("后端类型"))
o.default = "other"
o:value("other", translate("标准 WebDAV（Alist/OpenList 选这个）"))
o:value("rclone", "rclone")
o:value("owncloud", "ownCloud")
o:value("nextcloud", "Nextcloud")
o:value("sharepoint", "SharePoint")

o = s:option(Value, "user", translate("用户名"))
o = s:option(Value, "pass", translate("密码"))
o.password = true
o.description = translate("留空则保持原密码不变，不填也能正常挂载")

-- ============================ 缓存与读取 ============================
s = m:section(NamedSection, "cache", "cache", translate("缓存与读取"))
s.addremove = false
s.anonymous = false

o = s:option(Value, "max_size", translate("缓存上限"))
o.default = "20G"
o.description = translate("按磁盘剩余空间量力而行，别把盘撑满")

o = s:option(Value, "min_free", translate("最小保留空间"))
o.default = "5G"
o.description = translate("磁盘剩余低于此值就自动清理缓存")

o = s:option(Value, "max_age", translate("缓存有效期"))
o.default = "72h"

o = s:option(Value, "read_ahead", translate("预读大小"))
o.default = "128M"
o.description = translate("每个打开文件的预读量。调大起播更快但拖动进度条时浪费的流量也更多")

o = s:option(Value, "buffer_size", translate("缓冲区大小"))
o.default = "32M"

o = s:option(Value, "chunk_size", translate("分块大小"))
o.default = "32M"
o.description = translate("单次向网盘请求的字节数。太大会拖慢起播，太小请求数暴涨")

o = s:option(Value, "chunk_limit", translate("分块上限"))
o.default = "128M"
o.description = translate("顺序读时分块逐步放大到这个上限。设太大容易触发超时重传")

o = s:option(Value, "dir_cache_time", translate("目录缓存时间"))
o.default = "72h"
o.description = translate("调大能大幅减少刮削时的目录请求。新片要用「刷新目录缓存」才会出现")

o = s:option(Value, "attr_timeout", translate("属性缓存时间"))
o.default = "1h"

o = s:option(Value, "poll_interval", translate("缓存巡检间隔"))
o.default = "1m"
o.description = translate("rclone 检查并清理缓存的间隔。日志级别为 INFO 时，这个间隔决定了「vfs cache: cleaned」报告刷屏的频率，嫌吵就调大或把日志级别改成 NOTICE")

-- ============================ 并发与重试 ============================
s = m:section(NamedSection, "network", "network", translate("并发与重试"))
s.addremove = false
s.anonymous = false

o = s:option(Value, "transfers", translate("并发传输数"))
o.default = "4"
o.datatype = "uinteger"

o = s:option(Value, "checkers", translate("并发检查数"))
o.default = "8"
o.datatype = "uinteger"

o = s:option(Value, "tpslimit", translate("每秒请求上限"))
o.default = "8"
o.datatype = "uinteger"
o.description = translate("网盘最容易在这里被限流。出现大量 429 就往下调")

o = s:option(Value, "tpslimit_burst", translate("突发请求上限"))
o.default = "16"
o.datatype = "uinteger"

o = s:option(Value, "timeout", translate("IO 空闲超时"))
o.default = "5m"
o.description = translate("不是总时长。设太短网络一抖就断连重来，反而更慢")

o = s:option(Value, "retries", translate("整体重试次数"))
o.default = "3"
o.datatype = "uinteger"

o = s:option(Value, "retries_sleep", translate("重试间隔"))
o.default = "3s"
o.description = translate("避免失败后疯狂重试把自己打进限流名单")

o = s:option(Value, "low_level_retries", translate("底层重试次数"))
o.default = "10"
o.datatype = "uinteger"

o = s:option(ListValue, "log_level", translate("日志级别"))
o.default = "INFO"
o:value("DEBUG")
o:value("INFO")
o:value("NOTICE")
o:value("ERROR")
o.description = translate("DEBUG 会产生海量日志，只在排障时临时开")

-- ============================ 挂载选项 ============================
s = m:section(NamedSection, "mountopts", "mountopts", translate("挂载选项"))
s.addremove = false
s.anonymous = false

o = s:option(Flag, "read_only", translate("只读挂载"))
o.default = "1"
o.description = translate("省掉大量写入探测，也防止 Jellyfin 误删网盘文件")

o = s:option(Flag, "allow_other", translate("允许其他用户访问"))
o.default = "1"
o.description = translate("Jellyfin 与 rclone 不是同一用户时必须开启，否则读不到文件")

o = s:option(Flag, "allow_non_empty", translate("允许挂载到非空目录"))
o.default = "1"

o = s:option(Flag, "use_mmap", translate("使用 mmap"))
o.default = "1"

o = s:option(Flag, "no_referer", translate("清空 Referer 头"))
o.default = "1"
o.description = translate("配合 OpenList 的 302 重定向策略绕过直链防盗链；用本地代理时可关")

-- ============================ Jellyfin ============================
s = m:section(NamedSection, "jellyfin", "jellyfin", translate("Jellyfin 集成"))
s.addremove = false
s.anonymous = false

o = s:option(Flag, "enabled", translate("启用"))
o.default = "1"

o = s:option(Value, "container", translate("容器名称"))
o.default = "jellyfin"
o.description = translate("docker ps 里看到的容器名；Jellyfin 不是跑在 Docker 里就留空")

o = s:option(Flag, "restart_after_mount", translate("挂载后重启容器"))
o.default = "1"
o.description = translate("容器通常比本脚本更早启动，绑的是挂载前的旧实例。不重启的话容器内访问网盘会报 Transport endpoint is not connected")

return m
