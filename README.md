# claudecode-switch

> CLI wrapper that lets you switch between Claude Code-compatible providers (like Kimi, GLM, Qwen) with a single command.

English | [中文版](#zh)

---

## Overview

**claudecode-switch** is a lightweight wrapper script for the Claude Code CLI that allows you to quickly switch between different compatible API endpoints such as:

* Moonshot (Kimi)
* Zhipu (GLM)
* Qwen (coming soon)

It works by intercepting your call to `claude`, applying the correct environment variables based on a simple INI file, and delegating to the real `claude` binary.

---

## Features

* ✨ One-command switching: `claude kimi`, `claude glm`, `claude qwen`
* 📂 Unified config file: `~/claude_providers.ini`
* ⚡ Fast and zero-login after first-time setup
* ❌ Non-intrusive: preserves original `claude` as `claude-bin`
* ✍ Customize or extend to more providers easily

---

## Quickstart

### 1. Backup the original CLI

```bash
sudo mv "$(command -v claude)" "$(dirname \"$(command -v claude)\")/claude-bin"
```

### 2. Create provider config

```ini
# ~/claude_providers.ini

[kimi]
BASE_URL=https://api.moonshot.cn/anthropic/
API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxx

[glm]
BASE_URL=https://open.bigmodel.cn/api/anthropic/
API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

> `API_KEY` and `BASE_URL` are required. Tokens can be found in each platform's developer dashboard.

### 3. Create the wrapper script

Save this as `/usr/local/bin/claude`:

```bash
#!/usr/bin/env bash
# Read ~/claude_providers.ini and switch the environment according to the first position parameter
config="${CLAUDE_CONF:-$HOME/claude_providers.ini}"

# Treat the first argument as a provider tag
provider="$1"; shift

# Allow direct input `claude` to call the original version
if [[ "$provider" =~ ^[a-zA-Z0-9_-]+$ && -f "$config" ]]; then
    # Get BASE_URL
    base_url=$(awk -F'=' -v sec="[$provider]" '
        $0==sec {f=1; next} /^\[/{f=0}
        f && $1=="BASE_URL" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}
    ' "$config")
    # Get API_KEY
    api_key=$(awk -F'=' -v sec="[$provider]" '
        $0==sec {f=1; next} /^\[/{f=0}
        f && $1=="API_KEY" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}
    ' "$config")

    if [[ -z "$base_url" || -z "$api_key" ]]; then
        echo "✖ No complete configuration found for [$provider] in $config" >&2; exit 1
    fi

    export ANTHROPIC_BASE_URL="$base_url"
    export ANTHROPIC_AUTH_TOKEN="$api_key"
else
    # If no provider is specified, the parameters are returned as is.
    set -- "$provider" "$@"
fi


exec "$(command -v claude-bin)" "$@"
```

Then:

```bash
sudo chmod +x /usr/local/bin/claude
```

### 4. First-time run

```bash
claude kimi
```

Select option `2` (**Anthropic Console**) when prompted. After that, Claude CLI will remember the token.

To suppress future prompts, create this config:

```json
# ~/.claude/settings.json
{
  "forceLoginMethod": "console"
}
```

## ⚠️ Updating Claude Code CLI

When you run `npm install -g @anthropic-ai/claude-code@latest`,  
npm recreates a *global symlink* `~/.nvm/.../bin/claude`.  
If that symlink comes **before** `/usr/local/bin` in `$PATH`,  
your custom wrapper will be bypassed → `ANTHROPIC_*` variables won’t be set.

**Fix / Prevent**

- Make sure `/usr/local/bin` is at the front of your `$PATH`  

   ```bash
   # ~/.bashrc (or ~/.zshrc)
   export PATH="/usr/local/bin:$PATH"


---

<a name="zh"></a>
## 中文版本文档

### 概览

**claudecode-switch** 是 Claude Code 官方 CLI 的软装包装脚本，允许你通过一条命令：

```bash
claude kimi
```

快速切换到 Kimi、GLM、Qwen 等支持 Claude Code 协议的接口。

### 全流程简要

1. 备份官方 `claude` 执行文件，改名为 `claude-bin`
2. 新建 `~/claude_providers.ini`，一行一个配置 (BASE\_URL + API\_KEY)
3. 在 `/usr/local/bin` 写入脚本 `claude`，读取 INI 并 export 环境变量
4. 首次启动选择第 2 项 "Anthropic Console"，后续全程静默连接
5. (可选)在 `~/.claude/settings.json` 写入 `{ "forceLoginMethod": "console" }`

### ⚠️ 升级 Claude Code CLI

使用 `npm install -g @anthropic-ai/claude-code@latest` 升级时，  
npm 会在 `~/.nvm/.../bin` 重新生成一个名为 **claude** 的软链接。  
如果该目录在 `$PATH` 中排在 `/usr/local/bin` 前面，  
系统就会跳过你的包装脚本，导致 `ANTHROPIC_BASE_URL / AUTH_TOKEN`  
没有注入，CLI 会报 “Invalid API key”。

**解决 / 预防**

- 把 `/usr/local/bin` 放到 `$PATH` 最前  

   ```bash
   # 写入 ~/.bashrc 或 ~/.zshrc
   export PATH="/usr/local/bin:$PATH"

---

## License

This project is licensed under the MIT License.

---

## Coming soon

* Built-in shell autocompletion
* Auto-install script
* Support for Claude Code model flags
* Token encryption or system keyring support
