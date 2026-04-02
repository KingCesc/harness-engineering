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

# =============================================================================
# 主流程
# =============================================================================
main() {
    preflight_check
    install_homebrew
    install_base_tools
    configure_git
    print_summary
}

main "$@"
