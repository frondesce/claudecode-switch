#!/usr/bin/env bash
set -euo pipefail

# ========================
# Config
# ========================
TARGET_HOME="${HOME}"
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
  ALT_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  [ -n "$ALT_HOME" ] && TARGET_HOME="$ALT_HOME"
fi

WRAPPER_PATH="${TARGET_HOME}/bin/claude"
CONF_PATH="${TARGET_HOME}/.claude_providers.ini"
MIN_NODE_VERSION="20.0.0"
NODE_MAJOR="20"
NODE_DISTRO_URL="https://deb.nodesource.com/setup_20.x"
DEBUG_FLAG="${CLAUDE_SWITCH_DEBUG:-0}"
NODE_GLIBC_INCOMPAT="0"
GLIBC_BELOW_228="0"
CURL_ATTEMPTED=0

# ========================
# Colors
# ========================
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NC="\033[0m"

[ "$DEBUG_FLAG" != "0" ] && set -x

# ========================
# Helpers
# ========================
msg()  { printf "${GREEN}%s${NC}\n" "$*"; }
warn() { printf "${YELLOW}%s${NC}\n" "$*"; }
err()  { printf "${RED}%s${NC}\n" "$*" >&2; }
dbg()  {
  if [ "$DEBUG_FLAG" != "0" ]; then
    printf "[DEBUG] %s\n" "$*" >&2
  fi
  return 0
}
have_cmd() { command -v "$1" >/dev/null 2>&1; }
can_sudo() { have_cmd sudo && sudo -n true 2>/dev/null; }
is_root() { [ "$(id -u)" -eq 0 ]; }

find_claude_on_path() {
  local self_path="$1"
  local entry candidate
  local -a path_entries
  IFS=':' read -r -a path_entries <<< "${PATH:-}"
  for entry in "${path_entries[@]}"; do
    [ -z "$entry" ] && continue
    candidate="${entry%/}/claude"
    if [ -x "$candidate" ] && [ "$candidate" != "$self_path" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

find_claude_executable() {
  local self_path="$1"
  local candidate
  local known=(
    "${HOME}/.local/bin/claude"
    "${HOME}/.claude/bin/claude"
    "/usr/local/bin/claude"
    "/usr/bin/claude"
    "/opt/homebrew/bin/claude"
  )
  for candidate in "${known[@]}"; do
    if [ -x "$candidate" ] && [ "$candidate" != "$self_path" ]; then
      echo "$candidate"
      return 0
    fi
  done
  if candidate="$(find_claude_on_path "$self_path")"; then
    echo "$candidate"
    return 0
  fi
  return 1
}

append_once() {
  # append_once <file> <line>
  local f="$1" line="$2"
  [ -f "$f" ] || touch "$f"
  grep -Fqx "$line" "$f" || printf "%s\n" "$line" >> "$f"
}

detect_shell_rc() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    echo "${TARGET_HOME}/.zshrc"
  elif [ -n "${BASH_VERSION:-}" ]; then
    echo "${TARGET_HOME}/.bashrc"
  else
    echo "${TARGET_HOME}/.bashrc"
  fi
}

detect_glibc_version() {
  local v
  v="$(ldd --version 2>&1 | head -n1 | sed -E 's/.* ([0-9]+\.[0-9]+).*/\1/')" || true
  echo "${v}"
}

glibc_lt_2_28() {
  local v; v="$(detect_glibc_version)"
  [[ -z "$v" ]] && return 1
  if [[ "$(printf "%s\n%s\n" "2.28" "$v" | sort -V | head -n1)" == "$v" ]] && [[ "$v" != "2.28" ]]; then
    return 0
  fi
  return 1
}

set_node_version_defaults() {
  # Default to Node 20; fall back to 18 on older glibc
  MIN_NODE_VERSION="20.0.0"
  NODE_MAJOR="20"
  NODE_DISTRO_URL="https://deb.nodesource.com/setup_20.x"
  GLIBC_BELOW_228="0"

  if glibc_lt_2_28; then
    warn "Detected glibc < 2.28; falling back to Node 18 for compatibility."
    MIN_NODE_VERSION="18.0.0"
    NODE_MAJOR="18"
    NODE_DISTRO_URL="https://deb.nodesource.com/setup_18.x"
    GLIBC_BELOW_228="1"
  fi
}

ensure_path_prefix() {
  local rc; rc="$(detect_shell_rc)"
  mkdir -p "${TARGET_HOME}/bin"
  local export_line='export PATH="$TARGET_HOME/bin:$PATH"'
  append_once "$rc" "$export_line"
  # idempotent patch to common rc files
  [ "$rc" != "${TARGET_HOME}/.bashrc" ] && [ -f "${TARGET_HOME}/.bashrc" ] && append_once "${TARGET_HOME}/.bashrc" "$export_line"
  [ "$rc" != "${TARGET_HOME}/.zshrc" ] && [ -f "${TARGET_HOME}/.zshrc" ] && append_once "${TARGET_HOME}/.zshrc" "$export_line"
  export PATH="${TARGET_HOME}/bin:$PATH"
}

ensure_curl() {
  if [ "$CURL_ATTEMPTED" -eq 1 ]; then
    if have_cmd curl; then return 0; else warn "curl still missing (skipping repeated prompts)."; return 1; fi
  fi
  CURL_ATTEMPTED=1

  if have_cmd curl; then
    return 0
  fi

  local installer=""
  if have_cmd apt && (can_sudo || is_root); then installer="apt"; fi
  if have_cmd yum && (can_sudo || is_root); then installer="yum"; fi
  if have_cmd pacman && (can_sudo || is_root); then installer="pacman"; fi

  if [[ -z "$installer" ]]; then
    warn "curl not found and no usable package manager/sudo to auto-install."
    return 1
  fi

  read -r -p "curl not found. Install curl via ${installer}? [Y/n]: " ans
  case "$ans" in
    n|N|no|NO) warn "Skipping curl install. Please install curl or node ${MIN_NODE_VERSION}+ manually."; return 1 ;;
  esac

  case "$installer" in
    apt) if is_root; then apt update && apt install -y curl; else sudo apt update && sudo apt install -y curl; fi ;;
    yum) if is_root; then yum install -y curl; else sudo yum install -y curl; fi ;;
    pacman) if is_root; then pacman -Sy --noconfirm curl; else sudo pacman -Sy --noconfirm curl; fi ;;
  esac

  if have_cmd curl; then
    msg "curl installed via ${installer}."
    return 0
  fi

  warn "Failed to install curl via ${installer}. Please install manually."
  return 1
}

load_nvm_env() {
  export NVM_DIR="${NVM_DIR:-$TARGET_HOME/.nvm}"
  if [ -s "${NVM_DIR}/nvm.sh" ]; then
    # shellcheck disable=SC1090
    . "${NVM_DIR}/nvm.sh"
    # shellcheck disable=SC1090
    [ -s "${NVM_DIR}/bash_completion" ] && . "${NVM_DIR}/bash_completion"
    return 0
  fi
  return 1
}

set_nvm_path_if_valid() {
  local ver bin latest_dir
  shopt -s nullglob
  local dirs=( "${TARGET_HOME}/.nvm/versions/node"/v"${NODE_MAJOR}."* )
  shopt -u nullglob
  if (( ${#dirs[@]} == 0 )); then
    return 1
  fi
  latest_dir="$(printf '%s\n' "${dirs[@]}" | sort -V | tail -n1)"
  [[ -z "$latest_dir" ]] && return 1
  bin="${latest_dir%/}/bin"
  [[ -x "${bin}/node" ]] || return 1
  ver="$("${bin}/node" -v 2>/dev/null || true)"
  ver="${ver#v}"
  [[ -z "$ver" ]] && return 1
  if [[ "$(printf "%s\n%s\n" "$MIN_NODE_VERSION" "$ver" | sort -V | head -n1)" != "$MIN_NODE_VERSION" ]]; then
    return 1
  fi
  export PATH="${bin}:${PATH}"
  hash -r
  return 0
}

# ------------------------
# Node installation
# ------------------------
install_node_with_pkgmgr() {
  if [[ "$GLIBC_BELOW_228" == "1" ]]; then
    warn "glibc < 2.28 detected; skipping package-manager binaries and using NVM source build instead."
    return 1
  fi
  if have_cmd apt && can_sudo; then
    ensure_curl || return 1
    msg "Installing node via apt (NodeSource ${NODE_MAJOR}.x)..."
    curl -fsSL "${NODE_DISTRO_URL}" | sudo -E bash -
    sudo apt install -y nodejs
    return 0
  fi
  if have_cmd yum && can_sudo; then
    msg "Installing node via yum..."
    sudo yum install -y nodejs
    return 0
  fi
  if have_cmd pacman && can_sudo; then
    msg "Installing node via pacman..."
    sudo pacman -Sy --noconfirm nodejs
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
  msg "Installing node via NVM (no sudo required)..."
  if ! have_cmd curl; then
    warn "curl not found; cannot fetch nvm installer. Install curl or node ${MIN_NODE_VERSION}+ manually."
    return 1
  fi
  export NVM_DIR="${TARGET_HOME}/.nvm"
  if [ ! -s "${NVM_DIR}/nvm.sh" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  load_nvm_env || return 1
  dbg "Using NVM at ${NVM_DIR}"
  if [[ "$GLIBC_BELOW_228" == "1" ]]; then
    # Avoid glibc-mismatched prebuilt binaries; build from source directly.
    nvm install -s "${NODE_MAJOR}" || return 1
  else
    nvm install "${NODE_MAJOR}" || {
      warn "nvm install ${NODE_MAJOR} failed. Retrying with mirror NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node ..."
      NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node nvm install "${NODE_MAJOR}" || return 1
    }
  fi
  nvm use "${NODE_MAJOR}" || return 1
}

install_node_with_nvm_source() {
  msg "Retrying nvm install ${NODE_MAJOR} from source (may take several minutes)..."
  load_nvm_env || return 1
  nvm install -s "${NODE_MAJOR}" || return 1
  nvm use "${NODE_MAJOR}" || return 1
}

try_nvm_source_build() {
  if install_node_with_nvm_source; then
    load_nvm_env && nvm use "${NODE_MAJOR}" >/dev/null 2>&1 || true
    hash -r
    if have_cmd node && node_version_ok; then
      msg "Installed node via NVM (source build): $(node -v)"
      return 0
    fi
  fi
  return 1
}

node_version_ok() {
  local ver out
  out="$(node -v 2>&1 || true)"
  dbg "node_version_ok: raw_output='${out}'"
  ver="${out#v}"
  [[ -z "$ver" ]] && return 1
  # If the output still contains GLIBC warnings or non-version strings, treat as invalid
  if [[ "$out" =~ GLIBC_ ]]; then
    warn "node binary appears incompatible with current glibc (output: $out)"
    NODE_GLIBC_INCOMPAT="1"
    return 1
  fi
  if [[ "$(printf "%s\n%s\n" "$MIN_NODE_VERSION" "$ver" | sort -V | head -n1)" == "$MIN_NODE_VERSION" ]]; then
    return 0
  fi
  return 1
}

ensure_node() {
  local _had_errexit=0
  case "$-" in *e*) _had_errexit=1; set +e ;; esac
  restore_errexit() { [ "$_had_errexit" -eq 1 ] && set -e; }
  set_node_version_defaults
  NODE_GLIBC_INCOMPAT="0"
  dbg "ensure_node: user=$USER sudo_user=${SUDO_USER:-} target_home=$TARGET_HOME PATH=$PATH"
  local attempted_source_build=0
  local current_node
  current_node="$(command -v node 2>/dev/null || true)"
  dbg "ensure_node: current node=${current_node:-<none>} version=$(node -v 2>/dev/null || echo '-')"
  dbg "ensure_node: start"

  if set_nvm_path_if_valid && have_cmd node; then
    if node_version_ok; then
      msg "node found (nvm): $(node -v)"
      dbg "ensure_node: early success via nvm path"
      restore_errexit; return 0
    else
      warn "node found via nvm path but version/compatibility check failed; continuing installation..."
    fi
  fi

  if have_cmd node; then
    if node_version_ok; then
      msg "node found: $(node -v)"
      dbg "ensure_node: success with existing node"
      restore_errexit; return 0
    else
      warn "node found but version is below ${MIN_NODE_VERSION}: $(node -v). Attempting to install/upgrade..."
      if [[ "$NODE_GLIBC_INCOMPAT" == "1" ]]; then
        warn "Detected glibc mismatch with existing node. Attempting NVM source build..."
        attempted_source_build=1
        if try_nvm_source_build; then
          restore_errexit; return 0
        fi
      fi
    fi
  fi

  if ! have_cmd curl; then
    if ! ensure_curl; then
      err "curl is required to install Node automatically. Please install curl and re-run."
      restore_errexit; exit 1
    fi
  fi

  warn "node not found or too old. Attempting installation..."
  if install_node_with_pkgmgr && have_cmd node && node_version_ok; then
    msg "Installed node via package manager: $(node -v)"
    dbg "ensure_node: success via pkgmgr"
    restore_errexit; return 0
  elif have_cmd node && ! node_version_ok; then
    warn "Package manager provided node $(node -v), which is below ${MIN_NODE_VERSION}. Falling back to NVM..."
  fi

  if install_node_with_nvm; then
    load_nvm_env && nvm use "${NODE_MAJOR}" >/dev/null 2>&1 || true
    # ensure PATH includes the selected nvm node bin even under sudo
    if command -v nvm >/dev/null 2>&1; then
      local nvm_node_bin
      nvm_node_bin="$(nvm which current 2>/dev/null || true)"
      if [[ -n "$nvm_node_bin" ]]; then
        nvm_node_bin="${nvm_node_bin%/node}"
        export PATH="${nvm_node_bin}:${PATH}"
      fi
    fi
    hash -r
    if have_cmd node && node_version_ok; then
      msg "Installed node via NVM: $(node -v)"
      dbg "ensure_node: success via nvm after install"
      restore_errexit; return 0
    fi
    if set_nvm_path_if_valid && have_cmd node; then
      msg "Installed node via NVM: $(node -v)"
      dbg "ensure_node: success via set_nvm_path_if_valid after install"
      restore_errexit; return 0
    fi
    if [[ "$NODE_GLIBC_INCOMPAT" == "1" ]]; then
      warn "NVM binary install is incompatible with current glibc; trying source build..."
      attempted_source_build=1
      if try_nvm_source_build; then
        restore_errexit; return 0
      fi
    else
      warn "NVM binary install may be incompatible; trying source build..."
      attempted_source_build=1
      if try_nvm_source_build; then
        restore_errexit; return 0
      fi
    fi
  fi
  if [[ "$NODE_GLIBC_INCOMPAT" == "1" && "$attempted_source_build" -eq 0 ]]; then
    warn "Detected glibc mismatch; attempting NVM source build as final fallback..."
    if try_nvm_source_build; then
      restore_errexit; return 0
    fi
  fi
  dbg "ensure_node: end (failure path)"
  dbg "Final PATH=$PATH"
  dbg "node=$(command -v node || echo '<none>') version=$(node -v 2>/dev/null || echo '<none>')"
  err "Failed to install/upgrade node to ${MIN_NODE_VERSION}+ automatically. Please install manually and re-run. (Set CLAUDE_SWITCH_DEBUG=1 for verbose logs)"
  if [[ $_had_errexit -eq 1 ]]; then set -e; fi
  exit 1
}

ensure_claude_code_cli() {
  msg "Ensuring Claude Code CLI is installed (official installer)..."
  local existing
  existing="$(find_claude_executable "$WRAPPER_PATH" || true)"
  if [ -n "$existing" ]; then
    msg "Claude Code CLI already found: ${existing}"
    return
  fi

  if ! have_cmd curl; then
    if ! ensure_curl; then
      err "curl is required to install Claude Code CLI automatically."
      exit 1
    fi
  fi

  msg "Installing Claude Code CLI via official installer..."
  if curl -fsSL https://claude.ai/install.sh | bash; then
    return
  fi

  err "Failed to install Claude Code CLI automatically."
  exit 1
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
provider=""
if [[ -n "${1:-}" && "${1}" != -* && "${1}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  provider="${1}"
  shift
fi
if [[ -z "$provider" ]]; then
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
console.error(`>>> Using provider: ${process.env.PROVIDER}`);
NODE
fi

# ---- locate official CLI (absolute paths to avoid recursion) ----
SELF_PATH="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

find_on_path() {
  local entry candidate
  local -a path_entries
  IFS=':' read -r -a path_entries <<< "${PATH:-}"
  for entry in "${path_entries[@]}"; do
    [ -z "$entry" ] && continue
    candidate="${entry%/}/claude"
    if [[ -x "$candidate" && "$candidate" != "$SELF_PATH" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

CANDIDATES=(
  "$HOME/.local/bin/claude"
  "$HOME/.claude/bin/claude"
  "/usr/local/bin/claude"
  "/usr/bin/claude"
  "/opt/homebrew/bin/claude"
)

if found="$(find_on_path)"; then
  CANDIDATES+=("$found")
fi

for p in "${CANDIDATES[@]}"; do
  if [[ -x "$p" ]]; then
    exec "$p" "$@"
  fi
done

echo "Official Claude CLI not found. Please install: curl -fsSL https://claude.ai/install.sh | bash" >&2
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
    msg "Step 1/5: Ensuring node..."
    ensure_node
    dbg "Step 1 completed"
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
