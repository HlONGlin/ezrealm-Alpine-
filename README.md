# ezrealm-Alpine

基于 [EZrealm](https://github.com/qqrrooty/EZrealm) 的 Alpine Linux 版本，使用 OpenRC 管理 Realm 服务，不依赖 `systemd`。

## 一键安装与管理

在 Alpine Linux 上以 root 执行以下命令：

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/HlONGlin/ezrealm-Alpine-/main/one-click.sh)"
```

也可以使用与其他一键脚本一致的 Bash 进程替换方式：

```bash
bash <(curl -fsSL https://github.com/HlONGlin/ezrealm-Alpine-/raw/main/one-click.sh)
```

脚本会自动下载并启动本仓库的 Realm 管理菜单。若系统没有 `curl`，一键脚本会先通过 `apk` 自动安装。

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

首次运行后，选择菜单中的“安装/更新 Realm”，然后选择“启动服务”即可启动 Realm。确保云厂商安全组和 Alpine 防火墙已放行监听端口。

## 说明

- 需要 Alpine Linux、root 权限和可访问 GitHub Releases 的网络环境。
- Realm 配置目录为 `/etc/realm`，日志为 `/var/log/realm-manager.log`。
- 如果无法自动检测最新 Realm 版本，脚本会回退到 `v2.7.0`。
