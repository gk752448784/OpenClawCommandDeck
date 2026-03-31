# OpenClaw Command Deck

独立于 OpenClaw 原生面板的中文工作台，用来查看本机 OpenClaw 实例的状态、会话、渠道、计划任务和诊断信息，并直接触发常见控制动作。

当前版本的重点不只是“看状态”，而是把一部分常见运维动作收成了一个可执行闭环：

- 发现问题
- 识别根因
- 给出修复方案
- 执行低风险或确认型修复
- 重新验证问题是否真的恢复

这不是远程托管控制台，也不是多租户服务。它的定位是：

- 跑在当前机器上
- 读取当前机器上的 OpenClaw 数据目录
- 通过当前机器上的 `openclaw` CLI 执行控制命令

## What It Does

当前已经包含这些页面和能力：

- `工作台`：集中展示当前状态、重点事项和快捷入口
- `控制台`：切换模型、执行动作、派发代理任务
- `消息与会话`：查看会话摘要、异常线索和最近日志摘录
- `渠道`：查看飞书、微信、Discord 等渠道配置与状态
- `计划任务`：查看任务节奏、失败状态和修复入口
- `代理`：查看代理角色、工作区以及每个 agent 的问题线索计数
- `告警`：升级为问题分诊页，展示根因、修复级别、验证状态和修复动作
- `诊断`：读取运行状态、日志和安全审计摘要，并展示 issue evidence
- `设置`

## Root-Cause Repair Loop

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

当前支持的修复动作分三档：

- `auto`：低风险动作，允许直接执行
- `confirm`：有副作用的动作，执行前明确确认
- `manual`：只给出根因和处理步骤，不自动动配置

已经接通的可执行修复包括：

- 启用渠道
- 启用插件
- 对齐渠道与插件状态
- 切换主模型到可用候选
- 重启 Gateway

日志类问题当前先做到：

- 自动识别错误线索
- 关联 session / agent
- 展示摘录与修复建议
- 支持修复后重新验证

还没有做成黑盒式自动化多步修复。

## Runtime Model

项目的数据源分两类：

- 展示类数据优先直接读取本地 OpenClaw 文件
- 控制类动作通过 `openclaw` CLI 执行

默认会读取这些内容：

- `OPENCLAW_ROOT/openclaw.json`
- `OPENCLAW_ROOT/cron/jobs.json`
- `OPENCLAW_ROOT/workspace/HEARTBEAT.md`
- `OPENCLAW_ROOT/agents/*/sessions/sessions.json`

诊断页还会调用：

- `openclaw status --json`
- `openclaw logs --plain --limit 30`

修复动作会通过本机 `openclaw` CLI 执行，例如：

- `openclaw config set ...`
- `openclaw gateway restart`

## Requirements

- `Node.js >= 22`
- `npm >= 10`
- 当前机器已安装并可直接执行 `openclaw`
- 当前机器上存在可读取的 OpenClaw 工作目录

默认情况下，应用会把 `OPENCLAW_ROOT` 解析为当前用户的 `~/.openclaw`。

## Configuration

支持的环境变量：

- `OPENCLAW_ROOT`：OpenClaw 根目录，默认是 `~/.openclaw`
- `NEXT_PUBLIC_APP_NAME`：前端展示的应用名称

示例：

```bash
OPENCLAW_ROOT=/path/to/.openclaw NEXT_PUBLIC_APP_NAME="OpenClaw 指挥舱" npm run dev
```

## Getting Started

安装依赖：

```bash
npm install
```

启动开发环境：

```bash
npm run dev
```

然后打开：

```text
http://127.0.0.1:3000/workbench
```

如果你希望绑定固定测试地址，也可以使用：

```bash
npm run dev:test
```

## API Surface

除了页面路由，项目还暴露了一组给前端自己使用的本地 API：

- `GET /api/overview`
- `GET /api/alerts`
- `GET /api/issues`
- `POST /api/issues/[issueId]/repair`
- `POST /api/issues/[issueId]/verify`
- `GET /api/models`
- `POST /api/control/[action]`
- `GET /api/diagnostics`

其中：

- `/api/issues` 返回统一问题列表
- `/api/issues/[issueId]/repair` 执行问题对应修复动作
- `/api/issues/[issueId]/verify` 重新跑验证逻辑，判断问题是否已解决

## Scripts

- `npm run dev`：启动 Next.js 开发环境
- `npm run dev:test`：以 `127.0.0.1:3000` 启动，给 Playwright 使用
- `npm run build`：构建生产包
- `npm run start`：启动生产构建
- `npm run lint`：运行 ESLint
- `npm run typecheck`：运行 TypeScript 类型检查
- `npm run test`：运行 Vitest 单元测试
- `npm run test:e2e`：运行 Playwright 端到端测试

## Verification

建议在提交前至少执行：

```bash
npm run typecheck
npm run lint
npm run test
npm run build
```

如需跑一个基础 e2e 用例：

```bash
npm run test:e2e -- tests/e2e/overview.spec.ts
```

当前仓库的单元测试已经不再依赖你本机真实的 `.openclaw` 配置，而是使用仓库内 fixture。这样换机器后只要满足运行前提，就可以稳定验证。

## Project Structure

```text
app/          Next.js App Router 页面与 API 路由
components/   页面组件与复用 UI
lib/          适配器、选择器、配置和服务端逻辑
tests/        单元测试、e2e 测试与测试夹具
docs/         设计与实施文档
```

和问题修复闭环直接相关的目录主要是：

```text
lib/signals/       原始 signal collectors
lib/root-causes/   根因分类器
lib/repair/        修复计划与修复后验证
lib/issues/        issue orchestration 与 repair registry
app/api/issues/    统一 issue / repair / verify API
```

## Notes For Reuse

如果你要把这个项目放到另一台机器上，通常只需要满足两件事：

1. 那台机器本身能运行 `openclaw`
2. 那台机器的 OpenClaw 数据目录可以通过 `OPENCLAW_ROOT` 找到

项目并不依赖某个固定用户名或某台特定电脑，但它确实依赖“本机有 OpenClaw 运行环境”这个前提。

## Current Scope

这个项目当前适合：

- 作为本机 OpenClaw 的运维和控制面板
- 做问题分诊、常见故障处理和运行观察
- 作为进一步扩展 repair loop 的基础

它当前还不是：

- 远程多实例控制台
- 多租户托管服务
- 完整的日志平台
- 通用 OpenClaw 替代前端
