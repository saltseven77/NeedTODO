# 低内存 Linux 部署

适用于 systemd 的 Linux 服务器；在 Alibaba Cloud Linux 3、x86_64、约 409MiB 内存环境完成实际部署验证。使用 Node.js 24 和 Caddy，不依赖 Docker、npm 包或 MySQL。

文件布局：

- `/opt/needtodo/index.mjs`、`backup.mjs`、`package.json`：服务代码。
- `/opt/needtodo/node/bin/node`：Node.js 官方预编译运行时。
- `/etc/needtodo.env`：环境配置，权限 `600`。
- `/var/lib/needtodo/needtodo.sqlite`：持久化数据库，仅 `needtodo` 用户可访问。
- `/var/lib/needtodo/backups/`：在线数据库备份。
- `/etc/caddy/Caddyfile`：HTTPS 代理配置，本目录的模板使用回环地址连接 API。

创建系统用户 `needtodo`，将本目录中的 `needtodo.service`、`needtodo-backup.service`、`needtodo-backup.timer` 放到 `/etc/systemd/system/`，确认 Node.js 的路径正确。Caddy 按其[官方 systemd 部署说明](https://caddyserver.com/docs/running)安装，并使用此目录中的 Caddyfile。更换域名时修改 Caddyfile 和环境配置。

环境配置：

```text
HOST=127.0.0.1
PORT=8787
DATABASE=/var/lib/needtodo/needtodo.sqlite
PUBLIC_URL=https://api.whatineedtodotoday.xyz
TRUST_PROXY=true
TZ=Asia/Shanghai
```

API 仅监听 `127.0.0.1:8787`，Caddy 覆盖来源 IP 头后代理到此端口。对公网开放 Caddy 的 80、443 端口。域名必须在公共 DNS 正常解析后才能签发可信 HTTPS 证书；只在 DNS 管理平台显示记录完成不代表全球解析已生效。

启动顺序：

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now needtodo.service caddy.service
curl --fail http://127.0.0.1:8787/health
sudo systemctl enable --now needtodo-backup.timer
sudo systemctl start needtodo-backup.service
curl --fail https://api.whatineedtodotoday.xyz/health
```

备份安排在北京时间每天 03:30 后五分钟内执行，补偿机器关机期间错过的执行。成功备份后自动清理超过七天、文件名符合自动备份格式的旧备份，避免占满磁盘。备份服务只在数据库已创建时启动，避免首次安装的启动竞态。不要只复制运行中的 SQLite 主文件；使用 `backup.mjs` 生成的完整备份，并另存到服务器之外。

API 设置 96MiB 的 JavaScript 堆、单个密码计算线程及 256MiB 服务内存上限，用于降低小内存机器的峰值占用；这些配置并不代表可承载大量并发用户。可按实际负载调整。为小内存实例配置适量交换空间，可缓解短时峰值。

检查状态：`systemctl status needtodo caddy`、`systemctl list-timers needtodo-backup.timer`。查看错误：`journalctl -u needtodo -u caddy --no-pager -n 50`。客户端需要配置对应的 HTTPS 服务地址并重新构建，才能使用账号功能。
