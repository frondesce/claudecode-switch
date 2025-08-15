<a id="top"></a>
# claudecode-switch 🚀

> CLI wrapper that lets you switch between Claude Code–compatible providers (like Kimi, GLM, Qwen) with a single command.

🌐 English | [中文版](#zh)

A lightweight **PATH-based** wrapper for the official `@anthropic-ai/claude-code` CLI. It adds provider switching without modifying the official CLI.

With the `~/bin/claude` wrapper, you can quickly switch among providers that are compatible with the Anthropic API (Kimi/Moonshot, GLM/Zhipu, etc.) while keeping the official CLI untouched.

✨ Runtime log is:
```
>>> Using provider: kimi
```

---

## ✨ Features

- **🛠️ One-click installer**: ensures Node/npm, installs the official CLI, and writes the wrapper.
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
bash scripts/install-claude-switch.sh
# or explicitly
bash scripts/install-claude-switch.sh install
```

What the installer does:

1) Ensures Node.js/npm (tries system package manager, then falls back to NVM when possible)  
2) Installs `@anthropic-ai/claude-code` globally  
3) Adds `~/bin` to your PATH (idempotent)  
4) Writes the wrapper to `~/bin/claude`  
5) Creates a sample `~/.claude_providers.ini` if missing

> Tip: After first install, open a new terminal (or run `hash -r`) so the new PATH takes effect.

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
bash scripts/install-claude-switch.sh update
bash scripts/install-claude-switch.sh uninstall
bash scripts/install-claude-switch.sh uninstall --purge
bash scripts/install-claude-switch.sh status   # colored diagnostics
```

---

## 🗂️ Example Configuration

File path: `~/.claude_providers.ini` (override with `CLAUDE_CONF=/path/to/ini`)

```ini
default=kimi

[kimi]
BASE_URL=https://api.moonshot.cn/anthropic/
API_KEY=sk-xxxxxxxxxxxxxxxx

[glm]
BASE_URL=https://open.bigmodel.cn/api/anthropic/
API_KEY=xxxxxxxxxxxxxxxx
```

Resolution order:

1) `claude <provider>` argument  
2) `default=` in the INI  
3) If neither is set, wrapper runs the official CLI without injecting envs

Env variables exported for the official CLI:

- `ANTHROPIC_BASE_URL`
- `ANTHROPIC_AUTH_TOKEN`

---

## ⚙️ How It Works

- We **don’t rename** or patch the official binary.  
- A tiny wrapper lives at `~/bin/claude`; `~/bin` is placed **first** on your `PATH`.  
- The wrapper reads your INI, exports envs, and invokes the official CLI via **absolute paths** to avoid recursion.  
- Upgrading the official CLI is safe; the wrapper remains in your home directory and always wins on PATH.

---

## 🧪 Status & Troubleshooting

Run:
```bash
bash scripts/install-claude-switch.sh status
```
You’ll see colored checks for:

- **claude command path** — should resolve to `~/bin/claude`
- **Wrapper file exists** — verifies the wrapper is present
- **Config file path** — shows the INI path or `<not found>`
- **Default provider** — parsed from `default=`
- **Providers available** — lists `[sections]` in the INI

Common tips:

- If `claude` doesn’t resolve to `~/bin/claude`, open a new terminal or run `hash -r`.
- Ensure `~/bin` is **first** on your PATH.
- Very old distros: use **NVM** to install Node 18+ if system packages are outdated.
- Using `nvm`: keep the `export PATH="$HOME/bin:$PATH"` line **after** the `nvm` init lines in your shell rc.

---

## 📄 License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.


---  

<a id="zh"></a>

# 🌏 claudecode-switch（简体中文）

[Back to English](#top) | 中文版

> 一个基于 PATH 的轻量封装器，为官方 `@anthropic-ai/claude-code` CLI 增加 **Provider 切换** 能力；无需修改官方 CLI。

通过 `~/bin/claude` 包装器，你可以在不触碰官方执行文件的前提下，快速切换兼容 Anthropic API 的服务商（如 Kimi/Moonshot、GLM/智谱等）。

✨ 运行日志为：
```
>>> Using provider: kimi
```

---

## ✨ 功能点

- **🛠️ 一键安装脚本**：自动安装 Node/npm、官方 CLI、包装器
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
bash scripts/install-claude-switch.sh
```
或显式：
```bash
bash scripts/install-claude-switch.sh install
```

脚本功能：

1) 检查/安装 Node.js 与 npm（优先包管理器，必要时回退 NVM）  
2) 全局安装 `@anthropic-ai/claude-code`  
3) 将 `~/bin` 添加到 PATH（可重复执行）  
4) 写入包装器 `~/bin/claude`  
5) 若缺失则生成示例 `~/.claude_providers.ini`

> 首次安装后建议重新打开一个终端（或执行 `hash -r`），让 PATH 设置生效。

---

## 💡 常用命令

```bash
claude              # 使用默认 Provider
claude kimi         # 指定 kimi 启动
claude glm          # 指定 glm 启动
claude --list       # 列出 Provider（标注 default）

# 包装器维护
bash scripts/install-claude-switch.sh update
bash scripts/install-claude-switch.sh uninstall
bash scripts/install-claude-switch.sh uninstall --purge
bash scripts/install-claude-switch.sh status
```

---

## 📁 配置文件示例

路径：`~/.claude_providers.ini`（可用 `CLAUDE_CONF=/path/to/ini` 覆盖）

```ini
default=kimi

[kimi]
BASE_URL=https://api.moonshot.cn/anthropic/
API_KEY=sk-xxxxxxxxxxxxxxxx

[glm]
BASE_URL=https://open.bigmodel.cn/api/anthropic/
API_KEY=xxxxxxxxxxxxxxxx
```

解析优先级：

1) 命令行 `claude <provider>`  
2) INI 里的 `default=`  
3) 若都没有，则直接启动官方 CLI（不注入 env）

包装器会导出以下环境变量给官方 CLI：

- `ANTHROPIC_BASE_URL`
- `ANTHROPIC_AUTH_TOKEN`

---

## ⚙️ 工作原理

- **不重命名/不修改** 官方二进制；  
- 将包装器放在 `~/bin/claude`，并确保 `~/bin` 位于 PATH 前列；  
- 运行时读取 INI，导出环境变量，再通过**绝对路径**调用官方 CLI；  
- 升级官方 CLI 安全，不会覆盖包装器。

---

## 🧪 状态 & 故障排查

运行：
```bash
bash scripts/install-claude-switch.sh status
```
你会看到彩色输出，包括：

- **claude command path** → 目标为 `~/bin/claude`  
- **Wrapper file exists** → 包装器脚本是否存在  
- **Config file path** → 配置文件路径或 `<not found>`  
- **Default provider** → 读取自 `default=`  
- **Providers available** → INI 中的 `[section]` 列表

常见建议：

- 如果 `claude` 没解析到 `~/bin/claude`，请新开终端或执行 `hash -r`。  
- 确保 `~/bin` 在 PATH **最前**。  
- 老系统建议用 **NVM** 安装 Node 18+。  
- 使用 `nvm` 时，保证 `export PATH="$HOME/bin:$PATH"` 写在 `nvm` 初始化语句**之后**。

---

## 📄 许可证 / License

本项目采用 **MIT License** 授权。详见仓库根目录的 `LICENSE` 文件。
