# Dev Environment Setup Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a one-command shell script that sets up a complete dev environment on a fresh Mac for all team members (product, design, dev, QA).

**Architecture:** Single `setup.sh` script reads config from `biz-repos.yaml` (parsed with `yq`), installs tools via Homebrew, configures Maven/SSH/env vars, and clones repos by business line. Every step is idempotent — already-installed tools are skipped, existing repos are not re-cloned.

**Tech Stack:** Bash, Homebrew, yq (YAML parser), Git, OpenJDK 8, Maven 3.9, Node.js 20, Tailscale

---

### Task 1: Create biz-repos.yaml config file

**Files:**
- Create: `setup/biz-repos.yaml`

- [ ] **Step 1: Create the setup directory and config file**

```bash
mkdir -p setup
```

Create `setup/biz-repos.yaml` with the following content:

```yaml
# GitLab 基础信息
gitlab:
  host: gitlab.yourcompany.com

# Tailscale login server URL
tailscale:
  login_server: https://your-tailscale-server.com

# 本地工作目录根路径
workspace: ~/workspace

# 业务线定义
businesses:
  - name: 订单系统
    key: order
    repos:
      - group: backend
        name: order-service
        ssh: git@gitlab.yourcompany.com:backend/order-service.git
      - group: backend
        name: payment-service
        ssh: git@gitlab.yourcompany.com:backend/payment-service.git
      - group: frontend
        name: order-web
        ssh: git@gitlab.yourcompany.com:frontend/order-web.git

  - name: 用户中心
    key: user
    repos:
      - group: backend
        name: user-service
        ssh: git@gitlab.yourcompany.com:backend/user-service.git
      - group: frontend
        name: user-web
        ssh: git@gitlab.yourcompany.com:frontend/user-web.git
```

- [ ] **Step 2: Validate YAML syntax**

Run: `yq eval '.' setup/biz-repos.yaml > /dev/null && echo "YAML valid"`
Expected: `YAML valid`

(If `yq` is not yet installed locally, run `brew install yq` first.)

- [ ] **Step 3: Commit**

```bash
git add setup/biz-repos.yaml
git commit -m "feat: add biz-repos.yaml config for dev env setup"
```

---

### Task 2: Create maven-settings.xml template

**Files:**
- Create: `setup/maven-settings.xml`

- [ ] **Step 1: Create the Maven settings template**

Create `setup/maven-settings.xml` with the following content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.2.0
                              https://maven.apache.org/xsd/settings-1.2.0.xsd">

  <mirrors>
    <mirror>
      <id>nexus</id>
      <mirrorOf>*</mirrorOf>
      <name>Company Nexus Mirror</name>
      <url>https://nexus.yourcompany.com/repository/maven-public/</url>
    </mirror>
  </mirrors>

  <profiles>
    <profile>
      <id>nexus</id>
      <repositories>
        <repository>
          <id>central</id>
          <url>https://nexus.yourcompany.com/repository/maven-public/</url>
          <releases><enabled>true</enabled></releases>
          <snapshots><enabled>true</enabled></snapshots>
        </repository>
      </repositories>
    </profile>
  </profiles>

  <activeProfiles>
    <activeProfile>nexus</activeProfile>
  </activeProfiles>

</settings>
```

- [ ] **Step 2: Validate XML syntax**

Run: `xmllint --noout setup/maven-settings.xml && echo "XML valid"`
Expected: `XML valid`

(`xmllint` is pre-installed on macOS.)

- [ ] **Step 3: Commit**

```bash
git add setup/maven-settings.xml
git commit -m "feat: add maven-settings.xml template with Nexus mirror"
```

---

### Task 3: Create setup.sh — logging helpers and pre-flight checks

This task creates the script skeleton with logging functions, color output, result tracking, and pre-flight checks (macOS detection, sudo).

**Files:**
- Create: `setup/setup.sh`

- [ ] **Step 1: Create setup.sh with header, logging helpers, and result tracking**

Create `setup/setup.sh` with the following content:

```bash
#!/bin/bash
set -euo pipefail

# =============================================================================
# 一键开发环境配置脚本
# 使用方式: bash setup/setup.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/biz-repos.yaml"
MAVEN_TEMPLATE="${SCRIPT_DIR}/maven-settings.xml"

# -- 颜色定义 --
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -- 结果追踪 --
RESULTS_SUCCESS=()
RESULTS_SKIPPED=()
RESULTS_FAILED=()

log_success() {
    RESULTS_SUCCESS+=("$1")
    echo -e "${GREEN}[✓]${NC} $1"
}

log_skip() {
    RESULTS_SKIPPED+=("$1")
    echo -e "${YELLOW}[✓]${NC} $1"
}

log_fail() {
    RESULTS_FAILED+=("$1")
    echo -e "${RED}[✗]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

print_summary() {
    echo ""
    echo "=========================================="
    echo " 安装结果汇总"
    echo "=========================================="

    if [[ ${#RESULTS_SUCCESS[@]} -gt 0 ]]; then
        echo -e "\n${GREEN}成功:${NC}"
        for item in "${RESULTS_SUCCESS[@]}"; do
            echo -e "  ${GREEN}[✓]${NC} ${item}"
        done
    fi

    if [[ ${#RESULTS_SKIPPED[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}跳过:${NC}"
        for item in "${RESULTS_SKIPPED[@]}"; do
            echo -e "  ${YELLOW}[✓]${NC} ${item}"
        done
    fi

    if [[ ${#RESULTS_FAILED[@]} -gt 0 ]]; then
        echo -e "\n${RED}失败:${NC}"
        for item in "${RESULTS_FAILED[@]}"; do
            echo -e "  ${RED}[✗]${NC} ${item}"
        done
        echo ""
        echo -e "${RED}请检查以上失败项并手动修复。${NC}"
    else
        echo ""
        echo -e "${GREEN}全部完成！${NC}"
    fi
}

# -- 前置检查 --
preflight_check() {
    # 检测 macOS
    if [[ "$(uname)" != "Darwin" ]]; then
        echo -e "${RED}错误：此脚本仅支持 macOS${NC}"
        exit 1
    fi

    # 检测配置文件
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo -e "${RED}错误：找不到配置文件 ${CONFIG_FILE}${NC}"
        exit 1
    fi

    log_info "macOS 检测通过，开始配置开发环境..."
    echo ""
}

# =============================================================================
# 主流程
# =============================================================================
main() {
    preflight_check
    print_summary
}

main "$@"
```

- [ ] **Step 2: Make executable and do a dry run**

Run:
```bash
chmod +x setup/setup.sh
bash setup/setup.sh
```

Expected: Prints the info line "macOS 检测通过，开始配置开发环境..." then the empty summary.

- [ ] **Step 3: Commit**

```bash
git add setup/setup.sh
git commit -m "feat: setup.sh skeleton with logging, result tracking, preflight checks"
```

---

### Task 4: Add Homebrew, Git, and yq installation

**Files:**
- Modify: `setup/setup.sh`

- [ ] **Step 1: Add install functions for Homebrew, Git, and yq**

Add these functions after the `preflight_check` function and before the `main` function in `setup/setup.sh`:

```bash
# -- 安装 Homebrew --
install_homebrew() {
    if command -v brew &>/dev/null; then
        log_skip "Homebrew 已安装，跳过"
        return 0
    fi

    log_info "正在安装 Homebrew..."
    if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        # Add brew to PATH for Apple Silicon
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        log_success "Homebrew 安装完成"
    else
        log_fail "Homebrew 安装失败"
        echo -e "${RED}Homebrew 是后续安装的基础，脚本终止。${NC}"
        print_summary
        exit 1
    fi
}

# -- 通用 brew install 函数 --
brew_install() {
    local formula="$1"
    local display_name="$2"
    local check_cmd="${3:-}"

    # If a check command is provided, use it to see if already installed
    if [[ -n "${check_cmd}" ]] && command -v "${check_cmd}" &>/dev/null; then
        log_skip "${display_name} 已安装，跳过"
        return 0
    fi

    # Fallback: check if brew knows about it
    if brew list "${formula}" &>/dev/null; then
        log_skip "${display_name} 已安装，跳过"
        return 0
    fi

    log_info "正在安装 ${display_name}..."
    if brew install "${formula}"; then
        log_success "${display_name} 安装完成"
    else
        log_fail "${display_name} 安装失败"
    fi
}

# -- 安装基础工具 --
install_base_tools() {
    brew_install "git" "Git" "git"
    brew_install "yq" "yq" "yq"
}
```

- [ ] **Step 2: Update main() to call these functions**

Replace the `main` function:

```bash
main() {
    preflight_check
    install_homebrew
    install_base_tools
    print_summary
}
```

- [ ] **Step 3: Test the script**

Run: `bash setup/setup.sh`

Expected: On a machine that already has Homebrew, Git, and yq, you should see three "已安装，跳过" lines followed by the summary.

- [ ] **Step 4: Commit**

```bash
git add setup/setup.sh
git commit -m "feat: add Homebrew, Git, yq installation to setup.sh"
```

---

### Task 5: Add Git user config (interactive)

**Files:**
- Modify: `setup/setup.sh`

- [ ] **Step 1: Add Git config function**

Add this function after `install_base_tools` in `setup/setup.sh`:

```bash
# -- 配置 Git 用户信息 --
configure_git() {
    log_info "配置 Git 用户信息..."

    local current_name
    local current_email
    current_name="$(git config --global user.name 2>/dev/null || echo "")"
    current_email="$(git config --global user.email 2>/dev/null || echo "")"

    if [[ -n "${current_name}" ]]; then
        echo -e "  当前 Git 用户名: ${GREEN}${current_name}${NC}"
        read -rp "  输入新用户名（按回车保留当前值）: " new_name
    else
        read -rp "  输入 Git 用户名: " new_name
    fi

    if [[ -n "${new_name}" ]]; then
        git config --global user.name "${new_name}"
    fi

    if [[ -n "${current_email}" ]]; then
        echo -e "  当前 Git 邮箱: ${GREEN}${current_email}${NC}"
        read -rp "  输入新邮箱（按回车保留当前值）: " new_email
    else
        read -rp "  输入 Git 邮箱: " new_email
    fi

    if [[ -n "${new_email}" ]]; then
        git config --global user.email "${new_email}"
    fi

    local final_name
    local final_email
    final_name="$(git config --global user.name)"
    final_email="$(git config --global user.email)"
    log_success "Git 用户配置完成 (${final_name} <${final_email}>)"
}
```

- [ ] **Step 2: Add call to main()**

Update `main()` to call `configure_git` after `install_base_tools`:

```bash
main() {
    preflight_check
    install_homebrew
    install_base_tools
    configure_git
    print_summary
}
```

- [ ] **Step 3: Test interactively**

Run: `bash setup/setup.sh`

Expected: After installing tools, prompts for Git user name/email. If already configured, shows current values and allows keeping them by pressing Enter.

- [ ] **Step 4: Commit**

```bash
git add setup/setup.sh
git commit -m "feat: add interactive Git user config to setup.sh"
```

---

### Task 6: Add OpenJDK 8, Maven, Node.js 20, Tailscale installation

**Files:**
- Modify: `setup/setup.sh`

- [ ] **Step 1: Add brew_install_cask helper and dev tools function**

Add this function after `configure_git`:

```bash
# -- 通用 brew cask install 函数 --
brew_install_cask() {
    local cask="$1"
    local display_name="$2"

    if brew list --cask "${cask}" &>/dev/null; then
        log_skip "${display_name} 已安装，跳过"
        return 0
    fi

    log_info "正在安装 ${display_name}..."
    if brew install --cask "${cask}"; then
        log_success "${display_name} 安装完成"
    else
        log_fail "${display_name} 安装失败"
    fi
}

# -- 安装开发工具 --
install_dev_tools() {
    # OpenJDK 8
    if /usr/libexec/java_home -v 1.8 &>/dev/null; then
        log_skip "OpenJDK 8 已安装，跳过"
    else
        log_info "正在安装 OpenJDK 8..."
        if brew install openjdk@8; then
            # Create symlink so macOS java_home can find it
            sudo ln -sfn "$(brew --prefix openjdk@8)/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk-8.jdk
            log_success "OpenJDK 8 安装完成"
        else
            log_fail "OpenJDK 8 安装失败"
        fi
    fi

    # Maven
    brew_install "maven" "Maven" "mvn"

    # Node.js 20
    if command -v node &>/dev/null && [[ "$(node --version)" == v20.* ]]; then
        log_skip "Node.js 20 已安装，跳过"
    else
        brew_install "node@20" "Node.js 20" ""
    fi

    # Tailscale
    brew_install_cask "tailscale" "Tailscale"
}
```

- [ ] **Step 2: Add Tailscale login function**

Add this function after `install_dev_tools`:

```bash
# -- 配置 Tailscale --
configure_tailscale() {
    if ! command -v tailscale &>/dev/null; then
        log_info "Tailscale 未安装，跳过登录配置"
        return 0
    fi

    local login_server
    login_server="$(yq eval '.tailscale.login_server' "${CONFIG_FILE}")"

    if [[ -z "${login_server}" || "${login_server}" == "null" ]]; then
        log_info "biz-repos.yaml 中未配置 tailscale.login_server，跳过"
        return 0
    fi

    # Check if already connected
    if tailscale status &>/dev/null; then
        log_skip "Tailscale 已连接，跳过"
        return 0
    fi

    log_info "正在登录 Tailscale（将打开浏览器进行认证）..."
    if tailscale login --login-server="${login_server}"; then
        log_success "Tailscale 登录完成"
    else
        log_fail "Tailscale 登录失败，请稍后手动执行: tailscale login --login-server=${login_server}"
    fi
}
```

- [ ] **Step 3: Update main()**

```bash
main() {
    preflight_check
    install_homebrew
    install_base_tools
    configure_git
    install_dev_tools
    configure_tailscale
    print_summary
}
```

- [ ] **Step 4: Test**

Run: `bash setup/setup.sh`

Expected: Tools that are already installed show "跳过". New tools get installed. Tailscale login triggers browser if not already connected.

- [ ] **Step 5: Commit**

```bash
git add setup/setup.sh
git commit -m "feat: add OpenJDK 8, Maven, Node.js 20, Tailscale to setup.sh"
```

---

### Task 7: Add Maven settings.xml config and environment variables

**Files:**
- Modify: `setup/setup.sh`

- [ ] **Step 1: Add Maven config and env vars functions**

Add these functions after `configure_tailscale`:

```bash
# -- 配置 Maven settings.xml --
configure_maven() {
    local m2_dir="${HOME}/.m2"
    local target="${m2_dir}/settings.xml"

    mkdir -p "${m2_dir}"

    if [[ -f "${target}" ]]; then
        # Check if it's already the same file
        if diff -q "${MAVEN_TEMPLATE}" "${target}" &>/dev/null; then
            log_skip "Maven settings.xml 已是最新，跳过"
            return 0
        fi
        # Backup existing
        cp "${target}" "${target}.bak"
        log_info "已备份现有 settings.xml → settings.xml.bak"
    fi

    cp "${MAVEN_TEMPLATE}" "${target}"
    log_success "Maven settings.xml 已配置"
}

# -- 配置环境变量 --
configure_env_vars() {
    local zshrc="${HOME}/.zshrc"
    local marker="# == harness-engineering dev env =="

    # Create .zshrc if it doesn't exist
    touch "${zshrc}"

    # Check if already configured
    if grep -q "${marker}" "${zshrc}"; then
        log_skip "环境变量已配置，跳过"
        return 0
    fi

    cat >> "${zshrc}" << 'EOF'

# == harness-engineering dev env ==
# OpenJDK 8
export JAVA_HOME=$(/usr/libexec/java_home -v 1.8 2>/dev/null)
export PATH="$JAVA_HOME/bin:$PATH"

# Node.js 20
export PATH="/opt/homebrew/opt/node@20/bin:$PATH"
# == end harness-engineering dev env ==
EOF

    log_success "环境变量已写入 ~/.zshrc"
}
```

- [ ] **Step 2: Update main()**

```bash
main() {
    preflight_check
    install_homebrew
    install_base_tools
    configure_git
    install_dev_tools
    configure_tailscale
    configure_maven
    configure_env_vars
    print_summary
}
```

- [ ] **Step 3: Test Maven config**

Run:
```bash
bash setup/setup.sh
cat ~/.m2/settings.xml | head -5
```

Expected: First 5 lines of the maven-settings.xml template. If it was already there, you should see the "跳过" message.

- [ ] **Step 4: Test env vars (idempotency)**

Run the script twice:
```bash
bash setup/setup.sh
bash setup/setup.sh
```

Expected: Second run shows "环境变量已配置，跳过" — the marker comment prevents duplicate entries.

- [ ] **Step 5: Commit**

```bash
git add setup/setup.sh
git commit -m "feat: add Maven settings.xml config and env vars to setup.sh"
```

---

### Task 8: Add SSH key generation

**Files:**
- Modify: `setup/setup.sh`

- [ ] **Step 1: Add SSH key function**

Add this function after `configure_env_vars`:

```bash
# -- 配置 SSH Key --
configure_ssh_key() {
    local ssh_key="${HOME}/.ssh/id_ed25519"

    if [[ -f "${ssh_key}" ]]; then
        log_skip "SSH Key 已存在，跳过"
        echo -e "  公钥: $(cat "${ssh_key}.pub")"
        return 0
    fi

    log_info "正在生成 SSH Key..."
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"

    local email
    email="$(git config --global user.email 2>/dev/null || echo "")"

    if [[ -n "${email}" ]]; then
        ssh-keygen -t ed25519 -C "${email}" -f "${ssh_key}" -N ""
    else
        ssh-keygen -t ed25519 -f "${ssh_key}" -N ""
    fi

    log_success "SSH Key 已生成"
    echo ""
    echo -e "${BLUE}请将以下公钥添加到 GitLab:${NC}"
    echo ""
    cat "${ssh_key}.pub"
    echo ""

    local gitlab_host
    gitlab_host="$(yq eval '.gitlab.host' "${CONFIG_FILE}")"
    if [[ -n "${gitlab_host}" && "${gitlab_host}" != "null" ]]; then
        echo -e "GitLab SSH Key 设置页面: ${BLUE}https://${gitlab_host}/-/user_settings/ssh_keys${NC}"
    fi

    echo ""
    read -rp "添加完成后按回车继续..."
}
```

- [ ] **Step 2: Update main()**

```bash
main() {
    preflight_check
    install_homebrew
    install_base_tools
    configure_git
    install_dev_tools
    configure_tailscale
    configure_maven
    configure_env_vars
    configure_ssh_key
    print_summary
}
```

- [ ] **Step 3: Test**

Run: `bash setup/setup.sh`

Expected: If `~/.ssh/id_ed25519` already exists, shows "跳过" and prints the existing public key. If not, generates a new key, prints the public key, shows the GitLab URL, and waits for Enter.

- [ ] **Step 4: Commit**

```bash
git add setup/setup.sh
git commit -m "feat: add SSH key generation to setup.sh"
```

---

### Task 9: Add business line repo cloning

**Files:**
- Modify: `setup/setup.sh`

- [ ] **Step 1: Add repo cloning function**

Add this function after `configure_ssh_key`:

```bash
# -- Clone 业务线 Repo --
clone_repos() {
    local workspace
    workspace="$(yq eval '.workspace' "${CONFIG_FILE}")"
    # Expand ~ to $HOME
    workspace="${workspace/#\~/$HOME}"

    local biz_count
    biz_count="$(yq eval '.businesses | length' "${CONFIG_FILE}")"

    if [[ "${biz_count}" -eq 0 ]]; then
        log_info "biz-repos.yaml 中没有定义业务线"
        return 0
    fi

    echo ""
    echo "请选择要克隆的业务线："

    local biz_names=()
    for ((i = 0; i < biz_count; i++)); do
        local name
        name="$(yq eval ".businesses[${i}].name" "${CONFIG_FILE}")"
        biz_names+=("${name}")
        echo "  $((i + 1))) ${name}"
    done
    echo "  $((biz_count + 1))) 全部"
    echo ""

    read -rp "请输入序号（多选用空格分隔）: " -a selections

    # Determine which business lines to clone
    local selected_indices=()
    for sel in "${selections[@]}"; do
        if [[ "${sel}" -eq $((biz_count + 1)) ]]; then
            # "全部" selected
            selected_indices=()
            for ((i = 0; i < biz_count; i++)); do
                selected_indices+=("${i}")
            done
            break
        elif [[ "${sel}" -ge 1 && "${sel}" -le "${biz_count}" ]]; then
            selected_indices+=("$((sel - 1))")
        else
            log_fail "无效的序号: ${sel}"
        fi
    done

    if [[ ${#selected_indices[@]} -eq 0 ]]; then
        log_info "未选择任何业务线，跳过克隆"
        return 0
    fi

    # Clone repos for each selected business line
    for idx in "${selected_indices[@]}"; do
        local biz_name biz_key repo_count
        biz_name="$(yq eval ".businesses[${idx}].name" "${CONFIG_FILE}")"
        biz_key="$(yq eval ".businesses[${idx}].key" "${CONFIG_FILE}")"
        repo_count="$(yq eval ".businesses[${idx}].repos | length" "${CONFIG_FILE}")"

        local biz_dir="${workspace}/${biz_key}"
        mkdir -p "${biz_dir}"

        log_info "克隆业务线: ${biz_name} → ${biz_dir}"

        for ((r = 0; r < repo_count; r++)); do
            local repo_name repo_ssh
            repo_name="$(yq eval ".businesses[${idx}].repos[${r}].name" "${CONFIG_FILE}")"
            repo_ssh="$(yq eval ".businesses[${idx}].repos[${r}].ssh" "${CONFIG_FILE}")"

            local repo_dir="${biz_dir}/${repo_name}"
            if [[ -d "${repo_dir}" ]]; then
                log_skip "  ${repo_name} 已存在，跳过"
                continue
            fi

            if git clone "${repo_ssh}" "${repo_dir}"; then
                log_success "  ${repo_name} 克隆完成"
            else
                log_fail "  ${repo_name} 克隆失败"
            fi
        done
    done
}
```

- [ ] **Step 2: Update main()**

```bash
main() {
    preflight_check
    install_homebrew
    install_base_tools
    configure_git
    install_dev_tools
    configure_tailscale
    configure_maven
    configure_env_vars
    configure_ssh_key
    clone_repos
    print_summary
}
```

- [ ] **Step 3: Test with dry observation**

Run: `bash setup/setup.sh`

Expected: After all installation steps, displays the business line menu. Selecting a business line creates the workspace directory and attempts to clone repos (will fail if SSH key isn't added to GitLab or repos don't exist yet, but the flow and directory creation should work).

- [ ] **Step 4: Commit**

```bash
git add setup/setup.sh
git commit -m "feat: add business line repo cloning to setup.sh"
```

---

### Task 10: Final integration test and cleanup

**Files:**
- Review: `setup/setup.sh`
- Review: `setup/biz-repos.yaml`
- Review: `setup/maven-settings.xml`

- [ ] **Step 1: Full script review**

Read through the complete `setup/setup.sh` from top to bottom. Verify:
- All functions are called in the correct order in `main()`
- No syntax errors (run `bash -n setup/setup.sh` to check)
- Log output is consistent (all Chinese, matching the spec's log style)

Run: `bash -n setup/setup.sh && echo "Syntax OK"`
Expected: `Syntax OK`

- [ ] **Step 2: Full dry run**

Run: `bash setup/setup.sh`

Walk through the entire flow:
1. Pre-flight check passes (macOS)
2. Homebrew/Git/yq — installed or skipped
3. Git user config — prompts or shows current values
4. Dev tools — installed or skipped
5. Tailscale login — triggered or skipped
6. Maven settings.xml — copied or skipped
7. Env vars — written or skipped
8. SSH key — generated or skipped
9. Business line menu — displayed, selection works
10. Summary — all items categorized correctly

- [ ] **Step 3: Idempotency test**

Run the script a second time: `bash setup/setup.sh`

Expected: Everything shows "跳过" (skipped), no duplicate env vars in `~/.zshrc`, no duplicate Maven backup, no errors.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete dev environment setup script

One-command dev env setup for the full team (product, design, dev, QA).
Installs Homebrew, Git, OpenJDK 8, Maven 3.9, Node.js 20, Tailscale.
Configures Maven Nexus mirror, SSH keys, env vars, and clones repos by business line."
```
