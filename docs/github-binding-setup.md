# GitHub 账号绑定配置

服务器端已支持随机且一次性的授权状态、PKCE 校验、十分钟授权有效期和 GitHub ID 唯一绑定。客户端登录泥土豆账号后，从账号设置发起绑定，授权在系统浏览器中完成。

在 https://github.com/settings/applications/new 创建 OAuth App：

| 字段 | 值 |
| --- | --- |
| Application name | 泥土豆 NeedTODO |
| Homepage URL | https://api.whatineedtodotoday.xyz |
| Redirect URI | https://api.whatineedtodotoday.xyz/v2/github/callback |

不启用通配符匹配，不启用 Device Flow，保留访问令牌过期选项。注册后生成 Client Secret。

凭据仅配置在服务器 `/etc/needtodo.env` 中，文件由 root 所有、权限 600；不得放进客户端、构建参数或仓库。需要的变量为 `GITHUB_CLIENT_ID`、`GITHUB_CLIENT_SECRET`、`PUBLIC_URL=https://api.whatineedtodotoday.xyz`。更新配置后重启 needtodo 服务，真实账号在软件中完成一次授权后才能确认端到端绑定成功。

此功能绑定已有泥土豆账号，不改变日程所属 UID。服务不保留 GitHub 访问令牌；绑定时只读取账号身份，不申请仓库权限。

参考：[创建 OAuth 应用](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)、[OAuth 授权与 PKCE](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps)。
