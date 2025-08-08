# claudecode-switch

> CLI wrapper that lets you switch between Claude Code-compatible providers (like Kimi, GLM, Qwen) with a single command.

English | [中文版](#zh)

---

## Overview

**claudecode-switch** is a lightweight wrapper script for the Claude Code CLI that allows you to quickly switch between different compatible API endpoints such as:

* Moonshot (Kimi)
* Zhipu (GLM)
* Any API hub

It works by intercepting your call to `claude`, applying the correct environment variables based on a simple INI file, and delegating to the real `claude` binary.

---

## Features

* ✨ One-command switching: `claude kimi`, `claude glm`, `claude qwen`
* 📂 Unified config file: `~/claude_providers.ini`
* ⚡ Fast and zero-login after first-time setup
* 🔄 Default provider support: define `default=kimi` for fallback
* 📋 View all providers: run `claude --list` to show available configs
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
default=kimi

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
# Claude wrapper: auto switch environment via claude_providers.ini

config="${CLAUDE_CONF:-$HOME/claude_providers.ini}"

# Read default=xxx from ini (if it exists)
default_provider=""
if [[ -f "$config" ]]; then
    default_provider=$(awk -F '=' '
        $1 ~ /^[ \t]*default[ \t]*$/ {
            gsub(/^[ \t]+|[ \t]+$/, "", $2);
            print $2;
            exit
        }
    ' "$config")
fi

# # Execute --list to display all available configurations
if [[ "$1" == "--list" ]]; then
    if [[ -f "$config" ]]; then
        echo "Available Claude providers in $config:"
        awk -v def="$default_provider" '
            /^\[.*\]/ {
                sec=substr($0, 2, length($0)-2);
                if (sec == def) {
                    printf "  - %s (default)\n", sec
                } else {
                    printf "  - %s\n", sec
                }
            }
        ' "$config"
    else
        echo "⚠ Config file not found: $config"
    fi
    exit 0
fi

# Parsing provider: prioritize user-passed parameters, then fallback to default_provider
provider="$1"
if [[ ! "$provider" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    provider="$default_provider"
else
    shift
fi

# If it is still empty, it means that no default is set and no parameters are passed in
if [[ -z "$provider" ]]; then
    echo "⚠ No provider specified, and no [default] mapping found in $config" >&2
    exec "$(command -v claude-bin)" "$@"  # Start directly without configuration
fi

# Extract the configuration items of the provider
base_url=$(awk -F '=' -v sec="[$provider]" '
    $0 == sec {f=1; next} /^\[/{f=0}
    f && $1=="BASE_URL" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}
' "$config")

api_key=$(awk -F '=' -v sec="[$provider]" '
    $0 == sec {f=1; next} /^\[/{f=0}
    f && $1=="API_KEY" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}
' "$config")

# Load environment variables
if [[ -n "$base_url" && -n "$api_key" ]]; then
    export ANTHROPIC_BASE_URL="$base_url"
    export ANTHROPIC_AUTH_TOKEN="$api_key"

    echo ">>> ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL" >&2
    echo ">>> ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN" >&2
else
    echo "✖ Configuration for [$provider] is incomplete or missing." >&2
    exit 1
fi

# Execute claude-bin
exec "$(command -v claude-bin)" "$@"
```

Then:

```bash
sudo chmod +x /usr/local/bin/claude
```

### 4. Usage

> Configure all providers in a single `~/.claude_providers.ini` file.

#### ✅ Basic commands

```bash
claude kimi         # Use the [kimi] provider
claude glm          # Use the [glm] provider
claude              # Use the default provider (from `default=xxx`)
claude --list       # List all available providers, highlight default
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

1. Make sure `/usr/local/bin` is at the front of your `$PATH`:

   ```bash
   # ~/.bashrc (or ~/.zshrc)
   export PATH="/usr/local/bin:$PATH"
   ```

2. Immediately rename the autogenerated `claude` symlink to avoid wrapper conflict:

   ```bash
   mv "$(npm prefix -g)/bin/claude" "$(npm prefix -g)/bin/claude-bin"
   ```

3. Refresh your shell's command lookup cache:

   ```bash
   hash -r    # or use `rehash` if you're using zsh
   ```

After that, your `/usr/local/bin/claude` wrapper will remain active,  
and the CLI will work as expected — without `exec: : not found` or environment variable issues.

**Note about `.bashrc` and `nvm`**:

Even if you have already added:

```bash
export PATH=/usr/local/bin:$PATH
```

You must ensure this line appears after nvm is loaded.
Otherwise, nvm will re-append its own bin path (e.g. ~/.nvm/.../bin) to the front of your $PATH, overriding your changes.

If unsure, scroll to the bottom of your ~/.bashrc or ~/.zshrc and make sure the export PATH=/usr/local/bin:$PATH line comes after the following lines:

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```

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

1. 确保 `/usr/local/bin` 位于 `$PATH`前面：

   ```bash
   # ~/.bashrc (or ~/.zshrc)
   export PATH="/usr/local/bin:$PATH"
   ```

2. 重命名 `claude` 软链以避免冲突：

   ```bash
   mv "$(npm prefix -g)/bin/claude" "$(npm prefix -g)/bin/claude-bin"
   ```

3. 刷新 shell 的命令查找缓存：

   ```bash
   hash -r    # or use `rehash` if you're using zsh
   ```

此后，您的 `/usr/local/bin/claude` 包装器将为正确状态， 
并且 CLI 将按预期工作 - 没有`exec: : not found`或环境变量问题。

**关于 .bashrc 和 nvm 的说明**

即使你已经添加了以下内容：

```bash
export PATH=/usr/local/bin:$PATH
```

你仍需确保这一行写在 nvm 加载语句之后。
否则，nvm 会将自己的 bin 路径（例如 `~/.nvm/.../bin`）重新添加到 `$PATH` 的最前面，从而覆盖你的设置。如果不确定，请打开你的 `~/.bashrc` 或 `~/.zshrc`，确认 `export PATH=/usr/local/bin:$PATH` 这一行位于以下几行之后：

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```

---

## License

This project is licensed under the MIT License.

---

## Coming soon

* Built-in shell autocompletion
* Auto-install script
* Support for Claude Code model flags
* Token encryption or system keyring support
