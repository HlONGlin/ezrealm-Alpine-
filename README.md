# ezrealm-Alpine

基于 [EZrealm](https://github.com/qqrrooty/EZrealm) 的 Alpine Linux 版本，使用 OpenRC 管理 Realm 服务，不依赖 `systemd`。

## 一键安装与管理

在 Alpine Linux 上以 root 执行以下命令：

```sh
apk add --no-cache curl && curl -fsSL https://raw.githubusercontent.com/HlONGlin/ezrealm-Alpine-/main/one-click.sh -o /tmp/ezrealm-one-click.sh && sh /tmp/ezrealm-one-click.sh
```

如果已经安装了 Bash 和 curl，也可以使用进程替换方式：

```bash
bash <(curl -fsSL https://github.com/HlONGlin/ezrealm-Alpine-/raw/main/one-click.sh)
```

脚本会自动下载并启动本仓库的 Realm 管理菜单。默认 Alpine 使用 `/bin/sh`，无需安装 Bash。重复执行以上命令即可获取最新管理脚本。

也可以手动下载后执行：

```sh
curl -fsSL https://raw.githubusercontent.com/HlONGlin/ezrealm-Alpine-/main/one-click.sh -o one-click.sh
chmod +x one-click.sh
./one-click.sh
```

脚本会自动完成以下工作：

- 根据 `x86_64`、`aarch64` 或 ARMv7 架构下载 Realm 的 musl 版本
- 将 Realm 安装到 `/etc/realm/realm`
- 使用 OpenRC 服务 `/etc/init.d/realm`
- 管理 `/etc/realm/config.toml` 中的转发规则
- 使用 Alpine crond 管理每日重启任务
- 支持安装、更新、启动、停止、重启、查看日志和卸载

首次运行后，选择“安装/更新 Realm”，再选择“添加转发规则”。添加成功后会自动启动服务并启用开机自启。没有规则时不会启动 Realm；删除最后一条规则时会停止服务并取消开机自启。

规则变更前会备份到 `/etc/realm/config.toml.bak`。应用失败时会恢复原配置并尝试恢复服务，错误输出会直接显示在终端。IPv6 目标请输入 `2001:db8::1`，脚本自动转换为 `[2001:db8::1]:端口`；自定义监听地址需使用 `0.0.0.0:443` 或 `[::]:443` 格式。

更新时会先验证下载的二进制是否可执行，再停止运行中的服务并替换二进制。旧版本保留为 `/etc/realm/realm.previous`；更新后服务启动失败会尝试回退。确保云厂商安全组和 Alpine 防火墙已放行监听端口。

## 排查与验证

```sh
rc-service realm status
tail -n 50 /var/log/realm-manager.log
# 修复配置或端口冲突后重新启动
rc-service realm restart
```

出现 `missing field endpoints` 通常表示尚未添加转发规则，先通过菜单选项 2 添加规则，无需重新安装。

项目自检（在仓库目录执行，使用隔离配置和模拟服务，不操作系统服务）：

```sh
sh -n realm-alpine.sh && sh -n one-click.sh
sh tests/rules.sh
```

## 说明

- 需要 Alpine Linux、root 权限和可访问 GitHub Releases 的网络环境。
- Realm 配置目录为 `/etc/realm`，日志为 `/var/log/realm-manager.log`。
- 如果无法自动检测最新 Realm 版本，脚本会回退到 `v2.7.0`。
