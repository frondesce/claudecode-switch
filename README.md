> [!IMPORTANT]
> **This project is archived and no longer maintained.**
>
> This repository is preserved for reference purposes.
> No further updates, bug fixes, or support will be provided.
<a id="top"></a>
# claudecode-switch 🚀

> CLI wrapper that lets you switch between Claude Code–compatible providers (like Kimi, GLM, Qwen) with a single command.

🌐 English | [中文版](#zh)

A lightweight **PATH-based** wrapper for the official Claude Code CLI. It adds provider switching without modifying the official CLI.

With the `~/bin/claude` wrapper, you can quickly switch among providers that are compatible with the Anthropic API (Kimi/Moonshot, GLM/Zhipu, etc.) while keeping the official CLI untouched.

✨ Runtime log is:
```
>>> Using provider: kimi
```

📌 Claude Code >= 2.0 change: the official CLI now reads credentials from `~/.claude/settings.json` (`env` block), not from shell env vars. The wrapper writes/updates that file for the chosen provider automatically.

---

## ✨ Features

- **🛠️ One-click installer**: ensures Node, installs the official CLI, and writes the wrapper.
- 🧩 Multiple providers via `~/.claude_providers.ini`.
- 🌟 `default=` to set a default provider.
- 🔀 `claude <provider>` to select a provider on the fly.
- 📜 `claude --list` to show providers (marks `(default)`).
- 🎨 `status` subcommand with colored diagnostics.
- ❌ `uninstall --purge` to remove both wrapper and config.
- 🔒 Official CLI updates won’t overwrite the wrapper (PATH shadowing).

---

## 🛠️ Installation

```bash
bash cc-switch.sh
# or explicitly
bash cc-switch.sh install
```

What the installer does:

1) Ensures Node.js (tries system package manager, then falls back to NVM when possible)  
2) Installs the official Claude Code CLI via `curl -fsSL https://claude.ai/install.sh | bash`  
3) Adds `~/bin` to your PATH in shell rc/login files (idempotent)  
4) Writes the wrapper to `~/bin/claude`  
5) Creates a sample `~/.claude_providers.ini` if missing (new format for Claude Code >= 2.0)  

Note: when using NVM, if downloading the official Node binary fails, the installer auto-retries with `NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node` to avoid slow source builds.

> Tip: After first install, open a new terminal or source the file your shell reads (e.g., `source ~/.bashrc`, `source ~/.zshrc`, or `source ~/.profile` for login shells) so the new PATH takes effect. If `claude` was cached, run `hash -r`.

---

## 🧩 Common Commands

```bash
# Use default provider (from ~/.claude_providers.ini)
claude

# Use a specific provider
claude kimi
claude glm

# List all providers (default is marked)
claude --list

# Wrapper maintenance
bash cc-switch.sh update
bash cc-switch.sh uninstall
bash cc-switch.sh uninstall --purge
bash cc-switch.sh status   # colored diagnostics
```

---

## 🗂️ Example Configuration

File path: `~/.claude_providers.ini` (override with `CLAUDE_CONF=/path/to/ini`)

```ini
default=kimi

[kimi]
ANTHROPIC_AUTH_TOKEN=sk-xxxxxxxxxxxxxxxx
ANTHROPIC_BASE_URL=https://api.kimi.com/coding/
ANTHROPIC_DEFAULT_SONNET_MODEL=kimi-for-coding          ; optional
ANTHROPIC_DEFAULT_HAIKU_MODEL=kimi-for-coding           ; optional
ANTHROPIC_DEFAULT_OPUS_MODEL=kimi-for-coding            ; optional

[glm]
ANTHROPIC_AUTH_TOKEN=sk-xxxxxxxxxxxxxxxx
ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic/
ANTHROPIC_DEFAULT_SONNET_MODEL=glm-4.7              ; optional
ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.7               ; optional
ANTHROPIC_DEFAULT_OPUS_MODEL=glm-4.7                ; optional
```

Resolution order:

1) `claude <provider>` argument  
2) `default=` in the INI  
3) If neither is set, wrapper runs the official CLI without updating settings

When a provider is chosen, the wrapper writes these keys into `~/.claude/settings.json` → `env`:

- `ANTHROPIC_AUTH_TOKEN` (required)
- `ANTHROPIC_BASE_URL` (required)
- `ANTHROPIC_DEFAULT_SONNET_MODEL` (optional; only written if present)
- `ANTHROPIC_DEFAULT_HAIKU_MODEL` (optional; only written if present)
- `ANTHROPIC_DEFAULT_OPUS_MODEL` (optional; only written if present)

---

## ⚙️ How It Works

- We **don’t rename** or patch the official binary.  
- A tiny wrapper lives at `~/bin/claude`; `~/bin` is placed **first** on your `PATH`.  
- The wrapper reads your INI, writes credentials into `~/.claude/settings.json` (`env` block), and invokes the official CLI via **absolute paths** to avoid recursion.  
- Upgrading the official CLI is safe; the wrapper remains in your home directory and always wins on PATH.

---

## 🧪 Status & Troubleshooting

Run:
```bash
bash cc-switch.sh status
```
You’ll see colored checks for:

- **claude command path** — should resolve to `~/bin/claude`
- **Wrapper file exists** — verifies the wrapper is present
- **Config file path** — shows the INI path or `<not found>`
- **Default provider** — parsed from `default=`
- **Providers available** — lists `[sections]` in the INI

Common tips:

- If `claude` doesn’t resolve to `~/bin/claude`, open a new terminal or source the file your shell reads (e.g., `~/.bashrc`, `~/.zshrc`, or `~/.profile` for login shells). If needed, run `hash -r`.
- Ensure `~/bin` is **first** on your PATH.
- Node 20+ is required; if glibc < 2.28 is detected, the installer automatically falls back to Node 18 for compatibility. It will try to upgrade via NodeSource/NVM (needs `curl`). If an existing nvm-installed Node is still glibc-incompatible, the script will attempt an NVM source build; otherwise you may need to rebuild manually (e.g. `nvm uninstall 18 && nvm install -s 18`).
- If `curl` is missing, the installer will prompt to install it via your package manager (requires sudo); otherwise please install curl manually.
- When falling back to NVM, the installer reloads nvm and switches to Node 20 so that the new node is available in the current shell (avoids false failures).
- Debug mode: set `CLAUDE_SWITCH_DEBUG=1` to print extra diagnostics (PATH, node resolution) if installation has issues.
  - When run as root (or via sudo), the installer can auto-install curl via apt/yum/pacman without needing passwordless sudo.
- Very old distros: use **NVM** to install Node 20+ if system packages are outdated.
- Using `nvm`: keep the `export PATH="$HOME/bin:$PATH"` line **after** the `nvm` init lines in your shell rc.

---

## 📄 License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.


---  

<a id="zh"></a>

# 🌏 claudecode-switch（简体中文）

[Back to English](#top) | 中文版

> 一个基于 PATH 的轻量封装器，为官方 Claude Code CLI 增加 **Provider 切换** 能力；无需修改官方 CLI。

通过 `~/bin/claude` 包装器，你可以在不触碰官方执行文件的前提下，快速切换兼容 Anthropic API 的服务商（如 Kimi/Moonshot、GLM/智谱等）。

✨ 运行日志为：
```
>>> Using provider: kimi
```

📌 Claude Code 2.0 及以上：官方 CLI 从 `~/.claude/settings.json`（`env` 字段）读取密钥，不再读 shell 环境变量。包装器会为所选 Provider 自动写/更新该文件。

---

## ✨ 功能点

- **🛠️ 一键安装脚本**：自动安装 Node、官方 CLI、包装器
- 🧩 `~/.claude_providers.ini` 统一管理多 Provider
- 🌟 `default=` 设置默认 Provider
- 🔀 `claude <provider>` 临时切换指定 Provider
- 📜 `claude --list` 列出所有 Provider（标注 `(default)`）
- 🎨 `status` 子命令彩色查看环境状态
- ❌ `uninstall --purge` 卸载并清理配置文件
- 🔒 官方 CLI 升级不覆盖包装器（PATH 影子法）

---

## 🛠️ 安装

```bash
bash cc-switch.sh
```
或显式：
```bash
bash cc-switch.sh install
```

脚本功能：

1) 检查/安装 Node.js（优先包管理器，必要时回退 NVM）  
2) 通过官方安装脚本安装 Claude Code CLI（`curl -fsSL https://claude.ai/install.sh | bash`）  
3) 将 `~/bin` 写入 shell rc/登录文件的 PATH（可重复执行）  
4) 写入包装器 `~/bin/claude`  
5) 若缺失则生成示例 `~/.claude_providers.ini`

> 首次安装后建议重新打开终端，或执行当前 shell 读取的文件（如 `source ~/.bashrc`、`source ~/.zshrc`，登录 shell 则 `source ~/.profile`）让 PATH 生效；若 shell 缓存了 `claude`，再执行 `hash -r`。

---

## 💡 常用命令

```bash
claude              # 使用默认 Provider
claude kimi         # 指定 kimi 启动
claude glm          # 指定 glm 启动
claude --list       # 列出 Provider（标注 default）

# 包装器维护
bash cc-switch.sh update
bash cc-switch.sh uninstall
bash cc-switch.sh uninstall --purge
bash cc-switch.sh status
```

---

## 📁 配置文件示例

路径：`~/.claude_providers.ini`（可用 `CLAUDE_CONF=/path/to/ini` 覆盖）

```ini
default=kimi

[kimi]
ANTHROPIC_AUTH_TOKEN=sk-xxxxxxxxxxxxxxxx
ANTHROPIC_BASE_URL=https://api.kimi.com/coding/
ANTHROPIC_DEFAULT_SONNET_MODEL=kimi-for-coding          ; 可选
ANTHROPIC_DEFAULT_HAIKU_MODEL=kimi-for-coding           ; 可选
ANTHROPIC_DEFAULT_OPUS_MODEL=kimi-for-coding            ; 可选

[glm]
ANTHROPIC_AUTH_TOKEN=sk-xxxxxxxxxxxxxxxx
ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic/
ANTHROPIC_DEFAULT_SONNET_MODEL=glm-4.7              ; 可选
ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.7               ; 可选
ANTHROPIC_DEFAULT_OPUS_MODEL=glm-4.7                ; 可选
```

解析优先级：

1) 命令行 `claude <provider>`  
2) INI 里的 `default=`  
3) 若都没有，则直接启动官方 CLI（不更新 settings）

选择 Provider 后，包装器会将以下键写入 `~/.claude/settings.json` 的 `env`：

- `ANTHROPIC_AUTH_TOKEN`（必填）
- `ANTHROPIC_BASE_URL`（必填）
- `ANTHROPIC_DEFAULT_SONNET_MODEL`（可选，提供时写入）
- `ANTHROPIC_DEFAULT_HAIKU_MODEL`（可选，提供时写入）
- `ANTHROPIC_DEFAULT_OPUS_MODEL`（可选，提供时写入）

---

## ⚙️ 工作原理

- **不重命名/不修改** 官方二进制；  
- 将包装器放在 `~/bin/claude`，并确保 `~/bin` 位于 PATH 前列；  
- 运行时读取 INI，将凭据写入 `~/.claude/settings.json` 的 `env`，再通过**绝对路径**调用官方 CLI；  
- 升级官方 CLI 安全，不会覆盖包装器。

---

## 🧪 状态 & 故障排查

运行：
```bash
bash cc-switch.sh status
```
你会看到彩色输出，包括：

- **claude command path** → 目标为 `~/bin/claude`  
- **Wrapper file exists** → 包装器脚本是否存在  
- **Config file path** → 配置文件路径或 `<not found>`  
- **Default provider** → 读取自 `default=`  
- **Providers available** → INI 中的 `[section]` 列表

常见建议：

- 如果 `claude` 没解析到 `~/bin/claude`，请新开终端或执行当前 shell 读取的文件（如 `~/.bashrc`、`~/.zshrc`，登录 shell 则 `~/.profile`）；必要时再执行 `hash -r`。  
- 确保 `~/bin` 在 PATH **最前**。  
- 需要 Node 20+；若检测到 glibc < 2.28，会自动回退到 Node 18 以兼容旧系统。脚本会尝试通过 NodeSource/NVM 升级（需要 `curl`）。若已有 nvm 的 Node 仍因 glibc 不兼容，脚本会尝试 NVM 源码编译；失败则可手动 `nvm uninstall 18 && nvm install -s 18` 重建。
- 如果缺少 `curl`，安装器会询问是否用包管理器安装（需 sudo）；否则请手动安装。  
- 回退到 NVM 时，安装器会重新加载 nvm 并切到 Node 20，确保当前 shell 能识别新 node，避免“假失败”。  
- 调试模式：若安装有问题，可先设 `CLAUDE_SWITCH_DEBUG=1`，脚本会输出额外诊断信息（PATH、node 检测）。  
  - 以 root/sudo 运行时，脚本可以通过 apt/yum/pacman 自动安装 curl（不要求免密 sudo）。  
- 老系统建议用 **NVM** 安装 Node 20+。  
- 使用 `nvm` 时，保证 `export PATH="$HOME/bin:$PATH"` 写在 `nvm` 初始化语句**之后**。  

---

## 📄 许可证 / License

本项目采用 **MIT License** 授权。详见仓库根目录的 `LICENSE` 文件。
