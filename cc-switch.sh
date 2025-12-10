#!/usr/bin/env bash
set -euo pipefail

# ========================
# Config
# ========================
WRAPPER_PATH="${HOME}/bin/claude"
CONF_PATH="${HOME}/.claude_providers.ini"

# ========================
# Colors
# ========================
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NC="\033[0m"

# ========================
# Helpers
# ========================
msg()  { printf "${GREEN}%s${NC}\n" "$*"; }
warn() { printf "${YELLOW}%s${NC}\n" "$*"; }
err()  { printf "${RED}%s${NC}\n" "$*" >&2; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }
can_sudo() { have_cmd sudo && sudo -n true 2>/dev/null; }

append_once() {
  # append_once <file> <line>
  local f="$1" line="$2"
  [ -f "$f" ] || touch "$f"
  grep -Fqx "$line" "$f" || printf "%s\n" "$line" >> "$f"
}

detect_shell_rc() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    echo "${HOME}/.zshrc"
  elif [ -n "${BASH_VERSION:-}" ]; then
    echo "${HOME}/.bashrc"
  else
    echo "${HOME}/.bashrc"
  fi
}

ensure_path_prefix() {
  local rc; rc="$(detect_shell_rc)"
  mkdir -p "${HOME}/bin"
  local export_line='export PATH="$HOME/bin:$PATH"'
  append_once "$rc" "$export_line"
  # idempotent patch to common rc files
  [ "$rc" != "${HOME}/.bashrc" ] && [ -f "${HOME}/.bashrc" ] && append_once "${HOME}/.bashrc" "$export_line"
  [ "$rc" != "${HOME}/.zshrc" ] && [ -f "${HOME}/.zshrc" ] && append_once "${HOME}/.zshrc" "$export_line"
  export PATH="$HOME/bin:$PATH"
}

# ------------------------
# Node/npm installation
# ------------------------
install_node_with_pkgmgr() {
  if have_cmd apt && can_sudo; then
    msg "Installing node/npm via apt (NodeSource 18.x)..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt install -y nodejs
    return 0
  fi
  if have_cmd yum && can_sudo; then
    msg "Installing node/npm via yum..."
    sudo yum install -y nodejs npm
    return 0
  fi
  if have_cmd pacman && can_sudo; then
    msg "Installing node/npm via pacman..."
    sudo pacman -Sy --noconfirm nodejs npm
    return 0
  fi
  if have_cmd brew; then
    msg "Installing node via Homebrew..."
    brew install node
    return 0
  fi
  return 1
}

install_node_with_nvm() {
  msg "Installing node/npm via NVM (no sudo required)..."
  export NVM_DIR="${HOME}/.nvm"
  if [ ! -s "${NVM_DIR}/nvm.sh" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  # shellcheck disable=SC1090
  [ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"
  nvm install 18
  nvm use 18
}

ensure_node_npm() {
  if have_cmd node && have_cmd npm; then
    msg "node & npm found: $(node -v) / npm $(npm -v)"
    return 0
  fi
  warn "node/npm not found. Attempting installation..."
  if install_node_with_pkgmgr; then
    if have_cmd node && have_cmd npm; then
      msg "Installed node/npm via package manager."
      return 0
    fi
  fi
  if have_cmd curl; then
    install_node_with_nvm
    if have_cmd node && have_cmd npm; then
      msg "Installed node/npm via NVM: $(node -v)"
      return 0
    fi
  fi
  err "Failed to install node/npm automatically. Please install manually and re-run."
  exit 1
}

ensure_claude_code_cli() {
  msg "Ensuring @anthropic-ai/claude-code is installed globally..."
  if npm i -g @anthropic-ai/claude-code >/dev/null 2>&1; then
    return
  fi

  warn "npm install failed. Attempting automatic cleanup and retry..."
  npm uninstall -g @anthropic-ai/claude-code >/dev/null 2>&1 || true

  local npm_root
  npm_root="$(npm root -g 2>/dev/null || true)"
  if [ -n "${npm_root}" ] && [ -d "${npm_root}/@anthropic-ai" ]; then
    rm -rf "${npm_root}/@anthropic-ai/claude-code"
    find "${npm_root}/@anthropic-ai" -maxdepth 1 -type d -name '.claude-code-*' -exec rm -rf {} +
  fi

  npm cache clean --force >/dev/null 2>&1 || true

  if ! npm i -g @anthropic-ai/claude-code; then
    warn "Global npm install failed (likely permissions). Trying user prefix ~/.npm-global..."
    local user_prefix="${HOME}/.npm-global"
    mkdir -p "${user_prefix}"
    if npm config set prefix "${user_prefix}" >/dev/null 2>&1; then
      export PATH="${user_prefix}/bin:${PATH}"
      local rc; rc="$(detect_shell_rc)"
      local export_line="export PATH=\"${user_prefix}/bin:\\\$PATH\""
      append_once "$rc" "$export_line"
      [ "$rc" != "${HOME}/.bashrc" ] && [ -f "${HOME}/.bashrc" ] && append_once "${HOME}/.bashrc" "$export_line"
      [ "$rc" != "${HOME}/.zshrc" ] && [ -f "${HOME}/.zshrc" ] && append_once "${HOME}/.zshrc" "$export_line"
      if npm i -g @anthropic-ai/claude-code; then
        msg "Installed @anthropic-ai/claude-code into user prefix ${user_prefix}."
        return
      fi
    else
      warn "Failed to set npm user prefix; you may need to adjust npm permissions manually."
    fi
    err "Failed to install @anthropic-ai/claude-code automatically."
    exit 1
  fi
}

# ------------------------
# Wrapper
# ------------------------
write_wrapper() {
  local tmp="${WRAPPER_PATH}.tmp.$$"
  cat > "$tmp" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CLAUDE_CONF:-$HOME/.claude_providers.ini}"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_PATH="${CLAUDE_DIR}/settings.json"

get_ini_value() {
  local section="$1" key="$2"
  awk -F '=' -v sec="[$section]" -v key="$key" '
    $0==sec {f=1; next}
    /^\[/{f=0}
    f {
      k=$1; gsub(/^[ \t]+|[ \t]+$/, "", k)
      if (k==key) {
        v=$2; gsub(/^[ \t]+|[ \t]+$/, "", v)
        print v; exit
      }
    }
  ' "$CONFIG" 2>/dev/null
}

# ---- read default ----
default_provider=""
if [[ -f "$CONFIG" ]]; then
  default_provider=$(awk -F '=' '
    $1 ~ /^[ \t]*default[ \t]*$/ {
      gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit
    }' "$CONFIG")
fi

# ---- --list providers ----
if [[ "${1:-}" == "--list" ]]; then
  if [[ -f "$CONFIG" ]]; then
    echo "Available Claude providers in $CONFIG:"
    awk -v def="$default_provider" '
      /^\[.*\]/ {
        sec=substr($0,2,length($0)-2);
        if (sec==def) printf "  - %s (default)\n", sec; else printf "  - %s\n", sec
      }' "$CONFIG"
  else
    echo "⚠ Config file not found: $CONFIG"
  fi
  exit 0
fi

# ---- choose provider ----
provider="${1:-}"
if [[ -n "$provider" && "$provider" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  shift
else
  provider="$default_provider"
fi

if [[ -n "$provider" ]]; then
  auth_token=$(get_ini_value "$provider" "ANTHROPIC_AUTH_TOKEN")
  [[ -z "${auth_token:-}" ]] && auth_token=$(get_ini_value "$provider" "API_KEY") # backward compat

  base_url=$(get_ini_value "$provider" "ANTHROPIC_BASE_URL")
  [[ -z "${base_url:-}" ]] && base_url=$(get_ini_value "$provider" "BASE_URL") # backward compat

  model=$(get_ini_value "$provider" "ANTHROPIC_MODEL")
  [[ -z "${model:-}" ]] && model=$(get_ini_value "$provider" "MODEL")

  small_fast=$(get_ini_value "$provider" "ANTHROPIC_SMALL_FAST_MODE")
  [[ -z "${small_fast:-}" ]] && small_fast=$(get_ini_value "$provider" "SMALL_FAST_MODE")

  missing=()
  [[ -z "${auth_token:-}" ]] && missing+=("ANTHROPIC_AUTH_TOKEN")
  [[ -z "${base_url:-}" ]] && missing+=("ANTHROPIC_BASE_URL")

  if (( ${#missing[@]} > 0 )); then
    printf "✖ Provider [%s] has incomplete config (missing: %s).\n" "$provider" "$(IFS=,; echo "${missing[*]}")" >&2
    exit 1
  fi

  export SETTINGS_PATH PROVIDER="$provider"
  export AUTH_TOKEN="$auth_token" BASE_URL="$base_url" MODEL="$model" SMALL_FAST="$small_fast"

  node <<'NODE'
const fs = require('fs');
const path = require('path');

const settingsPath = process.env.SETTINGS_PATH;
const claudeDir = path.dirname(settingsPath);
const envUpdates = {};
const maybeSet = (key, val) => {
  if (typeof val !== 'undefined' && val !== '') envUpdates[key] = val;
};
maybeSet('ANTHROPIC_AUTH_TOKEN', process.env.AUTH_TOKEN);
maybeSet('ANTHROPIC_BASE_URL', process.env.BASE_URL);
maybeSet('ANTHROPIC_MODEL', process.env.MODEL);
maybeSet('ANTHROPIC_SMALL_FAST_MODE', process.env.SMALL_FAST);

fs.mkdirSync(claudeDir, { recursive: true });

let data = {};
if (fs.existsSync(settingsPath)) {
  try {
    const raw = fs.readFileSync(settingsPath, 'utf8');
    data = raw.trim() ? JSON.parse(raw) : {};
  } catch (err) {
    console.error(`✖ Failed to parse ${settingsPath}: ${err.message}`);
    process.exit(1);
  }
}

data.env = { ...(data.env || {}), ...envUpdates };
if (!data.permissions) data.permissions = { allow: [], deny: [] };
if (typeof data.alwaysThinkingEnabled === 'undefined') data.alwaysThinkingEnabled = true;

fs.writeFileSync(settingsPath, JSON.stringify(data, null, 2));
console.error(`>>> Updated ${settingsPath} for provider ${process.env.PROVIDER}`);
NODE
else
  echo "✖ No provider selected and no default configured in $CONFIG" >&2
  exit 1
fi

# ---- locate official CLI (absolute paths to avoid recursion) ----
NPM_ROOT_G="$(npm root -g 2>/dev/null || true)"
NPM_PREFIX_G="$(npm prefix -g 2>/dev/null || true)"

CANDIDATES=(
  "$NPM_ROOT_G/@anthropic-ai/claude-code/dist/cli.js"
  "$NPM_ROOT_G/@anthropic-ai/claude-code/cli.mjs"
)

# fallback to global shim (absolute path avoids calling this wrapper)
if [[ -n "${NPM_PREFIX_G:-}" && -x "$NPM_PREFIX_G/bin/claude" ]]; then
  CANDIDATES+=("$NPM_PREFIX_G/bin/claude")
fi

for p in "${CANDIDATES[@]}"; do
  if [[ -f "$p" ]]; then
    exec node "$p" "$@"
  elif [[ -x "$p" ]]; then
    exec "$p" "$@"
  fi
done

echo "Official Claude CLI not found. Please install: npm i -g @anthropic-ai/claude-code" >&2
exit 1
SH

  mkdir -p "$(dirname "$WRAPPER_PATH")"
  mv -f "$tmp" "$WRAPPER_PATH"
  chown "$USER":"$USER" "$WRAPPER_PATH" 2>/dev/null || true
  chmod +x "$WRAPPER_PATH"
}

write_sample_conf_if_absent() {
  if [ -f "$CONF_PATH" ]; then
    warn "Config already exists: $CONF_PATH (leaving it untouched)."
    return 0
  fi
  cat > "$CONF_PATH" <<'INI'
# Default provider name
default=kimi

# Providers (Anthropic-compatible API)
[kimi]
ANTHROPIC_AUTH_TOKEN=sk-xxxxxxxxxxxxxxxx
ANTHROPIC_BASE_URL=https://api.kimi.com/coding/
ANTHROPIC_MODEL=kimi-for-coding
ANTHROPIC_SMALL_FAST_MODE=kimi-for-coding

[glm]
ANTHROPIC_AUTH_TOKEN=sk-xxxxxxxxxxxxxxxx
ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic/
ANTHROPIC_MODEL=glm-4.5
ANTHROPIC_SMALL_FAST_MODE=glm-4.5-air
INI
  chmod 600 "$CONF_PATH" || true
}

# ------------------------
# Status (colored)
# ------------------------
cmd_status() {
  echo -e "${BOLD}Claude Wrapper Status${NC}"
  echo "---------------------"

  # claude command path
  local CLAUDE_PATH
  CLAUDE_PATH="$(command -v claude 2>/dev/null || true)"
  if [[ -n "$CLAUDE_PATH" && -x "$CLAUDE_PATH" ]]; then
    echo -e "claude command path: ${GREEN}${CLAUDE_PATH}${NC}"
  else
    echo -e "claude command path: ${RED}<not found>${NC}"
  fi

  # wrapper file
  if [[ -f "$WRAPPER_PATH" ]]; then
    echo -e "Wrapper file exists: ${GREEN}Yes${NC} (${WRAPPER_PATH})"
  else
    echo -e "Wrapper file exists: ${RED}No${NC} (expected at ${WRAPPER_PATH})"
  fi

  # config file, default provider, providers list
  if [[ -f "$CONF_PATH" ]]; then
    echo -e "Config file path: ${GREEN}${CONF_PATH}${NC}"
    local DEF
    DEF="$(grep -E '^\s*default\s*=' "$CONF_PATH" | awk -F= '{print $2}' | xargs)"
    if [[ -n "$DEF" ]]; then
      echo -e "Default provider: ${GREEN}${DEF}${NC}"
    else
      echo -e "Default provider: ${RED}<not set>${NC}"
    fi
    local PROVS
    PROVS="$(grep -E '^\[.*\]' "$CONF_PATH" | sed 's/[][]//g' | paste -sd',' -)"
    if [[ -n "$PROVS" ]]; then
      echo -e "Providers available: ${YELLOW}${PROVS}${NC}"
    else
      echo -e "Providers available: ${RED}<none>${NC}"
    fi
  else
    echo -e "Config file path: ${RED}<not found>${NC} (expected at ${CONF_PATH})"
  fi

  local SETTINGS_FILE="${HOME}/.claude/settings.json"
  if [[ -f "$SETTINGS_FILE" ]]; then
    echo -e "settings.json path: ${GREEN}${SETTINGS_FILE}${NC}"
  else
    echo -e "settings.json path: ${YELLOW}${SETTINGS_FILE}${NC} (will be created on first claude run)"
  fi
}

# ------------------------
# Update & Uninstall
# ------------------------
cmd_update() {
  msg "Updating wrapper..."
  ensure_path_prefix
  write_wrapper
  msg "Wrapper updated."
}

cmd_uninstall() {
  local PURGE=0
  if [[ "${1:-}" == "--purge" ]]; then
    PURGE=1
  fi

  read -r -p "Are you sure you want to uninstall the Claude wrapper? [y/N]: " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) warn "Uninstall cancelled."; exit 0 ;;
  esac

  if [ -f "${WRAPPER_PATH}" ]; then
    echo "Removing wrapper at ${WRAPPER_PATH}..."
    rm -f "${WRAPPER_PATH}"
    msg "Removed wrapper."
  else
    warn "Wrapper not found at ${WRAPPER_PATH}."
  fi

  if [ "$PURGE" -eq 1 ]; then
    if [ -f "${CONF_PATH}" ]; then
      read -r -p "Also remove config ${CONF_PATH}? [y/N]: " ans2
      case "$ans2" in
        y|Y|yes|YES) rm -f "${CONF_PATH}"; msg "Removed config." ;;
        *) warn "Skipped config removal." ;;
      esac
    else
      warn "Config not found; nothing to purge."
    fi
  fi

  warn "Note: PATH line in your shell rc was not removed (manual cleanup if desired)."
}

verify() {
  msg "Verification:"
  echo -e "Resolved 'claude' in PATH: ${CYAN}$(command -v claude || echo '<not found>')${NC}"
  if command -v claude >/dev/null 2>&1; then
    echo -e "${BOLD}Providers:${NC}"
    claude --list || true
  fi
}

# ========================
# Main (subcommands)
# ========================
CMD="install"
for a in "$@"; do
  case "$a" in
    install|update|uninstall|status) CMD="$a" ;;
    --purge) ;; # handled in cmd_uninstall
    -h|--help)
      cat <<EOF
Usage:
  $0 [command] [options]

Commands:
  install     Install or reinstall the wrapper (default if omitted)
  update      Update the wrapper to the latest version of this script
  uninstall   Remove the wrapper; optional --purge also removes config
  status      Show current resolution and config path

Options:
  --purge     With uninstall, also remove ${CONF_PATH}
  -h, --help  Show this help message
EOF
      exit 0 ;;
    *) ;;
  esac
done

case "$CMD" in
  install)
    msg "Step 1/5: Ensuring node & npm..."
    ensure_node_npm
    msg "Step 2/5: Ensuring official Claude Code CLI..."
    ensure_claude_code_cli
    msg "Step 3/5: Ensuring ~/bin in PATH..."
    ensure_path_prefix
    msg "Step 4/5: Writing wrapper..."
    write_wrapper
    msg "Step 5/5: Writing sample config (if missing)..."
    write_sample_conf_if_absent
    msg "✅ Installation complete."
    echo "Next: open a new terminal or run 'hash -r' and test 'claude --list'."
    verify
    ;;
  update)
    cmd_update
    ;;
  uninstall)
    cmd_uninstall "${2:-}"
    ;;
  status)
    cmd_status
    ;;
  *)
    err "Unknown command: $CMD" ;;
esac
