/*
  工作流引擎数据模型（UUID版）
  数据库：SQL Server
  说明：
  1) 所有表主键统一使用 uniqueidentifier（UUID）
  2) 主键默认值使用 NEWSEQUENTIALID()（减少索引碎片）
  3) 保留流程定义、实例、待办、审批记录、干预、批量操作、自动测试能力

  =============================================================================
  【各表功能与作用说明】（评审/落地时对照用）
  =============================================================================

  --- 一、流程定义层（“模板”，不随某次请假实例变化）---

  0) dbo.wf_process_category（流程目录树）
     作用：支撑界面左侧「人事流程 / 行政流程」等**仅目录**的节点；支持多级（parent_id 自关联，根为 NULL）。
     真正的流程定义仍在 wf_process_def；每条流程通过 category_id 挂到某一目录下，与树形 UI 一一对应。
     排序：同级用 sort_no；可选 folder_code 便于权限或路由（同一 parent 下 folder_code 建议唯一）。
     category_code（wf_process_def 上）可保留作冗余编码或兼容旧数据，与 category_id 二选一或并存均可。

  1) dbo.wf_process_def
     作用：一条业务上的“流程品种”，如「请假流程」「加班流程」。
     典型：process_code 全局唯一；latest_version 指向当前对外发布或草稿的最新版本号；category_id 指向所属目录。
     与前端：对应流程管理里维护的 processCode / processName（顶层标识）；左侧树「叶子」对应本表一行。

  2) dbo.wf_process_def_ver
     作用：同一流程品种下的**不可变版本快照**。发布后新版本号递增，旧版本仍可被已启动实例引用。
     核心字段：
       - definition_json：建议存**完整设计器导出 JSON**（见下文「与流程 JSON 对应」），便于还原画布与兼容演进。
       - engine_model_json：冗余存 engineModel 子树，便于后台只读引擎、报表、校验，而不必每次从 definition_json 解析。
     与前端：每次「保存/发布」生成一行；实例启动时锁定 process_def_ver_id。

  3) dbo.wf_node_def（可选但推荐）
     作用：把某版本下的**节点**从 JSON 里拆成行，便于按节点、按表单编码查询、统计、权限预检。
     来源：graphData.nodes[] 或 engineModel.nodes[]（建议保存时由程序同步写入，避免手写 SQL 解析 JSON）。
     典型：node_id 与画布 LogicFlow 节点 id 一致；form_code / field_rules_json 对应节点绑定表单。

  4) dbo.wf_edge_def（可选但推荐）
     作用：把某版本下的**连线/出口**拆成行，便于路由分析、条件命中统计、预测走向。
     来源：graphData.edges[] 或 engineModel.edges[]。

  --- 二、实例运行层（“某次请假单”这条正在跑的数据）---

  5) dbo.wf_instance
     作用：**流程实例**主表。一次「发起」= 一行。记录发起人、业务主键、当前状态、绑定哪一版定义等。
     与 JSON：不来自设计器 JSON；由引擎在「发起」时插入。

  6) dbo.wf_instance_data
     作用：实例在某个节点**提交/保存**时的表单快照（主表 + 页签表 JSON），用于审计、回显、重放。
     与 JSON：表单 schema 仍在外部表单库；这里只存**实例数据**；form_code 可与 wf_node_def 对齐。

  --- 三、待办与审批记录（运行态核心）---

  7) dbo.wf_task
     作用：**待办任务**。一条表示「某实例、某节点、分配给某人办理」的一条待办。
     典型：同节点会签可能多行；转办/复制会产生新行或关联 source_task_id。
     批量查询：按 assignee_user_id + status=待处理 即可拉出某人当前卡在所有流程上的全部节点（满足你提的 A 员工场景）。

  8) dbo.wf_action_log
     作用：**审批记录 / 操作流水**。同意、驳回、转办、撤回、干预跳转等均记一行。
     与 wf_task：可关联 task_id；干预类可把 from/to 写进 payload_json。

  --- 四、干预与批量操作 ---

  9) dbo.wf_intervention_rule
     作用：**人工干预规则**（定义级或实例级）。与 engineModel.manualIntervention 语义对齐。
     scope_type=1：绑定 process_def_ver_id（模板级）；scope_type=2：绑定 instance_id（仅本次实例覆盖）。

  10) dbo.wf_batch_op / dbo.wf_batch_op_item
     作用：**批量复制、批量转移**等异步/事务型操作的批次头与明细。
     典型：先插 batch_op，再逐条 item 更新 wf_task 并写 wf_action_log，保证可追溯。

  --- 五、自动测试 / 智能预测 ---

  11) dbo.wf_simulation_case
     作用：定义一组「给定表单输入 + 发起人上下文」下的**期望路径**或断言。

  12) dbo.wf_simulation_run
     作用：一次预测/回归运行的总结果（预测路径、是否通过、差异 JSON）。

  13) dbo.wf_simulation_node_result
     作用：预测过程中**逐步**每个节点的命中情况、解析出的办理人、条件命中原因等。

  =============================================================================
  【与当前前端「流程 JSON」的对应关系评估】
  =============================================================================

  当前设计器保存载荷（buildDefinitionPayload）大致结构为：
    {
      "processName", "processCode", "processVersion",
      "wfMeta": { ... },
      "graphData": { "nodes": [...], "edges": [...] },
      "engineModel": { "nodes": [...], "edges": [...], "executionPolicy", "manualIntervention", ... }
    }

  能直接对应上的表/字段：
    - wf_process_category
        ← 左侧树「文件夹」节点；与流程 JSON 无直接字段对应，由流程管理页维护 parent_id / name / sort_no。
    - wf_process_def.category_id
        ← 该流程挂在哪个目录下（叶子与目录分离）。
    - wf_process_def.process_code / process_name
        ← JSON 顶层 processCode / processName
    - wf_process_def_ver.definition_json
        ← 建议整包存入（含 graphData + engineModel + wfMeta），与前端 localStorage 草稿结构一致，还原成本最低
    - wf_process_def_ver.engine_model_json
        ← JSON.engineModel（冗余，便于引擎与报表）
    - wf_node_def
        ← 由 graphData.nodes[] 或 engineModel.nodes[] 解析写入（id、bizType→node_type、text、properties.formBinding 等）
    - wf_edge_def
        ← 由 graphData.edges[] 或 engineModel.edges[] 解析写入
    - wf_intervention_rule（定义级）
        ← engineModel.manualIntervention.rules[]（fromNodeId/forceToNodeId/enabled 等）

  不会出现在「流程 JSON」里、必须由引擎运行时写入的表：
    - wf_instance、wf_instance_data、wf_task、wf_action_log
    - wf_batch_op / wf_batch_op_item（批量操作运行时产生）
    - wf_simulation_*（测试/预测运行时产生；用例可手工维护）

  与「表单 schema」的关系：
    - 流程 JSON 里节点只有 formBinding.formCode（及 fieldRules），**不包含**表单设计器里的 schemaJson。
    - 表单 schema 应继续放在独立「表单定义表」（本脚本未建，你可命名为 wf_form_def 等），通过 form_code 关联。
    - wf_instance_data 存的是某次填报的 JSON 值，不是 schema。

  结论：当前表结构与现有「流程 JSON」**可以一一对应**；定义层主要靠 wf_process_def_ver + 拆表；
        运行层与 JSON 解耦，由引擎在发起/审批时写入。
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* =========================================================
   一、流程定义层
   ========================================================= */

/* 流程目录树：人事流程 / 行政流程 等文件夹；流程定义行通过 category_id 挂载 */
IF OBJECT_ID('dbo.wf_process_category', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_process_category (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    parent_id UNIQUEIDENTIFIER NULL,               -- 上级目录；根节点为 NULL
    folder_code NVARCHAR(64) NULL,                  -- 目录编码（可选，便于权限/同步）
    name NVARCHAR(128) NOT NULL,                    -- 目录显示名
    sort_no INT NOT NULL DEFAULT 0,                 -- 同级排序，小在前
    status TINYINT NOT NULL DEFAULT 1,              -- 1正常 0停用
    remark NVARCHAR(500) NULL,
    created_by NVARCHAR(64) NULL,
    created_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    updated_by NVARCHAR(64) NULL,
    updated_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_wf_process_category_parent FOREIGN KEY (parent_id) REFERENCES dbo.wf_process_category(id)
  );
  CREATE INDEX IX_wf_process_category_parent_sort ON dbo.wf_process_category(parent_id, sort_no, id);
  /* 同一父节点下 folder_code 不重复（允许多个 NULL） */
  CREATE UNIQUE NONCLUSTERED INDEX UQ_wf_process_category_parent_folder_code
    ON dbo.wf_process_category(parent_id, folder_code)
    WHERE folder_code IS NOT NULL;
END
GO

IF OBJECT_ID('dbo.wf_process_def', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_process_def (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    process_code NVARCHAR(64) NOT NULL,           -- 流程编码（业务唯一）
    process_name NVARCHAR(128) NOT NULL,          -- 流程名称
    category_id UNIQUEIDENTIFIER NULL,            -- 所属目录（wf_process_category），与左侧树叶子上级一致
    category_code NVARCHAR(64) NULL,              -- 流程分类编码（冗余/兼容，可与目录 folder_code 对齐）
    status TINYINT NOT NULL DEFAULT 0,            -- 0草稿 1已发布 2停用
    is_valid BIT NOT NULL DEFAULT 1,              -- 是否有效（业务开关，与 status 独立）
    latest_version INT NOT NULL DEFAULT 1,        -- 最新版本号
    created_by NVARCHAR(64) NULL,
    created_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    updated_by NVARCHAR(64) NULL,
    updated_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_wf_process_def_process_code UNIQUE (process_code),
    CONSTRAINT FK_wf_process_def_category FOREIGN KEY (category_id) REFERENCES dbo.wf_process_category(id)
  );
  CREATE INDEX IX_wf_process_def_category ON dbo.wf_process_def(category_id);
END
GO

/* 旧库已存在 wf_process_def 但尚无 category_id 时：补列、外键、索引（可重复执行） */
IF OBJECT_ID('dbo.wf_process_def', 'U') IS NOT NULL
  AND COL_LENGTH('dbo.wf_process_def', 'category_id') IS NULL
BEGIN
  ALTER TABLE dbo.wf_process_def ADD category_id UNIQUEIDENTIFIER NULL;
END
GO

IF OBJECT_ID('dbo.wf_process_def', 'U') IS NOT NULL
  AND COL_LENGTH('dbo.wf_process_def', 'category_id') IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'FK_wf_process_def_category' AND parent_object_id = OBJECT_ID('dbo.wf_process_def')
  )
BEGIN
  ALTER TABLE dbo.wf_process_def
    ADD CONSTRAINT FK_wf_process_def_category FOREIGN KEY (category_id) REFERENCES dbo.wf_process_category(id);
END
GO

IF NOT EXISTS (
  SELECT 1 FROM sys.indexes
  WHERE name = 'IX_wf_process_def_category' AND object_id = OBJECT_ID('dbo.wf_process_def')
)
  AND COL_LENGTH('dbo.wf_process_def', 'category_id') IS NOT NULL
BEGIN
  CREATE INDEX IX_wf_process_def_category ON dbo.wf_process_def(category_id);
END
GO

/* 旧库已存在 wf_process_def 但尚无 is_valid 时：补列（可重复执行） */
IF OBJECT_ID('dbo.wf_process_def', 'U') IS NOT NULL
  AND COL_LENGTH('dbo.wf_process_def', 'is_valid') IS NULL
BEGIN
  ALTER TABLE dbo.wf_process_def
    ADD is_valid BIT NOT NULL CONSTRAINT DF_wf_process_def_is_valid DEFAULT (1);
END
GO

IF OBJECT_ID('dbo.wf_process_def_ver', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_process_def_ver (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    process_def_id UNIQUEIDENTIFIER NOT NULL,      -- 对应 wf_process_def.id
    version_no INT NOT NULL,                       -- 版本号（递增）
    is_published BIT NOT NULL DEFAULT 0,           -- 是否已发布
    published_at DATETIME2(3) NULL,                -- 发布时间
    definition_json NVARCHAR(MAX) NOT NULL,        -- 全量定义（graphData + engineModel）
    engine_model_json NVARCHAR(MAX) NULL,          -- 冗余引擎模型（便于查询）
    checksum NVARCHAR(64) NULL,                    -- 版本签名/摘要
    created_by NVARCHAR(64) NULL,
    created_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_wf_process_def_ver_ver UNIQUE (process_def_id, version_no),
    CONSTRAINT FK_wf_process_def_ver_def FOREIGN KEY (process_def_id) REFERENCES dbo.wf_process_def(id)
  );
END
GO

IF OBJECT_ID('dbo.wf_node_def', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_node_def (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    process_def_ver_id UNIQUEIDENTIFIER NOT NULL,  -- 对应 wf_process_def_ver.id
    node_id NVARCHAR(64) NOT NULL,                 -- 画布节点ID
    node_name NVARCHAR(128) NULL,                  -- 节点名称
    node_type NVARCHAR(32) NOT NULL,               -- start/approve/cc/end/condition
    assignee_rule_json NVARCHAR(MAX) NULL,         -- 审批人策略快照
    form_code NVARCHAR(64) NULL,                   -- 节点绑定表单编码
    form_name NVARCHAR(128) NULL,                  -- 节点绑定表单名称
    field_rules_json NVARCHAR(MAX) NULL,           -- 字段策略（visible/hidden/readonly）
    created_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_wf_node_def_ver FOREIGN KEY (process_def_ver_id) REFERENCES dbo.wf_process_def_ver(id)
  );
  CREATE INDEX IX_wf_node_def_ver_node ON dbo.wf_node_def(process_def_ver_id, node_id);
  CREATE INDEX IX_wf_node_def_form_code ON dbo.wf_node_def(form_code);
END
GO

IF OBJECT_ID('dbo.wf_edge_def', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_edge_def (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    process_def_ver_id UNIQUEIDENTIFIER NOT NULL,  -- 对应 wf_process_def_ver.id
    edge_id NVARCHAR(64) NOT NULL,                 -- 连线ID
    source_node_id NVARCHAR(64) NOT NULL,          -- 源节点ID
    target_node_id NVARCHAR(64) NOT NULL,          -- 目标节点ID
    priority INT NOT NULL DEFAULT 100,             -- 连线优先级（小优先）
    rule_json NVARCHAR(MAX) NULL,                  -- 条件规则JSON
    created_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_wf_edge_def_ver FOREIGN KEY (process_def_ver_id) REFERENCES dbo.wf_process_def_ver(id)
  );
  CREATE INDEX IX_wf_edge_def_route ON dbo.wf_edge_def(process_def_ver_id, source_node_id, priority);
END
GO

/* =========================================================
   二、实例运行层
   ========================================================= */

IF OBJECT_ID('dbo.wf_instance', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_instance (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    instance_no NVARCHAR(64) NOT NULL,             -- 实例号（业务唯一）
    process_def_id UNIQUEIDENTIFIER NOT NULL,      -- 流程定义ID
    process_def_ver_id UNIQUEIDENTIFIER NOT NULL,  -- 流程定义版本ID（运行时固定）
    business_key NVARCHAR(128) NULL,               -- 业务主键（如请假单号）
    title NVARCHAR(256) NULL,                      -- 实例标题
    starter_user_id NVARCHAR(64) NOT NULL,         -- 发起人ID
    starter_dept_id NVARCHAR(64) NULL,             -- 发起部门ID
    status TINYINT NOT NULL DEFAULT 0,             -- 0运行中 1已完成 2已终止 3已撤回
    current_node_ids NVARCHAR(512) NULL,           -- 当前节点ID列表（逗号冗余）
    started_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    ended_at DATETIME2(3) NULL,
    created_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    updated_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_wf_instance_no UNIQUE (instance_no),
    CONSTRAINT FK_wf_instance_def FOREIGN KEY (process_def_id) REFERENCES dbo.wf_process_def(id),
    CONSTRAINT FK_wf_instance_def_ver FOREIGN KEY (process_def_ver_id) REFERENCES dbo.wf_process_def_ver(id)
  );
  CREATE INDEX IX_wf_instance_starter_status ON dbo.wf_instance(starter_user_id, status, created_at DESC);
  CREATE INDEX IX_wf_instance_def_status ON dbo.wf_instance(process_def_id, status);
END
GO

IF OBJECT_ID('dbo.wf_instance_data', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_instance_data (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    instance_id UNIQUEIDENTIFIER NOT NULL,         -- 实例ID
    node_id NVARCHAR(64) NOT NULL,                 -- 节点ID
    form_code NVARCHAR(64) NULL,                   -- 表单编码
    main_form_json NVARCHAR(MAX) NULL,             -- 主表单数据
    tabs_data_json NVARCHAR(MAX) NULL,             -- 页签表格数据
    snapshot_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(), -- 快照时间
    operator_user_id NVARCHAR(64) NULL,            -- 提交人
    CONSTRAINT FK_wf_instance_data_instance FOREIGN KEY (instance_id) REFERENCES dbo.wf_instance(id)
  );
  CREATE INDEX IX_wf_instance_data_snapshot ON dbo.wf_instance_data(instance_id, snapshot_at DESC);
  CREATE INDEX IX_wf_instance_data_node ON dbo.wf_instance_data(instance_id, node_id);
END
GO

/* =========================================================
   三、待办与审批记录
   ========================================================= */

IF OBJECT_ID('dbo.wf_task', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_task (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    task_no NVARCHAR(64) NOT NULL,                 -- 任务号（业务唯一）
    instance_id UNIQUEIDENTIFIER NOT NULL,         -- 实例ID
    node_id NVARCHAR(64) NOT NULL,                 -- 节点ID
    node_name NVARCHAR(128) NOT NULL,              -- 节点名称
    assignee_user_id NVARCHAR(64) NOT NULL,        -- 当前办理人ID
    assignee_name NVARCHAR(64) NULL,               -- 当前办理人名称
    task_type TINYINT NOT NULL DEFAULT 1,          -- 1审批 2抄送 3加签
    status TINYINT NOT NULL DEFAULT 0,             -- 0待处理 1已完成 2已拒绝 3已转办 4已取消 5已超时
    sign_mode NVARCHAR(16) NULL,                   -- all/any/sequential/cc
    batch_no INT NULL,                             -- 批次号
    source_task_id UNIQUEIDENTIFIER NULL,          -- 来源任务（复制/转移链路）
    tenant_id UNIQUEIDENTIFIER NULL,               -- 租户ID（可选）
    received_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    completed_at DATETIME2(3) NULL,
    due_at DATETIME2(3) NULL,
    created_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    updated_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_wf_task_no UNIQUE (task_no),
    CONSTRAINT FK_wf_task_instance FOREIGN KEY (instance_id) REFERENCES dbo.wf_instance(id),
    CONSTRAINT FK_wf_task_source FOREIGN KEY (source_task_id) REFERENCES dbo.wf_task(id)
  );
  -- 核心索引：查询某人当前待办
  CREATE INDEX IX_wf_task_assignee_status ON dbo.wf_task(assignee_user_id, status, received_at DESC);
  CREATE INDEX IX_wf_task_instance_node_status ON dbo.wf_task(instance_id, node_id, status);
END
GO

IF OBJECT_ID('dbo.wf_action_log', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_action_log (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    instance_id UNIQUEIDENTIFIER NOT NULL,         -- 实例ID
    task_id UNIQUEIDENTIFIER NULL,                 -- 关联任务ID
    node_id NVARCHAR(64) NOT NULL,                 -- 节点ID
    action_type NVARCHAR(32) NOT NULL,             -- submit/approve/reject/transfer/copy/add_sign/withdraw/terminate/intervene_jump
    action_result NVARCHAR(32) NULL,               -- 结果标记
    operator_user_id NVARCHAR(64) NOT NULL,        -- 操作人ID
    operator_name NVARCHAR(64) NULL,               -- 操作人名称
    comment NVARCHAR(1000) NULL,                   -- 审批意见/说明
    payload_json NVARCHAR(MAX) NULL,               -- 扩展数据（目标人、干预原因等）
    action_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    created_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_wf_action_log_instance FOREIGN KEY (instance_id) REFERENCES dbo.wf_instance(id),
    CONSTRAINT FK_wf_action_log_task FOREIGN KEY (task_id) REFERENCES dbo.wf_task(id)
  );
  CREATE INDEX IX_wf_action_log_instance_time ON dbo.wf_action_log(instance_id, action_at);
  CREATE INDEX IX_wf_action_log_task ON dbo.wf_action_log(task_id);
END
GO

/* =========================================================
   四、节点干预与批量操作
   ========================================================= */

IF OBJECT_ID('dbo.wf_intervention_rule', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_intervention_rule (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    scope_type TINYINT NOT NULL,                   -- 1流程定义级 2实例级
    process_def_ver_id UNIQUEIDENTIFIER NULL,      -- 定义级干预绑定版本
    instance_id UNIQUEIDENTIFIER NULL,             -- 实例级干预绑定实例
    from_node_id NVARCHAR(64) NOT NULL,            -- 干预起点节点
    force_to_node_id NVARCHAR(64) NOT NULL,        -- 干预目标节点
    enabled BIT NOT NULL DEFAULT 1,
    reason NVARCHAR(500) NULL,                     -- 干预原因
    priority INT NOT NULL DEFAULT 100,             -- 干预优先级
    created_by NVARCHAR(64) NULL,
    created_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    updated_by NVARCHAR(64) NULL,
    updated_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_wf_intervention_rule_ver FOREIGN KEY (process_def_ver_id) REFERENCES dbo.wf_process_def_ver(id),
    CONSTRAINT FK_wf_intervention_rule_instance FOREIGN KEY (instance_id) REFERENCES dbo.wf_instance(id)
  );
  CREATE INDEX IX_wf_intervention_rule_instance ON dbo.wf_intervention_rule(instance_id, enabled, priority);
  CREATE INDEX IX_wf_intervention_rule_ver ON dbo.wf_intervention_rule(process_def_ver_id, enabled, priority);
END
GO

IF OBJECT_ID('dbo.wf_batch_op', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_batch_op (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    op_no NVARCHAR(64) NOT NULL,                   -- 批量操作号（业务唯一）
    op_type NVARCHAR(32) NOT NULL,                 -- copy/transfer
    operator_user_id NVARCHAR(64) NOT NULL,        -- 执行人
    target_user_id NVARCHAR(64) NULL,              -- 转移目标人
    status TINYINT NOT NULL DEFAULT 0,             -- 0处理中 1成功 2部分成功 3失败
    summary NVARCHAR(500) NULL,                    -- 汇总信息
    created_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    finished_at DATETIME2(3) NULL,
    CONSTRAINT UQ_wf_batch_op_no UNIQUE (op_no)
  );
END
GO

IF OBJECT_ID('dbo.wf_batch_op_item', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_batch_op_item (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    batch_op_id UNIQUEIDENTIFIER NOT NULL,         -- 批量操作主表ID
    task_id UNIQUEIDENTIFIER NOT NULL,             -- 原任务ID
    instance_id UNIQUEIDENTIFIER NOT NULL,         -- 所属实例ID
    node_id NVARCHAR(64) NOT NULL,                 -- 所属节点ID
    result_code NVARCHAR(32) NULL,                 -- 执行结果码
    result_msg NVARCHAR(500) NULL,                 -- 执行结果消息
    new_task_id UNIQUEIDENTIFIER NULL,             -- 新任务ID（copy/transfer后）
    processed_at DATETIME2(3) NULL,
    CONSTRAINT FK_wf_batch_op_item_op FOREIGN KEY (batch_op_id) REFERENCES dbo.wf_batch_op(id),
    CONSTRAINT FK_wf_batch_op_item_task FOREIGN KEY (task_id) REFERENCES dbo.wf_task(id),
    CONSTRAINT FK_wf_batch_op_item_new_task FOREIGN KEY (new_task_id) REFERENCES dbo.wf_task(id)
  );
  CREATE INDEX IX_wf_batch_op_item_op ON dbo.wf_batch_op_item(batch_op_id);
  CREATE INDEX IX_wf_batch_op_item_task ON dbo.wf_batch_op_item(task_id);
END
GO

/* =========================================================
   五、自动测试 / 智能预测
   ========================================================= */

IF OBJECT_ID('dbo.wf_simulation_case', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_simulation_case (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    case_no NVARCHAR(64) NOT NULL,                 -- 用例编号（业务唯一）
    name NVARCHAR(128) NOT NULL,                   -- 用例名称
    process_def_ver_id UNIQUEIDENTIFIER NOT NULL,  -- 对应流程版本
    input_form_json NVARCHAR(MAX) NOT NULL,        -- 模拟输入表单
    starter_context_json NVARCHAR(MAX) NULL,       -- 模拟发起人上下文
    expected_path_json NVARCHAR(MAX) NULL,         -- 预期路径（节点序列）
    enabled BIT NOT NULL DEFAULT 1,
    created_by NVARCHAR(64) NULL,
    created_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_wf_simulation_case_no UNIQUE (case_no),
    CONSTRAINT FK_wf_simulation_case_ver FOREIGN KEY (process_def_ver_id) REFERENCES dbo.wf_process_def_ver(id)
  );
  CREATE INDEX IX_wf_simulation_case_ver ON dbo.wf_simulation_case(process_def_ver_id, enabled);
END
GO

IF OBJECT_ID('dbo.wf_simulation_run', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_simulation_run (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    run_no NVARCHAR(64) NOT NULL,                  -- 运行编号（业务唯一）
    case_id UNIQUEIDENTIFIER NOT NULL,             -- 用例ID
    engine_version NVARCHAR(32) NULL,              -- 引擎版本
    predicted_path_json NVARCHAR(MAX) NULL,        -- 预测路径
    actual_path_json NVARCHAR(MAX) NULL,           -- 实际路径（可选）
    pass BIT NULL,                                 -- 是否通过
    diff_json NVARCHAR(MAX) NULL,                  -- 差异明细
    started_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    ended_at DATETIME2(3) NULL,
    CONSTRAINT UQ_wf_simulation_run_no UNIQUE (run_no),
    CONSTRAINT FK_wf_simulation_run_case FOREIGN KEY (case_id) REFERENCES dbo.wf_simulation_case(id)
  );
  CREATE INDEX IX_wf_simulation_run_case_time ON dbo.wf_simulation_run(case_id, started_at DESC);
END
GO

IF OBJECT_ID('dbo.wf_simulation_node_result', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.wf_simulation_node_result (
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    run_id UNIQUEIDENTIFIER NOT NULL,              -- 运行记录ID
    seq_no INT NOT NULL,                           -- 步骤序号
    node_id NVARCHAR(64) NOT NULL,                 -- 节点ID
    node_name NVARCHAR(128) NULL,                  -- 节点名称
    route_hit BIT NULL,                            -- 是否命中该路由
    assignees_json NVARCHAR(MAX) NULL,             -- 预测办理人列表
    reason_json NVARCHAR(MAX) NULL,                -- 命中原因（条件日志）
    created_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_wf_simulation_node_result_run FOREIGN KEY (run_id) REFERENCES dbo.wf_simulation_run(id)
  );
  CREATE INDEX IX_wf_simulation_node_result_run_seq ON dbo.wf_simulation_node_result(run_id, seq_no);
END
GO

/* =========================================================
   六、典型查询（示例）
   =========================================================
   1) 查询某人当前所有待办节点（支持“卡在哪些流程哪些节点”）
      SELECT t.*, i.instance_no, i.title, d.process_code, d.process_name
      FROM dbo.wf_task t
      JOIN dbo.wf_instance i ON i.id = t.instance_id
      JOIN dbo.wf_process_def d ON d.id = i.process_def_id
      WHERE t.assignee_user_id = @UserId AND t.status = 0
      ORDER BY t.received_at DESC;

   2) 批量转移/复制：先写 wf_batch_op，再写 wf_batch_op_item，事务中逐条处理并记录 wf_action_log。

   3) 流程目录树 + 叶子流程（支撑左侧树 UI）
      - 目录：SELECT * FROM dbo.wf_process_category WHERE parent_id = @ParentId ORDER BY sort_no, id;
      - 某目录下流程：SELECT * FROM dbo.wf_process_def WHERE category_id = @CategoryId ORDER BY process_name;
      - 根下所有一级目录：SELECT * FROM dbo.wf_process_category WHERE parent_id IS NULL ORDER BY sort_no;
      多级目录可用递归 CTE 按 parent_id 展开，叶子节点类型在应用层区分：有子目录则继续查 category，无则并列查 wf_process_def。
*/

