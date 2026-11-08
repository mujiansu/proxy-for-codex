# Proxy for Codex

让国内 Windows 环境中的 Codex 通过本机已有的 HTTP/HTTPS 代理访问 GPT
远程服务。启用插件后，开始菜单、桌面、任务栏和搜索等普通 Codex 入口都能
使用代理，不需要另建“带代理启动”的快捷方式。

> 本项目只复用已有代理，不提供代理节点或订阅。请自行准备可用的代理服务。

## 安装

在 PowerShell 中通过 Codex 的插件 marketplace 直接安装：

```powershell
codex plugin marketplace add https://github.com/mujiansu/proxy-for-codex.git --sparse .agents/plugins
codex plugin add proxy-for-codex@proxy-for-codex
```

然后打开 Codex，在插件目录中启用 **Proxy for Codex**。不需要克隆仓库，
也不需要单独运行 `npm install`。

首次添加 marketplace 时，Git 需要能访问 GitHub；如果终端直连失败，请先让
Git 使用你已有的代理。

> 安装方式基于 Codex 官方插件 marketplace 机制。若当前版本提供
> “Add Marketplace”，也可以添加同一个 GitHub 仓库地址。

## 配置

1. 打开 **Proxy for Codex** 的插件设置。
2. 分别填写 HTTP 和 HTTPS 代理，例如 `http://127.0.0.1:7897`。
3. 保留本地地址直连，例如 `localhost,127.0.0.1,::1`。
4. 保存设置，然后完整退出并重新打开 Codex。

重新打开后，插件会把这些值写入当前用户的 `HTTP_PROXY`、`HTTPS_PROXY` 和
`NO_PROXY`（同时写入小写形式）。之后从普通 Windows 入口启动的 Codex 会
自动继承代理。

HTTP 和 HTTPS 是独立设置；只修改其中一项不会覆盖另一项。

## 常见问题

### 保存后为什么还没有生效？

已经运行的 Codex 不会重新读取用户环境变量。请从托盘菜单完整退出 Codex，
再重新打开。仅关闭窗口通常不够。

### 能否不使用代理时直接取消？

在插件页清除代理配置，然后完整重启 Codex。禁用插件不会自动删除已写入的
用户环境变量。

### 代理需要认证怎么办？

可以在代理 URL 中填写用户名和密码。插件状态输出和日志会把凭据显示为
`<redacted>`；请勿把
`%USERPROFILE%\.proxy-for-codex\config.json` 提交到仓库或发送给他人。

## 环境要求

- Windows 10/11
- 支持插件的 ChatGPT/Codex 桌面版和 Codex CLI
- 本机可用的 HTTP/HTTPS 代理
- 插件运行时的 Node.js `>= 22.19.0`

## 开发与本地安装

<details>
<summary>展开开发与本地安装步骤</summary>

MCP 运行包已随插件提供。只有修改 `server/server.mjs` 后才需要重新构建：

```powershell
git clone https://github.com/mujiansu/proxy-for-codex.git
cd .\proxy-for-codex\server
npm install
npm run build
cd ..
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
```

仓库自身的 `.agents/plugins/marketplace.json` 可用于本地测试。发布前可运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\pack.ps1
```

</details>

## 工作方式

插件通过 MCP 调用 PowerShell，将代理配置保存到当前 Windows 用户环境。
它不管理代理节点，也不会停止、结束或重启 Codex。配置前会备份原有环境，
清除时只恢复由本插件写入的值。

更详细的状态、安全和架构说明见 [`docs/`](docs/)。

## 许可证

[MIT](LICENSE)
