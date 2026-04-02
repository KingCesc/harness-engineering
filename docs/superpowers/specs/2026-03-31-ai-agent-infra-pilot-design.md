# AI Agent Company Infra — 打样项目设计

## 背景

50人产研团队转型为 AI Agent 原生组织。不区分产品/研发、前后端，人人都是 Agent 工程师，用 Claude Code 写代码。本设计是**打样项目**，从一个具体业务出发，跑通后再推广。

### 目标

- 保持系统的稳定
- 代码的质量
- 迭代的速度
- 一个人就能完成需求

### 现状

- 技术栈：前后端分离（JS/TS + Java），多个独立 GitLab repo，分布在不同 group
- 基础设施：公有云部署，已有成熟 CI/CD
- Claude Code 使用：部分人在用，无统一规范
- 测试基础：弱
- 一个业务涉及 6-7 个项目

### 核心痛点

- 代码风格/质量不一致
- 安全风险担忧
- 并行开发冲突
- Onboarding 慢
- 系统腐化
- 怕改坏现有功能

---

## 1. Repo 组织策略

**原则：不动 GitLab group 结构，本地 clone 到同一父目录。**

现有项目保持各自的 GitLab group 和 repo 不变，开发者本地按业务维度组织：

```
~/workspace/biz-xxx/
├── project-a-frontend/
├── project-b-backend/
├── project-c-service/
├── project-d-service/
├── ...
```

不迁移 repo 的原因：
- 迁移成本高（CI、权限、引用都要改）
- 本地组织已经能满足"一个人同时看多个项目"的需求

---

## 2. 上下文管理 — 单项目聚焦 + CLAUDE.md 导航

**核心原则：每次 Claude Code 只工作在一个项目目录里，通过 CLAUDE.md 了解全局依赖关系。**

6-7 个项目全部加载会导致 token 爆炸。解决方式：

- Claude Code 始终 `cd` 到当前工作的项目目录
- 每个项目的 CLAUDE.md 中包含跨项目导航信息
- 一个需求跨多个项目时，分别在各项目目录中工作，Claude Code 根据 CLAUDE.md 提醒同步

### CLAUDE.md 跨项目导航模板

```markdown
## 项目间依赖

### 我依赖的项目
- `project-b-backend`：调用其 /api/order/* 接口，接口定义见下方摘要
- `project-c-service`：通过 MQ 消费其 OrderCreated 事件

### 依赖我的项目
- `project-a-frontend`：调用本项目的 /api/user/* 接口
- 修改这些接口前必须通知前端同步

### 关键接口摘要
- POST /api/user/login → { token: string, user: UserInfo }
- GET /api/user/profile → UserInfo
- ...
```

---

## 3. 核心代码 vs 应用代码分层

**按业务重要性分层，用 CODEOWNERS 强制审核保护核心代码。**

### 目录结构（以 Java 后端为例）

```
backend/
├── src/main/java/com/xxx/
│   ├── core/              # 核心业务逻辑（支付、订单、权限等）
│   ├── biz/               # 普通业务功能
│   └── infra/             # 基础设施代码（DB、缓存、MQ 封装）
```

### 保护机制

| 目录 | 保护级别 | 审核要求 |
|------|----------|----------|
| `core/` | 高 | MR 至少 2 人审核，CODEOWNERS 指定资深开发者 |
| `infra/` | 高 | MR 至少 2 人审核，CODEOWNERS 指定资深开发者 |
| `biz/` | 标准 | MR 至少 1 人审核 |

### CLAUDE.md 中的标注

```markdown
## 代码分层

- `core/` 和 `infra/` 是高保护区域。修改这些目录下的代码前，必须：
  1. 说明修改原因和影响范围
  2. 确认有对应的测试覆盖
  3. 不要改变已有接口的签名或行为，除非明确要求
- `biz/` 是普通业务区域，可以自由修改，但仍需写测试
```

### CODEOWNERS 文件

```
# 放在 repo 根目录
/src/main/java/com/xxx/core/    @senior-dev-1 @senior-dev-2
/src/main/java/com/xxx/infra/   @senior-dev-1 @infra-lead
```

---

## 4. 自动 Code Review

**GitLab CI 触发 Codex 对 MR diff 做 review，结果写回 MR 评论。**

### 流程

```
开发者提交 MR
    │
    ▼
GitLab CI 触发 auto-review job
    │
    ▼
脚本提取 MR diff + 项目 CLAUDE.md 中的规范
    │
    ▼
调用 AI API（OpenAI Codex 或其他 LLM），传入 diff + review 规则
    │
    ▼
将 review 结果作为 MR 评论发回 GitLab
    │
    ▼
开发者根据评论修改，人工审核者参考 AI review 结果
```

### GitLab CI 配置

```yaml
auto-review:
  stage: review
  image: node:20-slim
  script:
    - scripts/ai-review.sh
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  allow_failure: true  # AI review 不阻断合入，作为辅助
```

### AI Review 关注点

1. **接口契约**：是否改变了现有 API 的签名或返回结构
2. **安全风险**：注入漏洞、硬编码密钥、敏感信息暴露
3. **架构合规**：是否违反 CLAUDE.md 中定义的分层规范（如 Controller 直接调 DAO）
4. **测试完备**：改了代码是否有对应测试
5. **core/ 目录特别审查**：对 core/ 的改动会触发更严格的 review prompt

### AI Review 与人工审核的关系

- AI review 是**辅助**，不替代人工
- `core/` 和 `infra/` 的改动仍需 CODEOWNERS 指定的人审核
- AI review 结果作为参考，人工审核者可以选择采纳或忽略

---

## 5. 自动化测试

**策略："新增必测，存量逐步"。不追求补全历史测试，重点保证新增代码有测试。**

### 5.1 测试分层

| 层级 | 范围 | 工具 | CI 要求 |
|------|------|------|---------|
| 单元测试 | 新增/修改的方法 | JUnit 5 (后端) / Vitest (前端) | 新代码覆盖率 ≥ 80%，**阻断合入** |
| 接口测试 | 后端 API | JUnit 5 + Testcontainers | 每个新增/修改的 API 必须有测试，**阻断合入** |
| E2E 测试 | 核心业务流程 | Playwright | 只覆盖关键路径，合入 main 后运行 |

### 5.2 AI 强制同步写测试

在 CLAUDE.md 中规定：

```markdown
## 测试要求

- 每次修改代码必须同时编写或更新对应的测试
- 新增方法必须有单元测试
- 新增/修改 API 必须有接口测试
- 禁止提交没有测试的代码改动
```

CI 中检查：如果 MR 修改了 `src/` 下的文件但没有修改 `test/` 下的文件，标记为警告。

### 5.3 测试基础设施

**后端（Java）：**
- JUnit 5 作为测试框架
- Testcontainers 启动真实 MySQL/Redis/MQ 容器，不 mock 数据库
- 用 JaCoCo 统计覆盖率，CI 中检查增量覆盖率

**前端（TS）：**
- Vitest 做单元测试和组件测试
- Testing Library 做组件交互测试
- Playwright 做 E2E 测试（仅核心流程）
- Istanbul 统计覆盖率

### 5.4 存量代码的测试策略

不要求一次性补全历史测试。而是：
- 每次改到存量代码时，顺手补上该模块的测试
- `core/` 目录优先补测试，作为专项任务逐步推进
- 设定季度目标：核心模块覆盖率逐步提升

---

## 6. CLAUDE.md 标准化

### 6.1 CLAUDE.md 层级体系

CLAUDE.md 分为**项目级**和**模块级**两个层级，Claude Code 会自动读取当前目录和所有父目录的 CLAUDE.md。

#### 项目级 CLAUDE.md（repo 根目录）

分三段内容，用 HTML 注释标记区分：

- **通用层**（`HARNESS:SHARED:BEGIN/END` 标记包裹）：安全红线、Git 规范、测试要求、代码风格。从 harness-engineering 自动同步，禁止手动修改，CI 校验一致性。
- **技术栈层**（`HARNESS:STACK:BEGIN/END` 标记包裹）：Java 后端规范或 TS 前端规范。从 harness-engineering 按技术栈同步，禁止手动修改，CI 校验一致性。
- **项目层**（`PROJECT:BEGIN/END` 标记包裹）：项目架构说明、项目间依赖关系和接口摘要、代码分层标注（core/biz/infra）、已知的"地雷区"。由项目团队自行维护。

同步脚本只替换通用层和技术栈层标记内的内容，不动项目层。CI 中校验通用层/技术栈层与 harness-engineering 模板一致，不一致则阻断 MR。

#### 模块级 CLAUDE.md（各模块目录下）

每个重要模块目录下放置 CLAUDE.md，描述该模块的详细信息：

```
project-backend/
├── CLAUDE.md                              # 项目级
├── src/main/java/com/xxx/
│   ├── core/
│   │   ├── CLAUDE.md                      # core 层总览
│   │   ├── payment/
│   │   │   └── CLAUDE.md                  # 支付模块详情
│   │   └── order/
│   │       └── CLAUDE.md                  # 订单模块详情
│   ├── biz/
│   │   └── CLAUDE.md                      # biz 层总览
│   └── infra/
│       └── CLAUDE.md                      # infra 层总览
```

模块级 CLAUDE.md 内容包括：
- **职责**：该模块做什么
- **核心类**：关键类及其作用
- **关键流程**：核心业务流程的步骤描述
- **修改注意事项**：地雷区、业务约束、历史踩坑经验
- **依赖**：依赖的内部模块和外部服务
- **测试**：测试文件位置和测试方式

### 6.2 模块级 CLAUDE.md 生成方式

由 AI 生成初版，人工校验补充。具体流程：

1. 开发者在项目目录下运行生成 skill/脚本
2. Claude Code 扫描项目结构，读取各模块代码，生成 CLAUDE.md 初版
3. 开发者 review，补充 AI 无法从代码推断的内容：
   - 地雷区（业务风险点）
   - 修改注意事项（历史踩坑经验）
   - 关键业务流程的业务含义
4. 合入 repo

模块级 CLAUDE.md 由项目团队自行维护，不受 harness-engineering 同步机制管控。当模块发生重大改动时，开发者应同步更新对应 CLAUDE.md。

---

## 7. Hooks — 本地即时检查

| Hook 时机 | 检查内容 |
|-----------|----------|
| `PreToolUse` (Edit/Write) | 文件中是否包含硬编码密钥、敏感信息 |
| `PreToolUse` (Bash) | 阻止危险命令（`rm -rf /`、`git push -f main`、`DROP TABLE`） |
| `PostToolUse` (Edit/Write) | 自动运行对应文件的 lint 检查 |
| `PreToolUse` (Bash: git commit) | 验证 commit message 格式 |

---

## 8. 分阶段落地计划

| 阶段 | 时间 | 内容 | 产出 |
|------|------|------|------|
| **Phase 1** | 第 1-3 周 | CLAUDE.md 标准化 + Hooks + 项目级配置 | 团队统一使用 Claude Code 的方式 |
| **Phase 2** | 第 4-6 周 | CI 质量门禁强化 + 自动化测试基础设施 | 新代码有测试保障 |
| **Phase 3** | 第 7-9 周 | 自动 CR（GitLab CI + Codex） | AI 辅助 code review |
| **Phase 4** | 第 10-12 周 | 复盘打样效果，推广到其他业务 | 全公司推广方案 |

每个 Phase 的产出独立可用，不需要等后续 Phase 完成才有价值。
