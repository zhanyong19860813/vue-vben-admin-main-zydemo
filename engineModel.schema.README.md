# engineModel.schema.json 说明文档

本文档面向**读 JSON 的人**：解释 `engineModel` 在流程定义里的位置、根结构含义，以及 Schema 里每个「类型定义」(`$defs`) 的作用。  
对应文件：`engineModel.schema.json`（JSON Schema，用于校验 `definitionJson.engineModel` 的结构）。

**与其它文档的对应关系（建议同步阅读）**

| 文档 | 作用 |
|------|------|
| `流程引擎规则.md` | 完整执行业务语义（批次、会签、连线、干预、**表头与连线的类型化条件**） |
| `ENGINE_RULES_LOCKED.md` | 冻结精简版，便于后端/联调快速对齐 |
| `engineModel.schema.json` | 对 `engineModel` 做结构校验（含 **`edgeConditionRule.fieldType` / `valueTo`**、`edgeFieldType`） |
| 本文 | 逐项解释 Schema 字段；**§4.1～4.2** 已写连线条件与表头条件类型策略对齐 |

代码与 Schema 变更时，优先改 **`流程引擎规则.md` + `ENGINE_RULES_LOCKED.md` + `engineModel.schema.json`**，再按需改本文。

---

## 1. `engineModel` 是什么？

- 流程保存时，除画布用的 `graphData` 外，会额外生成一份 **`engineModel`**：给**流程引擎**用，尽量不依赖节点坐标、样式等 UI 信息。
- 引擎主要用它做三件事：
  1. 知道有哪些**节点**、类型是什么；
  2. 知道节点之间**怎么连**、边上条件怎么算；
  3. 知道**全局策略**（审批人解析优先级、批次策略）和**人工干预**规则。

Schema 只约束 **`engineModel` 这一层**；节点里的 `properties`（LogicFlow 原始属性）在 Schema 里是「任意对象」，由业务代码再解析。

---

## 1.5 界面「添加操作组」与 JSON 对应关系

下面按设计器弹窗 **「添加操作组」**（审批节点双击打开）的布局，说明每一块对应保存到 **`definitionJson`** 里的哪一段。  
路径统一写成：`engineModel.nodes[]` 中 **`type === "approve"`** 的那条节点；若只关心引擎归一化结构，可同时看 `approveConfig`。

> **说明**：连线、出口条件不在本弹窗里配置，它们在 **流程画布** 上，对应 `engineModel.edges[]`（见本文第 4 节）。

| 界面区域 | 界面上的名字 | 主要 JSON 字段（路径相对审批节点） | Schema / 文档中的类型 |
|----------|----------------|--------------------------------------|-------------------------|
| 顶部工具栏 | 保存 / 删除 | 点击保存 → 写回画布节点 `properties`，并随整包进入 `definitionJson` | — |
| 基本信息 | **操作组名称** | `name`（节点显示名，与 `engineNode.name` 一致） | `engineNode.name` |
| 基本信息 | **对象类型**（一般 / 表单人力资源字段 / 创建人 / 节点操作者） | `properties.approvalWeaverUi.objectTypeCategory` | `WfApprovalWeaverUiState`（见 `workflow-definition.schema.ts`） |
| 基本信息 | **自动跳过**（是/否，旁问号说明） | `properties.approvalWeaverUi.autoSkipWhenSameActor`（默认 `true`；旧数据可能为 `nodeOperatorAutoSkip`） | 全对象类型通用，不随「节点操作者」才显示 |
| 对象 | **对象** 区内容随对象类型变化（如创建人：本人/直接上级/…；节点操作者：选前序节点、本人/经理；一般：部门/角色等） | `properties.approvalWeaverUi.*` + 解析结果写在 `properties.approverResolve` / `assigneeStrategies` | `approverResolve`、`assigneeStrategies` |
| 批次/条件 | **条件**（点击设置条件） | 摘要：`properties.approvalHeaderCondition`；结构化：`properties.approvalHeaderConditionRules` | `headerConditionRule`（表头条件，与 `approveConfig.headerConditionRules` 同源） |
| 批次/条件 | **批次**（表头旁小输入框） | `properties.approvalHeaderBatch` | — |
| 批次/条件 | **审批策略**（会签 / 或签 / 依次 / 抄送） | `properties.approvalRoutingMode`（及推导出的 `behaviors`、`countersignPolicy` 等） | 与引擎 `signMode` 对应关系见 `流程引擎规则.md` |
| 批次/条件 | **同步明细** / **空行** | 仅影响界面如何生成/清空 **操作者** 表格行，不单独占一个持久化键 | — |
| 操作者 | 表格 **类型** | 每行 `properties.approvalOperatorRows[].kind` | `approveOperatorRow.kind` |
| 操作者 | 表格 **名称** | 每行 `properties.approvalOperatorRows[].name` | `approveOperatorRow.name` |
| 操作者 | 表格 **级别** | 每行 `properties.approvalOperatorRows[].level`（可选） | `approveOperatorRow.level` |
| 操作者 | 表格 **会签属性** | 每行 `properties.approvalOperatorRows[].countersignAttr`；写入 `approveConfig.rows[].signMode` 时已映射为 `all/any/sequential/cc` | `approveOperatorRow.signMode` |
| 操作者 | 表格 **批次/协办条件** | 每行 `properties.approvalOperatorRows[].batchCondition` | `batchCondition` |
| 操作者 | 表格 **批次** | 每行 `properties.approvalOperatorRows[].batch`（数字，越小越优先） | `approveOperatorRow.batch` |
| 操作者 | 绿 **+** / 红 **−** | 增删 `approvalOperatorRows[]` 数组元素 | `approveConfig.rows` 保存时同步生成 |

**引擎以谁为准**：运行时审批人执行以 **`properties.approvalOperatorRows`**（及归一化后的 **`approveConfig.rows`**）为准；表头区主要用于配置、生成明细和展示摘要，规则见 `流程引擎规则.md` 第 3 节。

**与 `engineModel.schema.json` 的直接关系**：Schema 对 **`approveConfig`**、`edges`、`executionPolicy` 等有结构约束；**`approvalWeaverUi`、完整 `approvalOperatorRows` 原样字段**在 Schema 里挂在 `properties` 的开放对象上，因此本表「对象类型、表头批次」等要同时对照 **`workflow-definition.schema.ts`** 中的 `WfNodeProperties`。

---

## 2. 根对象：`engineModel` 顶层字段

| 字段 | 是否必填 | 作用 |
|------|----------|------|
| `startNodeId` | 否 | 开始节点在图里的 **id**，引擎从这里（或从类型为 `start` 的节点）启动实例。 |
| `nodes` | **是** | 所有节点的列表，至少 1 个。每个元素见下文 **engineNode**。 |
| `edges` | **是** | 所有连线的列表（可以为空数组）。每条见下文 **engineEdge**。 |
| `executionPolicy` | **是** | 全局执行策略：审批人怎么解析、同批默认会签语义、不同批怎么命中。见 **executionPolicy**。 |
| `manualIntervention` | **是** | 人工干预总开关 + 规则列表。见 **manualIntervention**。 |

根对象不允许出现未声明的额外字段（`additionalProperties: false`）。

---

## 3. 节点：`engineNode`

表示流程里的一个「业务节点」（开始、审批、条件、抄送、结束等）。

| 字段 | 必填 | 作用 |
|------|------|------|
| `id` | 是 | 与画布节点 id 一致，全局唯一。 |
| `name` | 是 | 节点显示名称（用于日志、待办展示等）。 |
| `type` | 是 | 节点类型枚举，见下 **engineNodeType**。 |
| `properties` | 否 | 来自设计器的节点属性快照（含 `bizType`、`approvalOperatorRows` 等）。Schema 不约束内部字段，便于扩展。 |
| `approveConfig` | 否 | **审批节点**由前端归一化出的执行视图：操作者行、批次策略、表头条件等。仅 `type === approve` 时通常有值。见 **approveConfig**。 |

---

### 3.2 节点绑定表单（本次新增）

`engineModel.nodes[].properties.formBinding` 为节点级表单绑定标准字段：

| 字段 | 必填 | 含义 |
|------|------|------|
| `formCode` | 否（与 `formName` 至少其一） | 绑定表单编码（推荐作为主键） |
| `formName` | 否（与 `formCode` 至少其一） | 绑定表单名称（回显与兼容） |
| `fieldRules` | 否 | 字段显示策略映射，值为 `visible \| hidden \| readonly` |

`fieldRules` 键格式：
- 主表字段：`fieldName`
- 页签列表列：`tabKey::field`

> 兼容迁移：旧数据可能只有 `formName/bindFormName/formTitle/formLabel` 或 `formCode/bindFormCode`，读取时可兼容；新写入应统一落到 `formBinding`。

---

### 3.1 `engineNodeType`（节点类型枚举）

| 取值 | 含义 |
|------|------|
| `start` | 开始节点 |
| `approve` | 审批节点（要待人办） |
| `condition` | 条件/网关节点（若你们画布有） |
| `cc` | 抄送类节点 |
| `end` | 结束节点 |

---

## 4. 连线：`engineEdge`

表示从 **源节点** 到 **目标节点** 的一条出口，用于「当前节点办完后，下一步去哪」。

| 字段 | 必填 | 作用 |
|------|------|------|
| `id` | 是 | 边唯一 id。 |
| `sourceNodeId` | 是 | 起点节点 id。 |
| `targetNodeId` | 是 | 终点节点 id。 |
| `priority` | 是 | **数字越小越先评估**。多条边从同一节点出发时，按 priority 升序尝试，**先命中条件的先走**。 |
| `name` | 否 | 连接线名称（界面展示用）。 |
| `desc` | 否 | 条件详细描述（如悬停提示全文）。 |
| `ruleGroups` | 否 | 结构化条件：**多组 OR，组内 AND**。见 **edgeRuleGroups**。 |
| `rules` | 否 | 单组 AND 的简写（多条规则都要满足）。 |
| `condition` | 否 | 字符串表达式兜底，引擎在结构化规则之后再用。 |

**引擎读取顺序（与业务规则一致）**：`ruleGroups` → `rules` → `condition`。

---

### 4.1 边上的单条条件：`edgeConditionRule`

| 字段 | 含义 |
|------|------|
| `scope` | `form`：表单字段；`initiator`：发起人相关上下文（由引擎定义具体键）。 |
| `key` | 字段名或上下文键。 |
| `fieldType` | 否 | `string \| number \| boolean \| date`；缺省按 `string`。设计器里与「表头条件」一致，用于**收敛操作符**和**规范化比较**（见下）。 |
| `op` | 是 | 比较运算符，见 **edgeConditionOp**（随 `fieldType` 可选范围不同）。 |
| `value` | 是 | 比较右值；`between` / `not_between` 时表示左端/下限。 |
| `valueTo` | 否 | 仅当 `op` 为 `between`、`not_between` 时使用，表示右端/上限。 |

---

### 4.2 `edgeConditionOp`（边上允许的操作符）

- **通用**：`==`、`!=`。
- **数值 / 日期**（`fieldType` 为 `number` 或 `date`）：另可 `>`、`>=`、`<`、`<=`，以及 **`between`**、**`not_between`**（需同时写 `value` 与 `valueTo`）。
- **文本**（`fieldType` 为 `string`）：`contains`、`startsWith`、`endsWith`、`in`、`notIn`、`containsAny` 等。
- **布尔**（`fieldType` 为 `boolean`）：仅建议 `==` / `!=`。

具体求值由**引擎实现**与 `scope` / `key` / `fieldType` 配合完成。

---

### 4.3 `edgeConditionGroup` 与 `edgeRuleGroups`

- **edgeConditionGroup**：`{ "allOf": [ rule, rule, ... ] }`  
  表示**这一组内全部规则都满足**才算这一组命中。
- **edgeRuleGroups**：`{ "anyOf": [ group, group, ... ] }`  
  表示**任意一组满足**则这条边整体条件满足（组间 OR）。

---

## 5. 审批归一化：`approveConfig`

仅对审批类节点有意义，把「操作者明细 + 批次策略」整理成引擎易读结构。

| 字段 | 必填 | 含义 |
|------|------|------|
| `source` | 是 | 固定为 `approvalOperatorRows`，表示执行数据来自操作者明细表。 |
| `batchMatchPolicy` | 是 | 固定 `first_matched_stop`：**按 batch 从小到大找，第一个命中的批次生效，后面不再看**。 |
| `sameBatchDispatch` | 是 | 固定 `parallel`：同批内任务默认**并发**下发。 |
| `sameBatchDefaultSignMode` | 是 | 固定 `any`：与泛微「同批非会签」对齐时的**默认**语义（具体仍以每行 `signMode` 为准）。 |
| `headerConditionText` | 否 | 表头条件摘要文案（给人看）。 |
| `headerConditionRules` | 否 | 结构化表头/批次条件，见 **headerConditionRule**。 |
| `rows` | 是 | 操作者行列表，至少一行，见 **approveOperatorRow**。 |

---

### 5.1 操作者一行：`approveOperatorRow`

对应界面「操作者」表格的一行。

| 字段 | 必填 | 含义 |
|------|------|------|
| `id` | 否 | 行唯一 id（前端生成，持久化用）。 |
| `kind` | 是 | 类型列文案，如「一般」「表单 人力资源字段」。 |
| `name` | 是 | 名称列（人或规则摘要）。 |
| `refValue` | 否 | 工号、用户 id 等引用值。 |
| `level` | 否 | 级别等扩展字段。 |
| `batch` | 是 | 批次号，**数字越小越先参与匹配**。 |
| `batchCondition` | 否 | 该行的批次/协办条件说明或表达式摘要。 |
| `signMode` | 是 | 该行会签语义，见 **signMode**。 |

---

### 5.2 `signMode`（会签属性，引擎枚举）

| 取值 | 含义 |
|------|------|
| `all` | 会签：全员通过才算过 |
| `any` | 或签/非会签：任一人通过即过 |
| `sequential` | 依次审批 |
| `cc` | 抄送：不阻塞主线 |

---

### 5.3 表头条件规则：`headerConditionRule`

用于「批次/表头」侧的结构化条件（与边上条件字段名不同，专门服务审批批次）。

| 字段 | 含义 |
|------|------|
| `id` | 规则 id。 |
| `joinWithPrev` | 与上一条的连接：`and` / `or`（首条可忽略）。 |
| `type` | `form_compare`（表单比较）、`actor_security`（人员安全级别）、`actor_user`（审批人是否某人）。 |
| `formFieldKey` / `formFieldType` | 表单比较时用：字段名 + 类型 `string|number|boolean|date`。 |
| `actorSource` | `initiator` 或 `node`（前序节点）。 |
| `actorNodeId` / `actorNodeLabel` | 当前序节点时，指向哪个节点。 |
| `op` | 见 **headerConditionOp**。 |
| `value` / `valueTo` | 单值或区间右端；`between` / `not_between` 时必须带 `valueTo`。 |
| `userId` / `userName` | `actor_user` 时选中的人。 |

Schema 里用 `if/then` 约束：`form_compare` 必须带齐表单字段与类型；`actor_security` 必须带 `actorSource/op/value`；`actor_user` 必须带 `actorSource/userId`。

---

### 5.4 `headerConditionOp`（表头条件运算符）

`==`、`!=`、`<`、`<=`、`>`、`>=`，以及区间 `between`、`not_between`。

---

## 6. 全局策略：`executionPolicy`

整份流程定义共用的「怎么解析人、怎么认批次」的约定。

| 字段 | 含义 |
|------|------|
| `resolverPriority` | **数组，长度至少 4**，元素只能是以下四种（顺序即优先级从高到低）：`manualIntervention`、`approverResolve`、`assigneeStrategies`、`approvalWeaverUi_view_only`。表示审批人冲突时先看谁。 |
| `sameBatchDefaultSignMode` | 固定 `any`：与「同批默认非会签」文档一致。 |
| `batchMatchPolicy` | 固定 `first_matched_stop`：不同批次命中即停。 |

---

## 7. 人工干预：`manualIntervention`

| 字段 | 含义 |
|------|------|
| `enabled` | 是否启用人工干预能力（总开关）。 |
| `rules` | 多条 **manualRouteRule**，每条表示「从某节点强制跳到另一节点」。 |

---

### 7.1 单条干预：`manualRouteRule`

| 字段 | 必填 | 含义 |
|------|------|------|
| `id` | 是 | 规则 id。 |
| `enabled` | 是 | 是否生效。 |
| `fromNodeId` | 是 | 从哪个节点出发时尝试命中该规则。 |
| `forceToNodeId` | 是 | 强制转到的目标节点 id。 |
| `reason` | 否 | 干预原因（审计、展示）。 |

**说明**：业务上应禁止 `fromNodeId === forceToNodeId`；当前 JSON Schema 未写死该校验，建议保存时或引擎侧再校验。

---

## 8. Schema 文件头部的元信息

| 字段 | 作用 |
|------|------|
| `$schema` | 声明使用的 JSON Schema 草案版本（2020-12），方便编辑器提示。 |
| `$id` | 该 Schema 的逻辑 URI，可被其它 Schema `$ref` 引用。 |
| `title` | 人类可读标题。 |

---

## 9. 和 `definitionJson` 的关系（便于联调）

典型结构示意：

```json
{
  "processName": "...",
  "processCode": "...",
  "processVersion": 1,
  "wfMeta": { ... },
  "graphData": { ... },
  "engineModel": { ... }
}
```

- **`graphData`**：给设计器还原画布。
- **`engineModel`**：给引擎跑实例；本 Schema 只校验 **`engineModel`** 这一块。

更细的执行业务语义见 **`流程引擎规则.md`** 与 **`ENGINE_RULES_LOCKED.md`**。

---

## 9.1 流程管理本地草稿与预览（实现口径）

- 流程管理本地草稿键：`wf-process-mgmt-local-draft:<processKey>`。
- 草稿中 `definition` 为整包快照，包含 `graphData` 与 `engineModel`，节点绑定随之持久化。
- 预览页读取 payload 时：
  - 开始节点有 `formBinding`：按 `formCode` 拉取并动态渲染 `schemaJson`
  - 无 `formBinding`：回退静态业务表
- 新标签页预览需具备跨页读取能力（`localStorage` 兜底），否则会误回退静态模板。

---

## 10. 本 Schema 刻意不约束的内容

- 节点 **`properties`** 内部字段：随设计器演进，避免 Schema 频繁变更。
- **`manualRouteRule`** 中 `from` 与 `to` 不能相等：建议在应用层校验。
- 边的条件 **`condition`** 字符串语法：由引擎脚本/表达式实现定义，Schema 只要求是字符串。

如需把上述「应用层规则」也写进 Schema，可以后续加 `pattern`、`enum` 或拆出子 Schema 再 `$ref`。
