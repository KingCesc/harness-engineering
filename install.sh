#!/bin/zsh
# =============================================================================
# harness-engineering 一键安装引导脚本
#
# 使用方式:
#   curl -fsSL https://raw.githubusercontent.com/KingCesc/harness-engineering/master/install.sh | zsh
# =============================================================================

set -u

REPO_URL="https://github.com/KingCesc/harness-engineering.git"
INSTALL_DIR="${HOME}/.harness-engineering"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

printf "${BLUE}[i]${NC} harness-engineering 开发环境一键配置\n"
echo ""

# 检测 git
if ! command -v git &>/dev/null; then
    # 尝试安装 Xcode Command Line Tools（会自带 git）
    printf "${BLUE}[i]${NC} 未检测到 git，正在安装 Xcode Command Line Tools...\n"
    xcode-select --install 2>/dev/null
    printf "${RED}请在弹窗中确认安装，完成后重新运行此命令。${NC}\n"
    exit 1
fi

# Clone 或更新仓库
if [[ -d "${INSTALL_DIR}" ]]; then
    printf "${BLUE}[i]${NC} 更新 harness-engineering...\n"
    git -C "${INSTALL_DIR}" pull --ff-only 2>/dev/null || true
else
    printf "${BLUE}[i]${NC} 下载 harness-engineering...\n"
    git clone "${REPO_URL}" "${INSTALL_DIR}"
fi

# 运行 setup 脚本
printf "${GREEN}[✓]${NC} 下载完成，开始配置开发环境...\n"
echo ""
exec zsh "${INSTALL_DIR}/setup/setup.sh"
