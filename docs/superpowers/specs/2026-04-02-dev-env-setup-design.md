# 一键开发环境配置脚本设计

## 背景

harness-engineering 项目的第一步：为全产研团队（产品、设计、研发、测试，约 50 人）提供一键配置开发环境的能力。团队统一使用 macOS，代码托管在私有 GitLab（SSH 访问），一个业务涉及 6-7 个项目。

### 目标

- 零前置条件：在全新 Mac 上运行一个命令即可完成全部配置
- 非技术人员友好：产品经理也能独立完成
- 幂等安全：重复运行不破坏已有配置
- 业务线驱动：用户只需选择业务线，自动 clone 对应的所有 repo

---

## 方案选择

**选定方案：单一 Shell 脚本**（方案 A）

一个 `setup.sh` + 一个 `biz-repos.yaml` 配置文件 + 一个 `maven-settings.xml` 模板。

选择理由：
- 目标用户包含非技术人员，越简单越好
- 仅支持 macOS，不需要跨平台抽象
- 工具数量有限，一个文件完全能管好

---

## 项目结构

```
harness-engineering/
├── setup/
│   ├── setup.sh              # 主入口脚本
│   ├── biz-repos.yaml        # 业务线 → repo 映射配置
│   └── maven-settings.xml    # Maven settings.xml 模板（指向私有 Nexus）
├── CLAUDE.md
└── docs/
```

- `setup.sh`：唯一需要运行的文件
- `biz-repos.yaml`：预配好所有业务线和对应 repo 的 SSH 地址
- `maven-settings.xml`：预配好 Nexus 镜像源的模板，脚本复制到 `~/.m2/settings.xml`

---

## biz-repos.yaml 配置格式

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

Clone 后的本地目录结构：

```
~/workspace/order/
├── order-service/
├── payment-service/
└── order-web/
```

---

## setup.sh 执行流程

### 1. 前置检查

- 检测是否为 macOS
- 检测是否有 sudo 权限

### 2. 安装基础工具

- **Homebrew**：没有则自动安装
- **Git**：`brew install git`
- **yq**：`brew install yq`（用于解析 YAML 配置文件）
- **配置 Git 用户名/邮箱**：交互式输入，已配过则显示当前值，按回车跳过

### 3. 安装开发工具

- **OpenJDK 8**：`brew install openjdk@8`，配置 JAVA_HOME 环境变量
- **Maven 3.9**：`brew install maven`
- **Node.js 20**：`brew install node@20`
- **Tailscale**：`brew install --cask tailscale`，安装后自动执行 `tailscale login --login-server=<URL>`（URL 从 biz-repos.yaml 读取），打开浏览器让用户完成认证
- 每一步先检查是否已安装，已安装则跳过

### 4. 配置 Maven

- 复制 `maven-settings.xml` → `~/.m2/settings.xml`
- 如果 `~/.m2/settings.xml` 已存在，先备份为 `settings.xml.bak`

### 5. 配置 SSH Key

- 检测 `~/.ssh/id_ed25519` 是否存在
- 不存在则生成新的 SSH key（`ssh-keygen -t ed25519`）
- 打印公钥，提示用户添加到 GitLab
- 暂停等待用户确认后再继续

### 6. Clone 业务线 repo

- 读取 `biz-repos.yaml`
- 列出所有业务线，让用户选择（支持多选）
- 按选择的业务线创建 `~/workspace/<biz-key>/` 目录并 clone
- 已存在的 repo 跳过，不重复 clone

### 7. 完成汇总

- 打印安装结果：成功/跳过/失败项

---

## 错误处理

- 每个安装步骤失败后打印错误信息，**不中断整个脚本**，继续后续步骤
- 最终汇总时列出所有失败项
- **唯一中断条件**：Homebrew 安装失败（后续步骤全部依赖它）

## 用户交互

- **Git 用户名/邮箱**：交互式输入，已配过则显示当前值，按回车跳过
- **业务线选择**：带序号的列表菜单，输入序号选择（支持多选，如 `1 3 5`），提供"全部"选项
- **SSH Key**：生成后打印公钥，提示"请将以上公钥添加到 GitLab，完成后按回车继续"

## 日志输出样式

```
[✓] Homebrew 已安装，跳过
[✓] Git 安装完成 (2.44.0)
[✓] OpenJDK 8 安装完成
[✓] Maven 安装完成 (3.9.6)
[✓] Node.js 20 安装完成
[✓] Tailscale 安装完成
[✓] Maven settings.xml 已配置
[✓] SSH Key 已生成

请选择要克隆的业务线：
  1) 订单系统
  2) 用户中心
  3) 全部
请输入序号（多选用空格分隔）: 1 2
```

---

## 环境变量配置

脚本会在 `~/.zshrc` 中追加以下配置（如果不存在）：

```bash
# OpenJDK 8
export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
export PATH="$JAVA_HOME/bin:$PATH"

# Node.js 20
export PATH="/opt/homebrew/opt/node@20/bin:$PATH"
```

---

## 使用方式

```bash
# 首次使用：clone harness-engineering 后运行
git clone git@gitlab.yourcompany.com:infra/harness-engineering.git
cd harness-engineering
bash setup/setup.sh

# 后续：加入新业务线后重新运行，只会 clone 新增的 repo
bash setup/setup.sh
```

---

## 技术约束

| 项目 | 版本/规格 |
|------|-----------|
| 操作系统 | macOS only |
| JDK | OpenJDK 8 |
| Maven | 3.9.x |
| Node.js | 20.x LTS |
| Git 认证 | SSH (ed25519) |
| GitLab | 私有部署 |
| 包管理器 | Homebrew |
| Maven 仓库 | 私有 Nexus |
| VPN | Tailscale（安装 + 自动 login） |
