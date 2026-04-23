# AI Workflow Chat Template

This template is for non-technical users to configure workflow by Q&A.
The AI should output a structured config plan, and a human admin confirms before publishing.

## Goal

- User does not write SQL.
- User only describes business rules in natural language.
- AI outputs a checklist that can be configured in `流程管理（数据库）`.

## How To Use

1. Copy `User Prompt Template`.
2. Fill business details.
3. Send to AI.
4. Ask AI to respond using `AI Output Template`.
5. Configure in UI by checklist.
6. Save draft, test, then publish.

## User Prompt Template

```text
你是流程配置助手。请把我的业务需求转换成“可在流程管理（数据库）页面逐项配置”的清单。

业务名称：<请假/签卡/加班/...>
流程编码：<如 HR_OT>
流程名称：<如 加班流程>

发起人范围：
<哪些人可以发起>

审批链（从发起到结束）：
<例如：发起人 -> 部门主管 -> 经理 -> 结束>

条件分支规则：
<例如：加班时长 <= 4 小时，主管审批后结束；>4 小时走经理审批>

驳回规则：
<例如：所有审批节点都可退回发起人>

表单字段（至少列必填项）：
<字段1, 字段2, ...>

我需要你输出：
1) 节点清单（名称、类型、办理人策略）
2) 连线清单（起点、终点、条件、是否回退）
3) 节点表单绑定清单
4) 发布前检查清单（5条以内）
```

## AI Output Template

```text
【流程基础信息】
- 流程编码：
- 流程名称：
- 发起人范围：

【节点清单】
1. 节点名：
   - 类型：开始/审批/抄送/结束/条件
   - 办理人策略：
   - 说明：

【连线清单】
1. 起点 -> 终点
   - 条件：
   - 回退：是/否
   - 连线名称：

【节点表单绑定】
1. 节点名：
   - 绑定表单：
   - 必填字段：
   - 只读字段：

【配置步骤（按页面点击）】
1.
2.
3.

【发布前检查清单】
- [ ] 已保存到数据库
- [ ] 已发布当前版本
- [ ] 发起人可发起
- [ ] 审批人可收到待办
- [ ] 驳回路径符合预期
```

## Safety Rules

- AI can propose config, but must not auto-publish.
- All workflow changes require admin confirmation.
- Keep operation logs: requester, prompt, generated plan, approver.

## Quick Example

User asks:

```text
业务名称：加班
流程编码：HR_OT
审批链：发起人 -> 部门主管 -> 经理 -> 结束
条件：时长<=4小时走主管后结束，>4小时走经理
驳回：退回发起人
字段：加班日期、开始时间、结束时间、时长、原因
```

AI should return: node list, edge conditions, binding list, and a step-by-step checklist.
