## harness-engineering

AI Agent 驱动的产研工程架构。全产研团队（产品/设计/研发/测试，约 50 人）参与，一个人就能完成产品构建和代码编写，基于 SPECS 做开发。

### 技术背景

- 团队全员 macOS，默认 shell 为 zsh
- 代码托管：私有 GitLab（git-web.shulex-tech.com），SSH 访问（git-ssh.shulex-tech.com）
- 技术栈：Java（OpenJDK 8）+ JS/TS（Node.js 20），前后端分离，多个独立 GitLab repo
- 构建工具：Maven 3.9，私有 Nexus 镜像源
- VPN：Tailscale（login server: hs.shulex.com）
- 一个业务涉及 6-7 个项目，分布在不同 GitLab group

### 项目结构

```
harness-engineering/
├── setup/
│   ├── setup.sh              # 一键开发环境配置脚本（zsh）
│   ├── biz-repos.yaml        # 业务线 → repo 映射配置
│   └── maven-settings.xml    # Maven settings.xml 模板（Nexus 镜像）
├── docs/
│   └── superpowers/
│       ├── specs/             # 设计文档
│       │   ├── 2026-03-31-ai-agent-infra-pilot-design.md  # 整体架构设计
│       │   └── 2026-04-02-dev-env-setup-design.md         # setup 脚本设计
│       └── plans/             # 实施计划
│           └── 2026-04-02-dev-env-setup.md
├── CLAUDE.MD
└── AGENTS.MD
```

### setup/setup.sh — 一键开发环境配置

面向全产研团队的零前置条件开发环境配置脚本。

**执行方式：** `zsh setup/setup.sh` 或 `./setup/setup.sh`

**功能流程：**

1. 前置检查（macOS 检测 + 配置文件存在）
2. 安装 Homebrew（失败则终止，其余步骤都依赖它）
3. 安装 Git + yq
4. 配置 Git 用户名/邮箱（已有则跳过，未配置才提示输入）
5. 安装 OpenJDK 8 + Maven + Node.js 20 + Tailscale
   - 已安装且版本满足要求则跳过（Maven >= 3.9, Node >= 20）
   - Tailscale 检测支持 brew/App Store/.pkg 多种安装方式
6. Tailscale 自动 login（从 biz-repos.yaml 读取 login_server）
7. Maven settings.xml 配置（复制模板到 ~/.m2/，已有则备份）
8. 环境变量写入 ~/.zshrc（仅在 java/node 不可用时才写入，避免覆盖现有配置）
9. SSH Key 生成（无则自动生成 ed25519）+ 展示公钥 + GitLab 设置页面链接
10. Clone 业务线 repo：
    - SSH 连通性验证（ssh -T git@ssh_host，失败可重试或跳过）
    - 交互式业务线选择菜单（支持多选 + 全部）
    - Clone 到 ~/workspace/<biz-key>/ 目录下

**设计原则：**

- 幂等安全：重复运行不破坏已有配置
- 失败继续：除 Homebrew 外，其他步骤失败不中断脚本
- 彩色日志：绿色=成功，黄色=跳过，红色=失败，蓝色=信息
- 最终汇总：打印所有成功/跳过/失败项

**注意事项（踩过的坑）：**

- zsh 中用 `printf` 而非 `echo -e`（echo -e 在 zsh 里会把 -e 当文本输出）
- zsh 的 `read` 语法：`read -r "var?prompt"` 而非 bash 的 `read -rp "prompt" var`
- zsh 循环内不要重复 `local` 声明变量（会打印赋值信息），应在循环外声明
- `ssh -T` 加 `-n` 参数防止消耗 stdin（否则后续 read 拿不到输入）
- `git clone` 加 `< /dev/null` 同理
- 不要用 `set -e` 或 `pipefail`，会导致脚本在允许失败的步骤静默退出
- 嵌套参数展开 `${${var#*.}%%.*}` 不兼容，要拆成两步

### biz-repos.yaml 配置说明

```yaml
gitlab:
  host: git-web.shulex-tech.com       # Web 界面地址
  ssh_host: git-ssh.shulex-tech.com   # SSH clone 地址（验证用）
tailscale:
  login_server: https://hs.shulex.com
workspace: ~/workspace                 # 本地工作目录根路径
businesses:                            # 业务线定义
  - name: 显示名称
    key: 目录名                         # clone 到 ~/workspace/<key>/
    repos:
      - group: backend/frontend
        name: repo 名称
        ssh: git@git-ssh...:group/repo.git
```

### 整体落地计划（来自架构设计文档）

| 阶段 | 内容 |
|------|------|
| Phase 1（第 1-3 周） | CLAUDE.md 标准化 + Hooks + 项目级配置 ← **当前阶段** |
| Phase 2（第 4-6 周） | CI 质量门禁强化 + 自动化测试基础设施 |
| Phase 3（第 7-9 周） | 自动 CR（GitLab CI + AI Review） |
| Phase 4（第 10-12 周） | 复盘打样效果，推广到其他业务 |
