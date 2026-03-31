# OpenClaw Command Deck 替代型面板实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将当前原型升级为可替代 OpenClaw 原生面板的主入口产品，覆盖高频工作流、核心控制能力和深度管理能力。

**Architecture:** 保留 Next.js + 本地聚合层的架构，把页面树重构为“高频工作台 + 深度控制台”。工作台负责收敛最重要事项、收件与待处理、执行节奏和异常；控制与管理页负责渠道、计划任务、代理、告警、会话、诊断和设置。所有系统动作通过统一控制 API 和明确的确认流执行。

**Tech Stack:** Next.js 15, React 19, TypeScript, zod, Vitest, Playwright, OpenClaw CLI

---

## 1. 目标升级

当前版本已经具备：

- 本地 OpenClaw 文件聚合
- 总览页
- 渠道 / 计划任务 / 代理 / 告警页面
- 一部分可执行控制动作

但当前问题也很明确：

- 还是“读数型后台”，不是“高频工作台”
- 还不能替代原生面板作为默认入口
- 页面树缺消息与会话、诊断、设置
- 高低频功能没有分层
- 一些控制动作仍然分散，缺统一操作体验

这次实施要把产品目标升级为：

1. 首页先服务“今天该处理什么”
2. 二级页完整承接管理与控制
3. 低频复杂功能下沉，不污染首页
4. 保留原生面板的核心能力，并在动作路径和建议能力上做增强

## 2. 替代型信息架构

### 一级导航

- `工作台`
- `控制台`
- `消息与会话`
- `渠道`
- `计划任务`
- `代理`
- `告警`
- `诊断`
- `设置`

### 页面职责

- `工作台`
  - 3-5 个最重要事项
  - 待处理队列
  - 今日节奏
  - 系统异常
  - 快捷动作
  - agent 分工视角

- `控制台`
  - 高价值、可直接执行的动作集合
  - 最近操作记录
  - 常见修复入口

- `消息与会话`
  - 汇总 OpenClaw 会话
  - 最近活跃 agent
  - 会话状态、最近消息、上下文压力线索

- `渠道`
  - 启停
  - 连接状态
  - 最近异常
  - 相关配置跳转

- `计划任务`
  - 启停
  - 立即执行
  - 下一次运行
  - 最近结果
  - 常见修复操作

- `代理`
  - 角色视角
  - 活跃状态
  - 模型绑定
  - 任务派发
  - 工作区入口

- `告警`
  - 只保留可执行告警
  - 告警详情
  - 修复建议
  - 处置状态

- `诊断`
  - 状态快照
  - 原始健康状态
  - 最近日志
  - 问题定位入口

- `设置`
  - 低频配置
  - 面板偏好
  - 模型默认项
  - 原始配置跳转

## 3. 功能取舍原则

### 强化

- 渠道状态与渠道控制
- 计划任务控制与失败修复
- 代理分工和任务派发
- 告警到动作的闭环
- 最近会话与活跃任务
- 诊断与定位入口

### 下沉

- 低频配置项
- 原始日志全文
- 技术化细节状态
- 很少使用的长表单

### 删除或不优先做

- 技能市场入口
- 首页长表格
- 纯展示但无动作建议的状态卡
- 与聊天窗口完全重复的 UI

## 4. 计划文件与主要改动范围

### 重点修改

- `/home/cloud/Documents/OpenClawCommandDeck/components/layout/app-shell.tsx`
- `/home/cloud/Documents/OpenClawCommandDeck/components/layout/side-nav.tsx`
- `/home/cloud/Documents/OpenClawCommandDeck/components/layout/top-bar.tsx`
- `/home/cloud/Documents/OpenClawCommandDeck/app/page.tsx`
- `/home/cloud/Documents/OpenClawCommandDeck/app/overview/page.tsx`
- `/home/cloud/Documents/OpenClawCommandDeck/app/control/page.tsx`
- `/home/cloud/Documents/OpenClawCommandDeck/app/channels/page.tsx`
- `/home/cloud/Documents/OpenClawCommandDeck/app/cron/page.tsx`
- `/home/cloud/Documents/OpenClawCommandDeck/app/agents/page.tsx`
- `/home/cloud/Documents/OpenClawCommandDeck/app/alerts/page.tsx`
- `/home/cloud/Documents/OpenClawCommandDeck/lib/server/load-dashboard-data.ts`
- `/home/cloud/Documents/OpenClawCommandDeck/lib/types/view-models.ts`
- `/home/cloud/Documents/OpenClawCommandDeck/lib/selectors/*.ts`
- `/home/cloud/Documents/OpenClawCommandDeck/app/api/control/[action]/route.ts`

### 新增

- `/home/cloud/Documents/OpenClawCommandDeck/app/workbench/page.tsx`
- `/home/cloud/Documents/OpenClawCommandDeck/app/sessions/page.tsx`
- `/home/cloud/Documents/OpenClawCommandDeck/app/diagnostics/page.tsx`
- `/home/cloud/Documents/OpenClawCommandDeck/app/settings/page.tsx`
- `/home/cloud/Documents/OpenClawCommandDeck/app/api/sessions/route.ts`
- `/home/cloud/Documents/OpenClawCommandDeck/app/api/diagnostics/route.ts`
- `/home/cloud/Documents/OpenClawCommandDeck/app/api/settings/route.ts`
- `/home/cloud/Documents/OpenClawCommandDeck/lib/server/openclaw-cli.ts`
- `/home/cloud/Documents/OpenClawCommandDeck/lib/selectors/sessions.ts`
- `/home/cloud/Documents/OpenClawCommandDeck/lib/selectors/diagnostics.ts`
- `/home/cloud/Documents/OpenClawCommandDeck/components/workbench/*`
- `/home/cloud/Documents/OpenClawCommandDeck/components/sessions/*`
- `/home/cloud/Documents/OpenClawCommandDeck/components/diagnostics/*`
- `/home/cloud/Documents/OpenClawCommandDeck/components/settings/*`

## 5. 实施阶段

### 阶段 1：重写产品骨架

- [x] 更新设计文档，明确替代型产品目标
- [x] 更新实施计划，记录新的页面树与阶段
- [x] 重构导航，切换为新一级菜单
- [x] 把首页入口改成 `工作台`

验证：

- [x] 运行 `npm run lint`
- [x] 运行 `npm run typecheck`

### 阶段 2：重做工作台

- [x] 重构总览模型为工作台模型
- [x] 首页加入重点事项、待处理、执行节奏、系统异常、快捷动作
- [x] 把现有角色卡融入工作台
- [x] 把“系统健康”缩成服务决策的侧栏，而不是主体

验证：

- [x] 补工作台 selector 测试
- [ ] 更新 `tests/e2e/overview.spec.ts` 或重命名为工作台首页测试

### 阶段 3：补全替代原生面板缺口

- [x] 新增 `消息与会话` 页面，接 `openclaw sessions --all-agents --json`
- [x] 新增 `诊断` 页面，接 `openclaw status --json` 和 `openclaw logs --plain --limit 30`
- [x] 新增 `设置` 页面，整合低频配置入口
- [x] 实现 CLI JSON 噪音容错解析

验证：

- [x] 补 sessions/diagnostics 的 unit test
- [x] 手工检查 API 路由返回

### 阶段 4：统一控制体验

- [x] 把高频动作集中到控制台
- [x] 统一成功 / 失败反馈
- [x] 统一确认流和危险动作文案
- [x] 在列表页保留必要的上下文动作，但不堆积按钮

验证：

- [x] 补控制 API 与 commands 测试
- [ ] e2e 覆盖至少一个真实控制流

### 阶段 5：收口与验证

- [ ] 更新 README
- [ ] 同步设计文档到最终实现
- [ ] 修正视觉与响应式问题
- [ ] 跑全套验证

验证命令：

- [ ] `npm run lint`
- [ ] `npm run typecheck`
- [ ] `npm run test`
- [ ] `npm run test:e2e -- tests/e2e/overview.spec.ts`
- [ ] `npm run build`

## 6. 上下文丢失恢复步骤

如果中途中断，恢复顺序如下：

1. 先读设计文档：
   - `/home/cloud/Documents/OpenClawCommandDeck/OpenClawCommandDeck.md`
2. 再读实施计划：
   - `/home/cloud/Documents/OpenClawCommandDeck/OpenClawCommandDeck-Implementation-Plan.md`
3. 再看导航和入口文件：
   - `/home/cloud/Documents/OpenClawCommandDeck/components/layout/side-nav.tsx`
   - `/home/cloud/Documents/OpenClawCommandDeck/app/page.tsx`
   - `/home/cloud/Documents/OpenClawCommandDeck/app/workbench/page.tsx`
4. 再看数据聚合层：
   - `/home/cloud/Documents/OpenClawCommandDeck/lib/server/load-dashboard-data.ts`
   - `/home/cloud/Documents/OpenClawCommandDeck/lib/server/openclaw-cli.ts`
5. 最后跑一次验证：
   - `npm run lint`
   - `npm run typecheck`
   - `npm run test`

## 7. 当前优先实现顺序

按性价比排序：

1. 页面树与导航重构
2. 工作台重构
3. 会话与诊断接入
4. 设置页与低频配置整理
5. 更完整的控制台与交互反馈

先把“像产品”这件事做对，再继续增加更多控制动作。
