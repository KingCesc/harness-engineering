#!/bin/zsh
set -uo pipefail

# =============================================================================
# 一键开发环境配置脚本
# 使用方式: zsh setup/setup.sh 或 ./setup/setup.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
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
    printf "${GREEN}[✓]${NC} %s\n" "$1"
}

log_skip() {
    RESULTS_SKIPPED+=("$1")
    printf "${YELLOW}[✓]${NC} %s\n" "$1"
}

log_fail() {
    RESULTS_FAILED+=("$1")
    printf "${RED}[✗]${NC} %s\n" "$1"
}

log_info() {
    printf "${BLUE}[i]${NC} %s\n" "$1"
}

print_summary() {
    echo ""
    echo "=========================================="
    echo " 安装结果汇总"
    echo "=========================================="

    if [[ ${#RESULTS_SUCCESS[@]} -gt 0 ]]; then
        printf "\n${GREEN}成功:${NC}\n"
        for item in "${RESULTS_SUCCESS[@]}"; do
            printf "  ${GREEN}[✓]${NC} %s\n" "${item}"
        done
    fi

    if [[ ${#RESULTS_SKIPPED[@]} -gt 0 ]]; then
        printf "\n${YELLOW}跳过:${NC}\n"
        for item in "${RESULTS_SKIPPED[@]}"; do
            printf "  ${YELLOW}[✓]${NC} %s\n" "${item}"
        done
    fi

    if [[ ${#RESULTS_FAILED[@]} -gt 0 ]]; then
        printf "\n${RED}失败:${NC}\n"
        for item in "${RESULTS_FAILED[@]}"; do
            printf "  ${RED}[✗]${NC} %s\n" "${item}"
        done
        echo ""
        printf "${RED}请检查以上失败项并手动修复。${NC}\n"
    else
        echo ""
        printf "${GREEN}全部完成！${NC}\n"
    fi
}

# -- 前置检查 --
preflight_check() {
    # 检测 macOS
    if [[ "$(uname)" != "Darwin" ]]; then
        printf "${RED}错误：此脚本仅支持 macOS${NC}\n"
        exit 1
    fi

    # 检测配置文件
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        printf "${RED}错误：找不到配置文件 ${CONFIG_FILE}${NC}\n"
        exit 1
    fi

    log_info "macOS 检测通过，开始配置开发环境..."
    echo ""
}

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
        printf "${RED}Homebrew 是后续安装的基础，脚本终止。${NC}\n"
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

# -- 配置 Git 用户信息 --
configure_git() {
    local current_name current_email
    current_name="$(git config --global user.name 2>/dev/null || echo "")"
    current_email="$(git config --global user.email 2>/dev/null || echo "")"

    if [[ -n "${current_name}" && -n "${current_email}" ]]; then
        log_skip "Git 用户已配置 (${current_name} <${current_email}>)，跳过"
        return 0
    fi

    log_info "配置 Git 用户信息..."

    if [[ -z "${current_name}" ]]; then
        local new_name=""
        read -r "new_name?  输入 Git 用户名: "
        if [[ -n "${new_name}" ]]; then
            git config --global user.name "${new_name}"
        fi
    fi

    if [[ -z "${current_email}" ]]; then
        local new_email=""
        read -r "new_email?  输入 Git 邮箱: "
        if [[ -n "${new_email}" ]]; then
            git config --global user.email "${new_email}"
        fi
    fi

    local final_name final_email
    final_name="$(git config --global user.name 2>/dev/null || echo "")"
    final_email="$(git config --global user.email 2>/dev/null || echo "")"
    log_success "Git 用户配置完成 (${final_name} <${final_email}>)"
}

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
            if sudo ln -sfn "$(brew --prefix openjdk@8)/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk-8.jdk; then
                log_success "OpenJDK 8 安装完成"
            else
                log_success "OpenJDK 8 安装完成（symlink 创建失败，可能需要手动执行 sudo 命令）"
            fi
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

    # Check if already logged in (look for actual peer/IP info in status output)
    local ts_status
    ts_status="$(tailscale status 2>&1 || true)"
    if echo "${ts_status}" | grep -q "^100\." ; then
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

    local brew_prefix
    brew_prefix="$(brew --prefix)"

    cat >> "${zshrc}" << EOF

# == harness-engineering dev env ==
# OpenJDK 8
export JAVA_HOME=\$(/usr/libexec/java_home -v 1.8 2>/dev/null)
export PATH="\$JAVA_HOME/bin:\$PATH"

# Node.js 20
export PATH="${brew_prefix}/opt/node@20/bin:\$PATH"
# == end harness-engineering dev env ==
EOF

    log_success "环境变量已写入 ~/.zshrc"
}

# -- 配置 SSH Key --
configure_ssh_key() {
    local ssh_key="${HOME}/.ssh/id_ed25519"

    if [[ -f "${ssh_key}" ]]; then
        log_skip "SSH Key 已存在，跳过"
        printf "  公钥: %s\n" "$(cat "${ssh_key}.pub")"
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
    printf "${BLUE}请将以下公钥添加到 GitLab:${NC}\n"
    echo ""
    cat "${ssh_key}.pub"
    echo ""

    local gitlab_host
    gitlab_host="$(yq eval '.gitlab.host' "${CONFIG_FILE}")"
    if [[ -n "${gitlab_host}" && "${gitlab_host}" != "null" ]]; then
        printf "GitLab SSH Key 设置页面: ${BLUE}https://${gitlab_host}/-/user_settings/ssh_keys${NC}\n"
    fi

    echo ""
    read -r "?添加完成后按回车继续..."
}

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

    local input=""
    read -r "input?请输入序号（多选用空格分隔）: " || true
    local selections=(${=input})

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

# =============================================================================
# 主流程
# =============================================================================
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

main "$@"
