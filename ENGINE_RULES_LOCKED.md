# ENGINE_RULES_LOCKED

> 流程引擎最终执行规范（冻结版）。
> 本文件用于后端实现、联调、验收，不再使用“建议/待定”语气。

## 1. 执行原则

- 运行时执行源仅为 `approvalOperatorRows[]`（或其归一化的 `approveConfig.rows`）。
- 表头配置（对象类型、对象、批次/条件、审批策略）仅用于生成明细和界面回显，不直接参与运行时判定。
- 引擎解析优先使用 `engineModel`，不依赖 `graphData`。

## 2. 冻结决策

### 2.1 审批人解析优先级

固定顺序：

`manualIntervention > approverResolve > assigneeStrategies > approvalWeaverUi(仅回显)`

### 2.2 同批次会签/或签/依次

- `all`（会签）：全员 `approve` 才通过；任一 `reject` 立即拒绝。
- `any`（或签/非会签）：任一 `approve` 立即通过；单个 `reject` 不立即拒绝，需全员 `reject` 才拒绝。
- `sequential`（依次）：按顺序审批；任一 `reject` 立即拒绝。

### 2.3 条件类型与操作符

**表头（审批 `approvalHeaderConditionRules` / `form_compare`）**

- `formFieldType` 必填：`string | number | boolean | date`
- 操作符按类型收敛（与设计器一致）
- `between/not_between` 必须同时提供 `value` 和 `valueTo`

**连线（`engineModel.edges[].ruleGroups` / `rules` 中的 `WfEdgeConditionRule`）**

- `fieldType` 必填（与设计器一致；**旧数据缺省按 `string`**）
- 操作符收敛规则与表头 **同一套**：`boolean` 仅 `==`/`!=`；`string` 含包含/列表类；`number`/`date` 含比较符及 `between`/`not_between`
- `between/not_between` 必须同时提供 `value` 与 `valueTo`

（上述字段与 JSON Schema 见 `engineModel.schema.json`）

### 2.4 前序节点操作者

- 前序节点多人通过时，仅取“第一位通过人”。
- 取“经理”时，取该第一位通过人的经理。
- `approvalWeaverUi.autoSkipWhenSameActor` 默认 `true`（旧字段 `nodeOperatorAutoSkip` 仅兼容读取）：
  - `true`：前序解析人与当前节点同人时，自动跳过当前节点。
  - `false`：不自动跳过（例如有表单必填项）。

### 2.5 手动干预

- 生效模式：实时覆盖。
- 命中 `fromNodeId -> forceToNodeId` 时，在出当前节点路由前立即改道。
- 旧路径已生成待办实时关闭/作废，只保留新路径有效待办。

## 3. 批次与命中规则

- `batch` 越小优先级越高。
- 空条件视为恒真。
- 不同批次按升序找“首个命中批次”，命中即停，不再看后续批次。
- 同批默认并发下发，具体聚合行为按该批行的 `signMode` 执行。

## 3.1 节点绑定表单（冻结）

- 标准字段：`engineModel.nodes[].properties.formBinding`。
- 结构固定：`formCode`、`formName`、`fieldRules?`。
- `fieldRules` 仅允许：`visible | hidden | readonly`。
- 页签列规则键必须使用 `tabKey::field`；主表字段使用 `fieldName`。
- 旧字段仅兼容读取，不作为写入目标：
  - 名称：`formName | bindFormName | formTitle | formLabel`
  - 编码：`formCode | bindFormCode`

## 4. 连线路由规则

节点通过后，路由按以下顺序执行：

1. `priority` 升序
2. `ruleGroups`（组间 OR，组内 AND）
3. `rules`（AND）
4. `condition`（字符串兜底）
5. 命中第一条边即路由；未命中走默认出口或抛配置异常

## 5. 执行伪代码

```text
advanceNode(instance, nodeId):
  node = getNode(nodeId)

  manual = matchManualIntervention(instance, nodeId)
  if manual.hit:
    closeInvalidTodos(instance, nodeId)
    auditManualJump(instance, manual)
    return gotoNode(instance, manual.forceToNodeId)

  rows = loadOperatorRows(node)
  activeBatch = pickFirstMatchedBatch(rows, instance)
  if activeBatch == null:
    return fail("NO_MATCHED_BATCH")

  result = runBatch(activeBatch)
  if result == REJECTED:
    return applyRejectPolicy(instance, node)
  if result != APPROVED:
    return wait()

  next = pickEdgeByPriority(nodeId, instance)
  if next == null:
    return handleNoRoute(instance, nodeId)
  return gotoNode(instance, next.targetNodeId)
```

## 6. 最小回归用例

1. 不同批次命中即停
2. 同批 `any` 一票通过
3. 同批 `all` 一票否决
4. `sequential` 顺序推进
5. 前序节点多人通过仅取第一位
6. `autoSkipWhenSameActor=true` 同人自动跳过
7. `autoSkipWhenSameActor=false` 同人不跳过
8. 手动干预实时覆盖 + 待办实时处理
9. 表头与连线：`number`/`date` 的 `between` 区间与非法值拦截
10. `ruleGroups > rules > condition` 的路由优先级
11. 连线条件 `fieldType` + 操作符收敛、旧数据缺省 `string`
12. 节点绑定表单：保存后再次打开可回显（含旧字段兼容读取）
13. 流程管理：切换流程前自动持久化草稿，切回后可恢复绑定
14. 预览：开始节点已绑定时动态渲染 schema；未绑定时回退静态业务表
