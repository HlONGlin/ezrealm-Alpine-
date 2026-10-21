#!/bin/sh
# Regression checks with isolated configuration and mocked OpenRC commands.
set -eu
cd "$(dirname "$0")/.."
EZREALM_SOURCE_ONLY=1
export EZREALM_SOURCE_ONLY
. ./realm-alpine.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
CONFIG_FILE="$work/config.toml"
LOG_FILE="$work/manager.log"
INIT_FILE="$work/init"
printf '#!/bin/sh\n' > "$INIT_FILE"
chmod +x "$INIT_FILE"
rc-service() { printf '%s\n' "$*" >> "$work/service.calls"; }
rc-update() { printf '%s\n' "$*" >> "$work/update.calls"; }
sleep() { :; }
cat > "$CONFIG_FILE" <<'EOF'
[network]
no_tcp = false
use_udp = true
EOF
if service_action start; then
    printf 'FAIL: empty configuration was started\n' >&2; exit 1
fi
[ ! -f "$work/service.calls" ]
valid_address '[::1]:443'
valid_address '127.0.0.1:65535'
if valid_address '::1:443' || valid_address '127.0.0.1:65536' || valid_address 'bad"host:80'; then
    printf 'FAIL: invalid address accepted\n' >&2; exit 1
fi
add_rule <<'EOF'
1443
2001:db8::1
443
IPv6 test


n
EOF
grep -F 'remote = "[2001:db8::1]:443"' "$CONFIG_FILE"
grep -F '[endpoints.network]' "$CONFIG_FILE"
grep -F 'use_udp = false' "$CONFIG_FILE"
show_rules | grep -F '1. 0.0.0.0:1443 -> [2001:db8::1]:443'
cp "$CONFIG_FILE" "$work/original"
# A restart failure must restore the exact original configuration.
rc-service() { [ "$2" != restart ]; }
cp "$CONFIG_FILE" "$CONFIG_FILE.tmp"
printf '\n# candidate\n' >> "$CONFIG_FILE.tmp"
if commit_rules; then
    printf 'FAIL: restart failure ignored\n' >&2; exit 1
fi
cmp "$CONFIG_FILE" "$work/original"
rc-service() { printf '%s\n' "$*" >> "$work/service.calls"; }
# An out-of-range deletion must not change the configuration.
if delete_rule <<'EOF'
99
EOF
then
    printf 'FAIL: out-of-range rule deleted\n' >&2; exit 1
fi
cmp "$CONFIG_FILE" "$work/original"
delete_rule <<'EOF'
1
EOF
if has_rules; then
    printf 'FAIL: last rule still present\n' >&2; exit 1
fi
if grep -F '[endpoints.network]' "$CONFIG_FILE"; then
    printf 'FAIL: deleted rule network settings still present\n' >&2; exit 1
fi
grep -F 'realm stop' "$work/service.calls"
grep -F 'del realm default' "$work/update.calls"
# The generated OpenRC script must also pass shell syntax checking.
REALM_BIN="$work/realm"
write_init
sh -n "$INIT_FILE"
grep -F 'export TOKIO_WORKER_THREADS="${TOKIO_WORKER_THREADS:-1}"' "$INIT_FILE"
printf 'All rule regression checks passed.\n'
