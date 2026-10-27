--[[
LuCI - Lua Configuration Interface
Rclone 网盘挂载：运行状态 / 参数配置 / 刷新、重挂、卸载动作
]]--

module("luci.controller.rclonemount", package.seeall)

local util = require "luci.util"
local http = require "luci.http"
local dsp  = require "luci.dispatcher"

local CTRL = "/usr/bin/rclonemount"
local UCI  = "rclonemount"

-- gsub 会返回 (结果串, 替换次数) 两个值，必须用外层括号截断成单值，
-- 否则在 tonumber(sh(...)) 这类调用里第二个返回值会被当成进制基数。
local function sh(cmd)
	return ((util.exec(cmd) or ""):gsub("^%s*(.-)%s*$", "%1"))
end

local function uci_get(section, option, default)
	local c = require("luci.model.uci").cursor()
	local v = c:get(UCI, section, option)
	if v == nil or v == "" then return default end
	return v
end

local function human_secs(s)
	if not s or s < 0 then return "-" end
	return string.format("%d天%d小时%d分",
		math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60))
end

local function collect()
	local d = {}

	-- 先取配置，状态采集要用配置的路径
	d.remote     = uci_get("main", "remote", "alist:")
	d.mountpoint = uci_get("main", "mountpoint", "/mnt/nvme0n1p5/Alist")
	d.cachedir   = uci_get("main", "cachedir", "/mnt/nvme0n1p5/Caches/Rclone")
	d.logfile    = uci_get("main", "logfile", "/mnt/nvme0n1p5/Logs/rclone-alist.log")
	d.alist_url  = uci_get("main", "alist_url", "http://127.0.0.1:5244")
	d.wdurl      = uci_get("webdav", "url", "-")
	d.wdsync     = uci_get("webdav", "sync", "0")
	d.cachemax   = uci_get("cache", "max_size", "20G")
	d.dircache   = uci_get("cache", "dir_cache_time", "72h")
	d.tpslimit   = uci_get("network", "tpslimit", "8")
	d.jf_on      = uci_get("jellyfin", "enabled", "0")
	d.jf_cont    = uci_get("jellyfin", "container", "")
	d.enabled    = uci_get("main", "enabled", "1")

	-- 直接读 /proc/mounts，不依赖 mount 命令（LuCI 执行环境 PATH 未必齐全）
	local line = sh([[awk '$2=="]] .. d.mountpoint .. [["{print $3"|"$4; exit}' /proc/mounts 2>/dev/null]])
	d.mounted, d.fstype, d.opts = false, "-", ""
	if line ~= "" then
		local ft, op = line:match("^(.-)|(.*)$")
		if ft then
			d.mounted = true
			d.fstype  = (ft ~= "") and ft or "-"
			d.opts    = op or ""
		end
	end
	d.ro         = (d.opts:match("^ro,") ~= nil) or (d.opts:match(",ro,") ~= nil) or (d.opts:match(",ro$") ~= nil)
	d.allowother = d.opts:match("allow_other") ~= nil

	d.pid = sh([[cat /var/run/rclonemount.pid 2>/dev/null | tr -d '\n']])
	if not d.pid:match("^%d+$") then d.pid = "" end
	if d.pid ~= "" then
		local up = tonumber(sh([[awk '{printf "%d", $1}' /proc/uptime 2>/dev/null]]))
		local st = tonumber(sh([[awk '{printf "%d", $22}' /proc/]] .. d.pid .. [[/stat 2>/dev/null]]))
		if up and st then
			d.runtime = human_secs(up - math.floor(st / 100))
		else
			d.runtime = "-"
		end
		d.mem = sh([[awk '/VmRSS/{printf "%d MB", $2/1024}' /proc/]] .. d.pid .. [[/status 2>/dev/null]])
		if d.mem == "" then d.mem = "-" end
	else
		d.runtime, d.mem = "-", "-"
	end

	d.cache = sh([[du -sh ]] .. d.cachedir .. [[ 2>/dev/null | awk '{print $1}']])
	if d.cache == "" then d.cache = "-" end
	-- 对挂载点本身 df 会量到 rclone 挂载（1.0P），必须用物理分区上的路径
	d.diskfree = sh([[df -h ]] .. d.cachedir .. [[ 2>/dev/null | tail -1 | awk '{print $4 " / " $2}']])
	d.logsize  = sh([[ls -lh ]] .. d.logfile .. [[ 2>/dev/null | awk '{print $5}']])
	d.logupd   = sh([[date -r ]] .. d.logfile .. [[ '+%m-%d %H:%M' 2>/dev/null]])
	d.openlist = sh([[pgrep -f 'openlist server' >/dev/null 2>&1 && echo 在线 || echo 未运行]])
	d.jellyfin = sh([[docker ps --format '{{.Names}}|{{.Status}}' 2>/dev/null | grep '^jellyfin|' | cut -d'|' -f2]])
	if d.jellyfin == "" then d.jellyfin = "未运行" end
	d.topdirs  = sh([[ls -1 ]] .. d.mountpoint .. [[ 2>/dev/null | tr '\n' ' ']])
	if d.topdirs == "" then d.topdirs = "-" end
	d.logtail  = util.exec([[tail -6 ]] .. d.logfile .. [[ 2>/dev/null]])
	d.cron     = (sh([[grep -c 'rclonemount' /etc/crontabs/root 2>/dev/null]]) ~= "0")

	return d
end

function index()
	local page = node("admin", "status", "rclonemount")
	page.target   = firstchild()
	page.title    = _("网盘挂载")
	page.order    = 60
	page.dependent = true

	entry({"admin", "status", "rclonemount", "status"},
		call("action_status"), _("运行状态"), 10).leaf = true
	entry({"admin", "status", "rclonemount", "config"},
		cbi("rclonemount"), _("配置"), 20).leaf = true

	entry({"admin", "status", "rclonemount", "refresh"},  post("action_refresh")).leaf  = true
	entry({"admin", "status", "rclonemount", "remount"},  post("action_remount")).leaf  = true
	entry({"admin", "status", "rclonemount", "umount"},   post("action_umount")).leaf   = true
	entry({"admin", "status", "rclonemount", "jellyfin"}, post("action_jellyfin")).leaf = true
end

local function back()
	http.redirect(dsp.build_url("admin/status/rclonemount/status"))
end

function action_status()
	luci.template.render("rclonemount/status", {
		info  = collect(),
		token = dsp.context.authtoken or ""
	})
end

function action_refresh()
	util.exec(CTRL .. " refresh 2>/dev/null")
	back()
end

function action_remount()
	util.exec(CTRL .. " restart >/dev/null 2>&1 &")
	back()
end

function action_umount()
	util.exec(CTRL .. " stop 2>/dev/null")
	back()
end

function action_jellyfin()
	local c = uci_get("jellyfin", "container", "jellyfin")
	if c ~= "" then
		util.exec("docker restart " .. c .. " >/dev/null 2>&1 &")
	end
	back()
end
