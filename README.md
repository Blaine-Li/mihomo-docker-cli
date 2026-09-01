# Mihomo Docker CLI

一个面向 Linux 的轻量级 [Mihomo](https://github.com/MetaCubeX/mihomo) Docker 管理脚本。它负责下载订阅配置、启动临时容器、管理当前 shell 的代理环境变量，以及修改代理和控制 API 端口。

本项目不提供代理节点、订阅服务或网络访问保证，也不隶属于 MetaCubeX。

## 特性

- `clashon`：启动 Mihomo，并为当前及后续 shell 配置代理环境变量
- `clashoff`：停止 Mihomo，并移除 shell 代理环境变量
- `clashctl`：交互式管理订阅、端口、日志和脚本更新
- 使用临时容器（`--rm`），停止后自动删除
- 不设置开机自启，不持久化容器
- 配置和订阅链接保存在用户目录，并限制为仅当前用户可读
- 默认通过镜像源 `docker.gh-proxy.com/metacubex/mihomo` 拉取 Mihomo

## 运行要求

- Linux
- Bash
- [Docker Engine](https://docs.docker.com/engine/install/)，且当前用户能够执行 Docker 命令
- curl、awk、grep
- 使用 TUN 时，主机需要提供 `/dev/net/tun`

脚本使用 host 网络、`NET_ADMIN` capability 和 `/dev/net/tun`。Docker Desktop 并不是当前支持目标；尤其是 macOS/Windows 环境中的 host 网络和 TUN 行为与 Linux 不同。

## 安装

一行安装：

```bash
bash -c "$(curl -fsSL https://v6.gh-proxy.org/https://raw.githubusercontent.com/Blaine-Li/mihomo-docker-cli/main/install.sh)"
```

安装过程会询问订阅链接。可以直接回车跳过，之后通过 `clashctl` 交互菜单配置。

安装完成后，根据使用的 shell 重新加载配置：

```bash
# Bash
source ~/.bashrc

# Zsh
source ~/.zshrc
```

如果对应的 rc 文件不存在，脚本不会自动创建它，也不会安装快捷别名。此时可以直接使用：

```bash
~/.clash/clashctl status
source ~/.clash/clashctl on
source ~/.clash/clashctl off
```

## 使用

直接运行 `clashctl` 可打开交互菜单：

```text
1) 查看状态
2) 查看日志
3) 更新订阅
4) 修改代理端口
5) 修改 UI/API 控制端口
6) 更新管理脚本
7) 卸载 Clash
0) 退出

如要启停请输入 clashon 或 clashoff
```

常用命令：

| 命令 | 说明 |
| --- | --- |
| `clashon` | 启动容器并启用 shell 代理 |
| `clashoff` | 停止容器并关闭 shell 代理 |
| `clashctl status` | 查看容器、端口和代理变量状态 |
| `clashctl logs` | 持续查看容器日志，按 `Ctrl+C` 退出 |
| `clashctl update [URL]` | 更新订阅；不提供 URL 时使用已保存的链接 |
| `clashctl port` | 查看当前代理与控制 API 端口 |
| `clashctl port proxy 7891` | 修改 HTTP/SOCKS5 混合代理端口 |
| `clashctl port ui 9091` | 修改控制 API 端口 |
| `clashctl upgrade` | 从本项目默认地址更新管理脚本 |
| `clashctl version` | 显示管理脚本版本 |
| `clashctl uninstall` | 停止容器并删除本地安装 |

`clashon` 和 `clashoff` 使用 `source`，因此能够修改当前终端环境。普通执行 `clashctl port proxy <端口>` 无法反向修改父级终端；脚本会提示执行对应的 `source ~/.clash/clashctl on` 或 `off` 命令。

这里的“代理”指 `http_proxy`、`https_proxy`、`all_proxy` 等 shell 环境变量，不会自动修改桌面系统代理，也不保证浏览器或图形应用使用该代理。

首次下载和后续更新订阅时，请求会使用 `User-Agent: clash-verge/v2.4.5`，以兼容会校验客户端类型的订阅服务。

## 端口与配置

默认端口：

- `7890`：HTTP/SOCKS5 混合代理
- `9090`：Mihomo 外部控制 API

修改端口前，脚本会将配置备份为 `config.yaml.port.bak`，并把用户设置独立保存到 `ports.env`。如果容器正在运行，会重建临时容器并同步现有 `.bashrc`/`.zshrc` 代理配置；正常关闭状态不会重新启用代理。

每次更新订阅后，脚本都会重新应用 `ports.env` 中的代理端口和控制端口，因此用户设置不会被订阅覆盖。要恢复订阅提供的端口，可删除 `~/.clash/ports.env` 后重新运行 `clashctl update`。

## Web 面板

Mihomo 的控制端口提供 API，不直接提供网页。可以使用 [MetaCubeXD 官方面板](https://metacubex.github.io/metacubexd)。若配置包含 `secret`，还需要在面板中填写同一个密钥。

默认建议让 `external-controller` 仅监听 `127.0.0.1`。如确需远程访问，请按照 [Mihomo 通用配置文档](https://wiki.metacubex.one/config/general/) 设置强 `secret`、限制防火墙来源，并将 `external-controller-cors` 限制为可信面板来源。不要把无认证的控制 API 暴露到公网。

## 本地文件

```text
~/.clash/
├── clashctl               # 管理脚本
├── config.yaml            # 当前 Mihomo 配置，权限 0600
├── config.yaml.bak        # 更新订阅前的备份，权限 0600
├── config.yaml.port.bak   # 修改端口前的备份，权限 0600
├── ports.env              # 独立保存的端口覆盖值，权限 0600
└── .env                   # 保存的订阅 URL，权限 0600
```

目录权限为 `0700`。订阅 URL 和配置文件通常包含访问令牌、服务器地址或节点凭据，不要将这些文件提交到 Git、上传到工单或粘贴到公开日志中。

## 安全说明

- 优先使用交互菜单输入订阅链接，避免 URL 留在 shell 历史中。
- 安装与 `clashctl upgrade` 都会下载远程脚本，项目当前没有提供签名更新机制。
- 默认镜像源未固定镜像 digest。高安全要求环境可在启动前通过 `CLASH_IMAGE` 指定可信版本或 digest。
- 容器使用 host 网络、`NET_ADMIN` 和 TUN 设备，权限高于普通容器。只在可信主机上运行，并审查订阅配置。
- 在线面板是在浏览器中运行的代码。只使用可信面板，并为远程控制 API 配置密钥和网络访问控制。

发现安全问题时，请不要创建包含订阅、配置或密钥的公开 Issue。请按照 [安全策略](SECURITY.md) 私下报告。

## 自定义镜像

启动前设置 `CLASH_IMAGE` 即可覆盖默认镜像：

```bash
export CLASH_IMAGE='docker.gh-proxy.com/metacubex/mihomo:v1.19.28'
clashon
```

脚本不会自动持久化该变量。需要长期使用时，请自行在安全的 shell 配置中设置。

## 卸载

```bash
clashctl uninstall
```

卸载会停止容器、清除脚本写入的 shell 配置块，并删除 `~/.clash`。该目录中的订阅、配置和备份也会一并删除。

## 参与贡献

提交变更前至少运行：

```bash
bash -n install.sh
git diff --check
```

请勿在测试、Issue、PR 或提交历史中包含真实订阅链接、节点配置和访问凭据。

## License

[MIT](LICENSE)
