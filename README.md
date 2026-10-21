# ezrealm-Alpine

基于 [EZrealm](https://github.com/qqrrooty/EZrealm) 的 Alpine Linux 版本，使用 OpenRC 管理 Realm 服务，不依赖 `systemd`。

适用于 Alpine NAT VPS / LXC 容器。管理脚本版本：**v1.2.0**。

## NAT VPS 部署要点

默认监听 **IPv4 `0.0.0.0`**，默认协议为 **TCP**。添加规则时可选择 UDP 或 TCP+UDP，每条规则独立设置协议；已有规则的协议配置保留。

例如面板分配的公网地址为 `203.0.113.10`、外部端口为 `30080`，映射至实例内部端口 `8080`，目标服务为 `example.com:443`：

```text
客户端 → 203.0.113.10:30080 → 面板 TCP 映射 → 实例 0.0.0.0:8080 → example.com:443
```

在菜单选项 2 中填写内部监听端口 `8080`，目标地址 `example.com`，目标端口 `443`。客户端连接公网的 `30080`。如果面板内外端口相同，监听端口就填写该分配端口。

- 映射需在服务商面板创建，协议必须与规则一致；TCP+UDP 需面板同时提供两种协议映射。
- 保留 SSH 使用的内部端口及外部映射，避免将 Realm 绑定到 sshd 正在使用的端口。
- IPv6 双栈监听为可选项，请先确认实例有 IPv6 支持；直通 IPv6 和 NAT IPv6 的访问方式由面板决定。
- `0.0.0.0` 接收 IPv4 NAT 入站；仅绑定 `127.0.0.1` 适用于同实例反代访问。
- 菜单 **11** 显示资源、磁盘/inode、地址路由、监听端口、服务和日志。先查本机，再查面板映射和外部连接。

### 小内存与日志

新生成的 OpenRC 服务默认使用一个 Tokio 工作线程，适合小型容器。如需调整，可在 `/etc/conf.d/realm` 中配置 `TOKIO_WORKER_THREADS=2`，然后重启服务。此设置限制工作线程数，不是内存或连接数硬限制。

安装时配置 logrotate：日志每天检查轮转，单次检查超过 1 MiB 也会轮转，保留 2 份压缩历史。采用 `copytruncate`，无需为轮转重启 Realm；两次检查之间日志仍可能增长。定时检查依赖 Alpine 的 logrotate 周期任务及 crond。

已安装用户选择菜单 **1** 更新即可重新生成服务和日志轮转配置；规则会保留。诊断显示的是容器内部视角，平台流量额度、宿主机 OOM 和公网映射状态请结合服务商面板查看。

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
