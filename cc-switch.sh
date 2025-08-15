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
  npm i -g @anthropic-ai/claude-code >/dev/null 2>&1 || npm i -g @anthropic-ai/claude-code
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

# Inject ANTHROPIC_* from INI if provider present
if [[ -n "$provider" ]]; then
  base_url=$(awk -F '=' -v sec="[$provider]" '
    $0==sec {f=1; next} /^\[/{f=0}
    f && $1=="BASE_URL" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}
  ' "$CONFIG" 2>/dev/null || true)

  api_key=$(awk -F '=' -v sec="[$provider]" '
    $0==sec {f=1; next} /^\[/{f=0}
    f && $1=="API_KEY" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}
  ' "$CONFIG" 2>/dev/null || true)

  if [[ -n "${base_url:-}" && -n "${api_key:-}" ]]; then
    export ANTHROPIC_BASE_URL="$base_url"
    export ANTHROPIC_AUTH_TOKEN="$api_key"
    >&2 echo ">>> Using provider: $provider"
  else
    echo "✖ Provider [$provider] has incomplete config (needs BASE_URL and API_KEY)." >&2
    exit 1
  fi
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
BASE_URL=https://api.moonshot.cn/anthropic/
API_KEY=sk-xxxxxxxxxxxxxxxx

[glm]
BASE_URL=https://open.bigmodel.cn/api/anthropic/
API_KEY=xxxxxxxxxxxxxxxx
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
