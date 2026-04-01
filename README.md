# OpenClaw Command Deck

中文化、本机优先的 OpenClaw 控制台。

它不是一个“查看状态”的静态面板，而是一个围绕本地 OpenClaw 实例打造的运维工作台：把运行状态、问题分诊、常见控制动作和修复验证收进同一套界面里，减少在原生面板、配置文件和 CLI 之间来回切换的成本。

## What It Is

`OpenClaw Command Deck` 适合用来管理当前机器上的 OpenClaw 运行环境：

- 查看工作台、告警、会话、渠道、计划任务、代理和诊断信息
- 通过本机 `openclaw` CLI 执行常见控制动作
- 把部分高频问题处理收敛成一个可执行闭环：
  - 发现问题
  - 识别根因
  - 给出修复方案
  - 执行低风险或确认型修复
  - 重新验证是否恢复

它的边界也很明确：

- 不是远程多实例控制台
- 不是多租户托管服务
- 不是完整日志平台
- 不是 OpenClaw 官方前端的全量替代品

## Highlights

当前版本重点在这几块：

- `工作台`
  - 展示今日重点、系统姿态、快捷动作和运行摘要
- `控制台`
  - 切换模型、派发 agent、执行计划任务和常用控制动作
- `告警 / Issues`
  - 做问题分诊，展示根因、修复级别、验证状态和修复动作
- `服务`
  - 查看 Gateway 运行态，执行启停/重启，管理配置备份与恢复
- `渠道 / 计划任务 / 代理 / 会话`
  - 提供更聚焦的控制面，不把所有信息堆在一个页面里
- `诊断`
  - 读取运行状态、日志和安全审计摘要，并与 issue evidence 对齐
- `Skills`
  - 查看当前技能清单、可用性和缺失依赖，详情按需加载

## Repair Loop

第一阶段已经落地的 repair loop 主要覆盖三类问题：

- `渠道 / 插件`
  - `channel_disabled`
  - `plugin_disabled`
  - `plugin_missing`
  - `channel_plugin_mismatch`
- `模型 / Gateway`
  - `primary_model_missing`
  - `primary_model_unavailable`
  - `gateway_unreachable`
  - `gateway_restart_required`
- `会话 / 日志`
  - `session_log_error_detected`
  - `agent_dispatch_failure`

当前支持的修复级别：

- `auto`
  - 低风险动作，允许直接执行
- `confirm`
  - 有副作用的动作，执行前明确确认
- `manual`
  - 只给出根因和处理步骤，不自动改配置

已经接通的可执行修复包括：

- 启用渠道
- 启用插件
- 对齐渠道与插件状态
- 切换默认模型到可用候选
- 重启 Gateway

服务管理页还支持这些独立动作：

- 启动 Gateway
- 停止 Gateway
- 重启 Gateway
- 创建配置备份
- 从备份恢复并重启 Gateway

## Runtime Model

这个项目是“本机控制台”，不是远程 API 管理器。

它的数据来源分两类：

- 展示类数据优先直接读取本地 OpenClaw 文件
- 控制类动作通过本机 `openclaw` CLI 执行

默认会读取：

- `OPENCLAW_ROOT/openclaw.json`
- `OPENCLAW_ROOT/cron/jobs.json`
- `OPENCLAW_ROOT/workspace/HEARTBEAT.md`
- `OPENCLAW_ROOT/agents/*/sessions/sessions.json`

诊断和运行态还会调用：

- `openclaw status --json`
- `openclaw logs --plain --limit 30`
- `openclaw skills list --json`
- `openclaw skills info <name> --json`

控制和修复动作会通过本机 CLI 执行，例如：

- `openclaw config set ...`
- `openclaw gateway restart`
- `openclaw gateway start`
- `openclaw gateway stop`
- `openclaw cron edit ...`
- `openclaw cron run ...`

## Getting Started

### Requirements

- `Node.js >= 22`
- `npm >= 10`
- 当前机器已安装并可直接执行 `openclaw`
- 当前机器存在可读取的 OpenClaw 工作目录

默认情况下，`OPENCLAW_ROOT` 会解析到当前用户的 `~/.openclaw`。

### Install

```bash
npm install
```

### Run

```bash
npm run dev
```

打开：

```text
http://127.0.0.1:3000/workbench
```

如果你需要给 Playwright 固定地址，也可以使用：

```bash
npm run dev:test
```

## Configuration

支持的环境变量：

- `OPENCLAW_ROOT`
  - OpenClaw 根目录，默认 `~/.openclaw`
- `NEXT_PUBLIC_APP_NAME`
  - 前端展示用应用名称
- `OPENCLAW_CLI_TIMEOUT_MS`
  - 诊断类 CLI 超时时间，默认 `12000`
- `OPENCLAW_CONTROL_TIMEOUT_MS`
  - 控制类 CLI 超时时间，默认 `15000`
- `OPENCLAW_SKIP_GATEWAY_RESTART_ON_MODEL_CHANGE`
  - 设为 `1/true` 时，模型变更后跳过 Gateway 重启
- `OPENCLAW_ALLOW_PRIVATE_MODEL_DISCOVERY`
  - 设为 `1/true` 时，允许模型自动发现访问内网或本地地址

示例：

```bash
OPENCLAW_ROOT=/path/to/.openclaw \
NEXT_PUBLIC_APP_NAME="OpenClaw 指挥舱" \
npm run dev
```

## API Surface

这个仓库提供一组给前端自己使用的本地 API：

- `GET /api/overview`
- `GET /api/alerts`
- `GET /api/issues`
- `POST /api/issues/[issueId]/repair`
- `POST /api/issues/[issueId]/verify`
- `GET /api/models`
- `POST /api/models`
- `POST /api/models/discover`
- `POST /api/control/[action]`
- `GET /api/diagnostics`
- `GET /api/service`
- `GET /api/service/backups`
- `POST /api/service/backups`
- `POST /api/service/backups/restore`
- `GET /api/agents`
- `GET /api/channels`
- `GET /api/cron`
- `GET /api/sessions`
- `GET /api/settings`
- `GET /api/skills`
- `GET /api/skills/[skillName]`

其中较核心的几组是：

- `issues`
  - 统一问题列表、修复动作和修复后验证
- `service`
  - 服务运行态、配置备份和恢复
- `models`
  - 模型与 provider 管理、模型自动发现
- `skills`
  - 技能清单、可用性和单项详情

## Scripts

- `npm run dev`
  - 启动 Next.js 开发环境
- `npm run dev:test`
  - 以 `127.0.0.1:3000` 启动，供 Playwright 使用
- `npm run build`
  - 构建生产包
- `npm run start`
  - 启动生产构建
- `npm run lint`
  - 运行 ESLint
- `npm run typecheck`
  - 运行 TypeScript 类型检查
- `npm run test`
  - 运行 Vitest 单元测试
- `npm run test:e2e`
  - 运行 Playwright 端到端测试

## Verification

提交前建议至少执行：

```bash
npm run typecheck
npm run lint
npm run test
npm run build
```

如需跑一个最基础的 e2e：

```bash
npm run test:e2e -- tests/e2e/overview.spec.ts
```

当前仓库的单元测试不依赖你本机真实的 `.openclaw` 配置，而是使用仓库内 fixture，因此跨机器运行更稳定。

## Project Structure

```text
app/          Next.js App Router 页面与 API 路由
components/   页面组件与复用 UI
lib/          适配器、选择器、控制逻辑和服务端能力
tests/        单元测试、e2e 测试与测试夹具
docs/         设计与实施文档
```

和 repair loop 直接相关的目录主要是：

```text
lib/signals/       原始 signal collectors
lib/root-causes/   根因分类器
lib/repair/        修复计划与修复后验证
lib/issues/        issue orchestration 与 repair registry
app/api/issues/    统一 issue / repair / verify API
```

## Scope

这个项目当前适合：

- 作为本机 OpenClaw 的运维和控制面板
- 做问题分诊、常见故障处理和运行观察
- 作为继续扩展 repair loop 的基础

它当前还不适合：

- 远程管理多台 OpenClaw 实例
- 做多租户托管服务
- 承担完整日志平台职责
- 作为官方控制面的全量替代
