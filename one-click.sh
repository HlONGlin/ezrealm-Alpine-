#!/bin/sh

# EZrealm Alpine one-click installer and manager.
set -eu

REPO_RAW_URL="https://raw.githubusercontent.com/HlONGlin/ezrealm-Alpine-/main"
SCRIPT_URL="$REPO_RAW_URL/realm-alpine.sh"
TMP_FILE="$(mktemp -t ezrealm-alpine.XXXXXX)"

cleanup() {
    rm -f "$TMP_FILE"
}
trap cleanup EXIT INT TERM

if [ "$(id -u)" -ne 0 ]; then
    printf '%s\n' '错误：请使用 root 权限运行。' >&2
    exit 1
fi

if ! command -v apk >/dev/null 2>&1; then
    printf '%s\n' '错误：此一键脚本仅支持 Alpine Linux。' >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    printf '%s\n' '正在安装 curl...'
    apk add --no-cache curl >/dev/null
fi

printf '正在下载 EZrealm Alpine 管理脚本...\n'
curl -fsSL --retry 3 "$SCRIPT_URL" -o "$TMP_FILE"
chmod 700 "$TMP_FILE"
exec /bin/sh "$TMP_FILE" "$@"
