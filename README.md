# OpenClaw Command Deck

独立于 OpenClaw 原生面板的中文工作台，用来查看本机 OpenClaw 实例的状态、会话、渠道、计划任务和诊断信息，并直接触发常见控制动作。

这不是远程托管控制台，也不是多租户服务。它的定位是：

- 跑在当前机器上
- 读取当前机器上的 OpenClaw 数据目录
- 通过当前机器上的 `openclaw` CLI 执行控制命令

## What It Does

当前已经包含这些页面和能力：

- `工作台`：集中展示当前状态、重点事项和快捷入口
- `控制台`：切换模型、执行动作、派发代理任务
- `消息与会话`：查看会话摘要和最近活动
- `渠道`：查看飞书、微信、Discord 等渠道配置与状态
- `计划任务`：查看任务节奏、失败状态和修复入口
- `代理`：查看代理角色和工作区信息
- `告警`：聚焦失败任务和待处理问题
- `诊断`：读取运行状态、日志和安全审计摘要
- `设置`

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

## Project Structure

```text
app/          Next.js App Router 页面与 API 路由
components/   页面组件与复用 UI
lib/          适配器、选择器、配置和服务端逻辑
tests/        单元测试、e2e 测试与测试夹具
docs/         设计与实施文档
```

## Notes For Reuse

如果你要把这个项目放到另一台机器上，通常只需要满足两件事：

1. 那台机器本身能运行 `openclaw`
2. 那台机器的 OpenClaw 数据目录可以通过 `OPENCLAW_ROOT` 找到

项目并不依赖某个固定用户名或某台特定电脑，但它确实依赖“本机有 OpenClaw 运行环境”这个前提。
