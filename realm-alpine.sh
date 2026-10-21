#!/bin/sh

# EZrealm Alpine edition. Requires Alpine Linux and root privileges.
set -u

VERSION="1.1.0"
REALM_DIR="/etc/realm"
REALM_BIN="$REALM_DIR/realm"
CONFIG_FILE="$REALM_DIR/config.toml"
INIT_FILE="/etc/init.d/realm"
LOG_FILE="/var/log/realm-manager.log"
RELEASE_API="https://api.github.com/repos/zhboner/realm/releases/latest"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

die() { printf '%b\n' "${RED}错误：$*${NC}" >&2; exit 1; }
info() { printf '%b\n' "${BLUE}$*${NC}"; }
ok() { printf '%b\n' "${GREEN}$*${NC}"; }
warn() { printf '%b\n' "${YELLOW}$*${NC}"; }
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

require_root() { [ "$(id -u)" -eq 0 ] || die "请使用 root 运行此脚本。"; }

ensure_dependencies() {
    command -v apk >/dev/null 2>&1 || die "当前系统不是 Alpine Linux（找不到 apk）。"
    mkdir -p "$REALM_DIR"
    touch "$LOG_FILE" || die "无法写入 $LOG_FILE。"
    command -v rc-service >/dev/null 2>&1 || die "找不到 OpenRC，请先执行 apk add openrc。"
    command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 && return 0
    info "正在安装 curl 和 tar..."
    apk add --no-cache curl tar gzip >/dev/null || die "依赖安装失败，请先执行 apk update。"
}

arch_target() {
    case "$(uname -m)" in
        x86_64|amd64) printf '%s' 'x86_64-unknown-linux-musl' ;;
        aarch64|arm64) printf '%s' 'aarch64-unknown-linux-musl' ;;
        armv7l|armv7) printf '%s' 'armv7-unknown-linux-musleabihf' ;;
        armv6l|armv6) die "Realm 官方没有提供 Alpine 可用的 ARMv6 musl 构建。" ;;
        *) die "不支持的 CPU 架构：$(uname -m)" ;;
    esac
}

latest_version() {
    curl -fsSL --connect-timeout 15 --max-time 60 "$RELEASE_API" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\([0-9][0-9.]*\)".*/\1/p' | head -n 1
}

write_init() {
    cat > "$INIT_FILE" <<EOF
#!/sbin/openrc-run
name="realm"
description="Realm proxy service"
command="$REALM_BIN"
command_args="-c $CONFIG_FILE"
command_user="root"
command_background="yes"
pidfile="/run/realm.pid"
output_log="$LOG_FILE"
error_log="$LOG_FILE"
depend() {
    need net
    after firewall
}
start_pre() {
    if ! grep -q '^[[:space:]]*\\[\\[endpoints\\]\\]' "$CONFIG_FILE"; then
        eerror "No forwarding rules configured; add a rule using EZrealm first."
        return 1
    fi
}
EOF
    chmod 755 "$INIT_FILE"
}

install_realm() (
    ensure_dependencies
    target=$(arch_target) || exit 1
    version=$(latest_version || true)
    [ -n "$version" ] || version="2.7.0"
    url="https://github.com/zhboner/realm/releases/download/v$version/realm-$target.tar.gz"
    tmp=$(mktemp -d) || exit 1
    trap 'rm -rf "$tmp"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    info "下载 Realm v$version（$target）..."
    curl -fL --connect-timeout 15 --max-time 300 --retry 3 -o "$tmp/realm.tar.gz" "$url" || die "下载失败：$url"
    tar -xzf "$tmp/realm.tar.gz" -C "$tmp" || die "Realm 压缩包解压失败。"
    [ -f "$tmp/realm" ] || die "下载包中没有 realm 可执行文件。"
    chmod 755 "$tmp/realm" || exit 1
    "$tmp/realm" --version || die "下载的 Realm 无法在当前系统执行。"
    was_running=false
    rc-service realm status >/dev/null 2>&1 && was_running=true
    cp "$tmp/realm" "$REALM_BIN.new" || exit 1
    if $was_running; then
        rc-service realm stop || { rm -f "$REALM_BIN.new"; exit 1; }
    fi
    [ ! -f "$REALM_BIN" ] || cp -p "$REALM_BIN" "$REALM_BIN.previous" || exit 1
    mv -f "$REALM_BIN.new" "$REALM_BIN" || exit 1
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<'EOF'
[network]
no_tcp = false
use_udp = true
EOF
    fi
    write_init
    if has_rules; then
        rc-update add realm default || exit 1
    else
        warn '请先添加转发规则；添加成功后会启动服务并启用开机自启。'
    fi
    if $was_running && ! service_action start; then
        warn '新版本启动失败，恢复之前的二进制。'
        rc-service realm stop >/dev/null 2>&1 || true
        mv -f "$REALM_BIN.previous" "$REALM_BIN" || exit 1
        service_action start
        exit 1
    fi
    ok "Realm v$version 安装完成。"
    log "installed realm v$version for $target"
)

has_rules() { grep -q '^[[:space:]]*\[\[endpoints\]\]' "$CONFIG_FILE" 2>/dev/null; }

service_action() {
    action=$1
    [ -x "$INIT_FILE" ] || { warn "Realm 尚未安装。"; return 1; }
    if [ "$action" = start ] || [ "$action" = restart ]; then
        if ! has_rules; then
            warn "当前没有转发规则，Realm 无法启动。请先选择 2 添加转发规则。"
            return 1
        fi
    fi
    case "$action" in
        start) rc-service realm start && sleep 1 && rc-service realm status ;;
        stop) rc-service realm stop ;;
        restart) rc-service realm restart && sleep 1 && rc-service realm status ;;
        status) rc-service realm status ;;
    esac
}

valid_port() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null; }
valid_host() { case "$1" in ''|*[!a-zA-Z0-9:.-]*) return 1 ;; esac; return 0; }

valid_address() {
    case "$1" in
        \[*\]:*) address_host=${1%:*}; address_host=${address_host#\[}; address_host=${address_host%\]} ;;
        *:*) address_host=${1%:*}; case "$address_host" in *:*) return 1 ;; esac ;;
        *) return 1 ;;
    esac
    valid_host "$address_host" && valid_port "${1##*:}"
}

apply_rules() {
    if has_rules; then
        rc-update add realm default && service_action restart
    else
        if rc-service realm status >/dev/null 2>&1; then
            rc-service realm stop || return 1
        fi
        rc-update del realm default
    fi
}

commit_rules() {
    cp -p "$CONFIG_FILE" "$CONFIG_FILE.bak" || return 1
    mv -f "$CONFIG_FILE.tmp" "$CONFIG_FILE" || return 1
    if apply_rules; then
        return 0
    fi
    warn '应用规则失败，正在恢复原配置。请查看日志排查端口占用或配置错误。'
    cp -p "$CONFIG_FILE.bak" "$CONFIG_FILE" || return 1
    apply_rules || true
    return 1
}

add_rule() {
    [ -f "$CONFIG_FILE" ] || { warn "请先安装 Realm。"; return; }
    while :; do
        printf '本地监听端口（q 返回）：'; read -r local_port || return 0
        [ "$local_port" = q ] && return 0
        valid_port "$local_port" || { warn "端口必须是 1-65535 的数字。"; continue; }
        printf '目标服务器 IP/域名：'; read -r remote_host || return 0
        valid_host "$remote_host" || { warn "目标地址格式无效。"; continue; }
        printf '目标端口：'; read -r remote_port || return 0
        valid_port "$remote_port" || { warn "端口必须是 1-65535 的数字。"; continue; }
        printf '备注（可选）：'; read -r remark || return 0
        printf '监听模式 [1 双栈 / 2 IPv4 / 3 自定义]（默认 1）：'; read -r mode || return 0
        mode=${mode:-1}
        case "$mode" in
            1) listen='[::]:'"$local_port" ;;
            2) listen='0.0.0.0:'"$local_port" ;;
            3) printf '完整监听地址：'; read -r listen || return 0
               valid_address "$listen" || { warn '监听地址格式无效。'; continue; } ;;
            *) warn '无效选项。'; continue ;;
        esac
        # Escape TOML-sensitive characters in user supplied strings.
        safe_remark=$(printf '%s' "$remark" | sed 's/["\\]/\\&/g')
        safe_host=$(printf '%s' "$remote_host" | sed 's/["\\]/\\&/g')
        case "$safe_host" in *:*) safe_host="[$safe_host]" ;; esac
        if awk -v addr="$listen" '/^[[:space:]]*listen[[:space:]]*=/ { sub(/^[^"]*"/, ""); sub(/".*$/, ""); if ($0 == addr) found=1 } END { exit !found }' "$CONFIG_FILE"; then
            warn '该监听地址已存在。'; continue
        fi
        cp -p "$CONFIG_FILE" "$CONFIG_FILE.tmp" || return 1
        {
            printf '\n[[endpoints]]\n# 备注: %s\nlisten = "%s"\nremote = "%s:%s"\n' "$safe_remark" "$listen" "$safe_host" "$remote_port"
        } >> "$CONFIG_FILE.tmp"
        commit_rules || return 1
        ok '转发规则已添加。'
        log "added rule $listen -> $remote_host:$remote_port"
        printf '继续添加？[y/N]：'; read -r answer || return 0
        [ "$answer" = y ] || [ "$answer" = Y ] || return 0
    done
}

show_rules() {
    [ -f "$CONFIG_FILE" ] || { warn '配置文件不存在。'; return; }
    awk '
        /^\[\[endpoints\]\]/{ if (listen != "") { n++; printf "%d. %s -> %s%s\n", n, listen, remote, remark }; listen=""; remote=""; remark="" }
        /^# 备注:/{ sub(/^# 备注:[[:space:]]*/, ""); remark="  (" $0 ")" }
        /^listen[[:space:]]*=/{ sub(/^[^"]*"/, ""); sub(/".*$/, ""); listen=$0 }
        /^remote[[:space:]]*=/{ sub(/^[^"]*"/, ""); sub(/".*$/, ""); remote=$0 }
        END { if (listen != "") { n++; printf "%d. %s -> %s%s\n", n, listen, remote, remark }; if (n == 0) print "没有发现转发规则。" }
    ' "$CONFIG_FILE"
}

delete_rule() {
    [ -f "$CONFIG_FILE" ] || { warn '配置文件不存在。'; return; }
    show_rules
    printf '输入要删除的规则序号（回车返回）：'; read -r choice || return 0
    [ -z "$choice" ] && return
    case "$choice" in ''|*[!0-9]*) warn '请输入数字。'; return ;; esac
    count=$(grep -c '^\[\[endpoints\]\]' "$CONFIG_FILE")
    [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$count" ] 2>/dev/null || { warn '规则序号超出范围。'; return 1; }
    awk -v wanted="$choice" '
        /^\[\[endpoints\]\]/{ n++; if (n == wanted) skip=1; else skip=0 }
        /^\[/ && !/^\[\[endpoints\]\]/ && !/^\[endpoints\./ { skip=0 }
        !skip { print }
    ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" || return 1
    commit_rules || return 1
    ok '规则已删除。'
}

cron_manage() {
    file=/etc/crontabs/root
    touch "$file"
    printf '1. 每日指定时间重启\n2. 删除 Realm 定时任务\n3. 查看 Realm 定时任务\n选择：'; read -r choice || return 0
    case "$choice" in
        1) printf '小时（0-23）：'; read -r hour || return 0
           case "$hour" in ''|*[!0-9]*) warn '小时无效。'; return ;; esac
           [ "$hour" -le 23 ] || { warn '小时必须为 0-23。'; return; }
           sed -i '/# ezrealm-restart$/d' "$file"
           printf '0 %s * * * /sbin/rc-service realm restart # ezrealm-restart\n' "$hour" >> "$file"
           rc-update add crond default && rc-service crond restart || return 1
           ok '定时任务已设置。' ;;
        2) sed -i '/# ezrealm-restart$/d' "$file"; ok '定时任务已删除。' ;;
        3) grep '# ezrealm-restart$' "$file" || printf '没有 Realm 定时任务。\n' ;;
        *) warn '无效选项。' ;;
    esac
}

uninstall() {
    if rc-service realm status >/dev/null 2>&1; then
        service_action stop || return 1
    fi
    rc-update del realm default >/dev/null 2>&1 || true
    rm -f "$INIT_FILE"
    sed -i '/# ezrealm-restart$/d' /etc/crontabs/root 2>/dev/null || true
    rm -rf "$REALM_DIR"
    ok 'Realm 已卸载。配置和二进制文件已删除。'
    log 'uninstalled realm'
}

menu() {
    while :; do
        clear 2>/dev/null || true
        printf '%b\n' "${YELLOW}EZrealm Alpine v$VERSION${NC}"
        printf '安装状态：%s\n' "$([ -x "$REALM_BIN" ] && printf '已安装' || printf '未安装')"
        printf '服务状态：'; if rc-service realm status >/dev/null 2>&1; then printf '运行中\n'; else printf '未运行\n'; fi
        printf '\n1. 安装/更新 Realm\n2. 添加转发规则\n3. 查看转发规则\n4. 删除转发规则\n5. 启动服务\n6. 停止服务\n7. 重启服务\n8. 定时任务管理\n9. 查看日志\n10. 完全卸载\n0. 退出\n选择：'
        read -r choice || return 0
        case "$choice" in
            1) install_realm ;; 2) add_rule ;; 3) show_rules ;; 4) delete_rule ;;
            5) service_action start ;; 6) service_action stop ;; 7) service_action restart ;;
            8) cron_manage ;; 9) tail -n 20 "$LOG_FILE" 2>/dev/null || true ;;
            10) printf '确认卸载？[y/N]：'; read -r confirm || return 0; [ "$confirm" = y ] && uninstall ;;
            0) exit 0 ;; *) warn '无效选项。' ;;
        esac
        printf '\n按回车继续...'; read -r _ || return 0
    done
}

if [ "${EZREALM_SOURCE_ONLY:-0}" != 1 ]; then
    require_root
    ensure_dependencies
    menu
fi
