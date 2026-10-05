# 账号服务

Node.js 22.16+（推荐 24），无需 npm 依赖。SQLite 保存账号和日程，密码使用随机盐 + scrypt，令牌只保存摘要。

密码使用 scrypt 的 32MiB 工作参数，旧账号成功登录时自动升级哈希。每个 IP 的注册／登录及单个账号的登录均限流，密码计算并发受限。删除任务仅保留必要同步标记。安全检查结果与当前隐私边界见 [安全检查说明](../docs/security-review.md)。

## 当前状态

账号公网服务已部署在 `https://api.whatineedtodotoday.xyz`，客户端默认连接此地址，GitHub 绑定和账号找回已启用。自部署者需要自行配置 OAuth 应用凭据。

## 公网部署

小内存 Linux 实例也可采用 [systemd 部署](linux/README.md)，直接运行 Node.js 和 Caddy。

准备一台可长期运行 Docker Engine 和 Docker Compose 的 Linux 服务器，以及持久化磁盘。SQLite 方案部署一个 API 实例即可。

1. 在域名管理平台新增 `api` 的 A 记录，指向服务器公网 IPv4。只有服务器确实提供 IPv6 时才添加 AAAA 记录。此配置使用直接 DNS 解析；若启用 CDN 代理，需要另行配置真实客户端 IP 的信任范围。
2. 允许服务器公网访问 TCP 80、443。API 的 8787 端口只在容器网络内使用，不映射到公网。
3. 将项目放到服务器，进入 `server`，执行：

```sh
cp .env.example .env
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d --build
docker compose ps
curl --fail https://api.whatineedtodotoday.xyz/health
```

健康接口应返回 `{"ok":true,"version":2}`。Caddy 自动申请和续期 HTTPS 证书；前提是 DNS 已生效、80/443 可达。账号数据库和证书分别保存在 Docker 持久化卷中，容器重建不会清空账号和日程。不要使用 `docker compose down -v` 删除这些卷。

`DOMAIN` 控制公网域名，Compose 会根据它生成 `PUBLIC_URL`。Compose 中 `TRUST_PROXY=true` 配合 Caddy 覆盖来源 IP 头使用，避免所有用户共用代理 IP 的登录限额；脱离此私有代理直接运行时应保持 `TRUST_PROXY=false`，防止来源伪造。

更新服务：在服务器取得更新后的代码，进入 `server`，再次执行 `docker compose --env-file .env up -d --build`。查看日志：`docker compose logs --tail=100 api caddy`。不要把 `.env` 或数据库上传到仓库。

## 备份

无需停机，使用 SQLite backup API 创建一致的备份（包含已提交到 WAL 的数据）：

```sh
docker compose exec -T api node backup.mjs /data/backups/account.sqlite
mkdir -p backups
docker compose cp api:/data/backups/account.sqlite ./backups/account.sqlite
```

每次使用新的文件名，例如带日期的 `account-2026-10-01.sqlite`；脚本拒绝覆盖现有文件。把备份另存到服务器之外。备份包含账号凭据摘要和用户数据，请限制访问。

恢复时先停 API，保留原数据库及其 `-wal`、`-shm` 文件，把备份复制到数据卷的 `/data/needtodo.sqlite`，清除旧的同名 WAL/SHM，确认文件归容器 `node` 用户可写后再启动 API。不可在运行中的数据库上直接替换主文件。

## 客户端接入

客户端默认服务地址为：

```text
https://api.whatineedtodotoday.xyz
```

自部署时可把 GitHub 仓库 Actions 变量 `NEEDTODO_API_URL` 设为自己的 HTTPS 地址，并重新构建客户端；也可以使用 `--dart-define=NEEDTODO_API_URL=https://你的服务地址`。仅修改服务器不会更改客户端已编译的地址。令牌和 OAuth 密钥不得写入构建参数。

## 本地运行

```sh
cp .env.example .env
npm start
```

账号密码登录无需 GitHub 配置。绑定 GitHub 时，填写 `GITHUB_CLIENT_ID`、`GITHUB_CLIENT_SECRET`、`PUBLIC_URL`，OAuth 回调为 `PUBLIC_URL/v2/github/callback`。授权在系统浏览器完成；手机与电脑通过已登录会话查询绑定结果，不在 URL 中传登录令牌。

服务使用 `/v2` 协议，与旧版示例 `/v1` 独立：账号隔离、版本冲突检测、任务删除墓碑、GitHub 一对一绑定。未绑定 GitHub 时同步接口拒绝读取和写入；已有云端副本保留。GitHub 绑定不是直接登录方式。

找回账号：客户端调用 `POST /v2/github/recover`，在浏览器使用已绑定 GitHub 验证身份，通过 `POST /v2/github/recovery-status` 查询结果，再用一次性票据调用 `POST /v2/auth/reset` 设置新密码。找回流程同样使用 PKCE 与一次性 state，票据十分钟过期，服务器只存票据摘要。更新密码撤销该账号所有旧会话，保持账号 ID 与已有数据不变。尚无邮箱验证和运营管理界面。

验证：`node --test test.mjs`。测试使用内存数据库和模拟 GitHub 响应，不会请求真实账号。
