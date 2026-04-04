/*
  [1008] 一键迁移：考勤日常处理 → 考勤日结果（只读列表 v_att_lst_DayResult）

  与 1002 刷卡资料查询 同模式：列表设计器 + 导出/刷新，无新增/编辑/删除。

  列表列：与 dbo.v_att_lst_DayResult 视图字段对齐（README：列表 tableName/列 field 须与 query 对象一致）。
  老系统 t_set_datagrid 若列名/顺序不同，可在列表设计器里再改；多余列可用工具栏「列设置」隐藏。

  行为：
    - 删除「固定 id」上的本菜单旧数据 + 列表设计器行（幂等重插）
    - 删除库内其它 meta 指向 v_att_lst_DayResult 的叶子菜单（避免重复入口），不动「考勤日常处理」分组
    - 无需手工改 GUID；执行本脚本即可

  前置：
    - 根菜单「考勤管理」A1000001-0001-4001-8001-000000000001
    - 「考勤日常处理」mid A1000001-0001-4001-8001-000000000030（1002）

  固定 id（勿与其它脚本冲突）：
    - 叶子菜单 A1000001-0001-4001-8001-000000000036
    - 列表设计器 A1000001-0001-4001-8001-000000000236
*/

SET NOCOUNT ON;

DECLARE @role_name NVARCHAR(50) = N'系统管理员';
DECLARE @role_id UNIQUEIDENTIFIER;
SELECT TOP 1 @role_id = r.id FROM dbo.vben_role r WHERE r.name = @role_name;
IF @role_id IS NULL
BEGIN
  RAISERROR(N'Role not found: %s', 16, 1, @role_name);
  RETURN;
END

DECLARE @root_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000001';
IF NOT EXISTS (SELECT 1 FROM dbo.vben_menus_new WHERE id = @root_menu_id)
BEGIN
  RAISERROR(N'根菜单不存在：考勤管理。请先初始化考勤模块菜单。', 16, 1);
  RETURN;
END

DECLARE @mid_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000030';
IF NOT EXISTS (SELECT 1 FROM dbo.vben_menus_new WHERE id = @mid_menu_id)
BEGIN
  RAISERROR(N'父菜单不存在：考勤日常处理。请先执行 1002_migrate_full_刷卡资料查询.sql。', 16, 1);
  RETURN;
END

DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000036';
DECLARE @list_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000236';

DECLARE @list_code NVARCHAR(200) = N'v_att_lst_DayResult';
DECLARE @title_leaf NVARCHAR(200) = N'考勤日结果';
DECLARE @path_leaf NVARCHAR(255) = N'/attendance/daily/day-result';
DECLARE @component NVARCHAR(255) = N'/EntityList/entityListFromDesigner';

DECLARE @act_exp_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000370';
DECLARE @act_reload_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000371';

DECLARE @meta_leaf NVARCHAR(700) =
  N'{"title":"考勤日结果","icon":"lucide:calendar-check","query":{"entityname":"v_att_lst_DayResult","menuid":"A1000001-0001-4001-8001-000000000036"}}';

DECLARE @schema_json NVARCHAR(MAX) = N'{
  "title": "考勤日结果",
  "tableName": "v_att_lst_DayResult",
  "primaryKey": "FID",
  "toolbar": {
    "actions": [
      { "key": "export", "label": "导出", "action": "export" },
      { "key": "reload", "label": "刷新", "action": "reload", "type": "primary" }
    ]
  },
  "form": {
    "collapsed": false,
    "submitOnChange": false,
    "wrapperClass": "grid-cols-1 md:grid-cols-2 lg:grid-cols-3",
    "schema": [
      { "component": "Input", "fieldName": "EMP_ID", "label": "工号" },
      { "component": "Input", "fieldName": "name", "label": "姓名" },
      { "component": "Input", "fieldName": "long_name", "label": "部门" },
      { "component": "DatePicker", "fieldName": "attdate", "label": "考勤日期", "componentProps": { "format": "YYYY-MM-DD", "valueFormat": "YYYY-MM-DD", "allowClear": true } },
      { "component": "Input", "fieldName": "attStatus", "label": "状态码" },
      { "component": "Input", "fieldName": "attStatusName", "label": "出勤状态" },
      { "component": "Input", "fieldName": "approval", "label": "核准" },
      { "component": "Input", "fieldName": "monthApprove", "label": "月核准" },
      { "component": "Input", "fieldName": "OperatorName", "label": "操作人" }
    ]
  },
  "grid": {
    "pagerConfig": { "enabled": true, "pageSize": 50 },
    "sortConfig": { "remote": true, "defaultSort": { "field": "attdate", "order": "desc" } },
    "toolbarConfig": { "custom": true },
    "columns": [
      { "type": "seq", "width": 60 },
      { "field": "FID", "title": "记录ID", "width": 280, "sortable": true },
      { "field": "ShiftID", "title": "班次ID", "width": 280, "sortable": true },
      { "field": "attHolidayID", "title": "节日ID", "width": 280, "sortable": true },
      { "field": "dept_id", "title": "部门ID", "width": 280, "sortable": true },
      { "field": "EMP_ID", "title": "工号", "width": 96, "sortable": true },
      { "field": "name", "title": "姓名", "width": 100, "sortable": true },
      { "field": "long_name", "title": "部门", "minWidth": 160, "sortable": true },
      { "field": "dutyName", "title": "岗位", "width": 100, "sortable": true },
      { "field": "frist_join_date", "title": "入职日期", "width": 120, "sortable": true },
      { "field": "attdate", "title": "考勤日期", "width": 120, "sortable": true },
      { "field": "weekday", "title": "星期", "width": 90, "sortable": true },
      { "field": "isHoliday", "title": "是否节假日", "width": 100, "sortable": true },
      { "field": "code_name", "title": "班次名称", "minWidth": 160, "sortable": false },
      { "field": "attStatus", "title": "状态", "width": 90, "sortable": true },
      { "field": "attStatusName", "title": "出勤状态", "width": 100, "sortable": true },
      { "field": "attTime", "title": "标准时间", "width": 100, "sortable": true },
      { "field": "attDay", "title": "出勤天数", "width": 90, "sortable": true },
      { "field": "attLate", "title": "迟到(分)", "width": 90, "sortable": true },
      { "field": "attEarly", "title": "早退(分)", "width": 90, "sortable": true },
      { "field": "attAbsenteeism", "title": "旷工(分)", "width": 90, "sortable": true },
      { "field": "attHoliday", "title": "节日工时", "width": 90, "sortable": true },
      { "field": "attovertime15", "title": "加班1.5", "width": 90, "sortable": true },
      { "field": "attovertime20", "title": "加班2.0", "width": 90, "sortable": true },
      { "field": "attovertime30", "title": "加班3.0", "width": 90, "sortable": true },
      { "field": "BCST1", "title": "班别上班1", "width": 100, "sortable": false },
      { "field": "BCET1", "title": "班别下班1", "width": 100, "sortable": false },
      { "field": "ST1", "title": "刷卡上班1", "width": 100, "sortable": false },
      { "field": "ET1", "title": "刷卡下班1", "width": 100, "sortable": false },
      { "field": "BCST2", "title": "班别上班2", "width": 100, "sortable": false },
      { "field": "BCET2", "title": "班别下班2", "width": 100, "sortable": false },
      { "field": "ST2", "title": "刷卡上班2", "width": 100, "sortable": false },
      { "field": "ET2", "title": "刷卡下班2", "width": 100, "sortable": false },
      { "field": "BCST3", "title": "班别上班3", "width": 100, "sortable": false },
      { "field": "BCET3", "title": "班别下班3", "width": 100, "sortable": false },
      { "field": "ST3", "title": "刷卡上班3", "width": 100, "sortable": false },
      { "field": "ET3", "title": "刷卡下班3", "width": 100, "sortable": false },
      { "field": "attStatus1Name", "title": "段1状态", "width": 90, "sortable": true },
      { "field": "attStatus2Name", "title": "段2状态", "width": 90, "sortable": true },
      { "field": "attStatus3Name", "title": "段3状态", "width": 90, "sortable": true },
      { "field": "attStatus1", "title": "段1状态码", "width": 90, "sortable": true },
      { "field": "attStatus2", "title": "段2状态码", "width": 90, "sortable": true },
      { "field": "attStatus3", "title": "段3状态码", "width": 90, "sortable": true },
      { "field": "begin_time_tag1", "title": "开始标记1", "width": 90, "sortable": true },
      { "field": "end_time_tag1", "title": "结束标记1", "width": 90, "sortable": true },
      { "field": "begin_time_tag2", "title": "开始标记2", "width": 90, "sortable": true },
      { "field": "end_time_tag2", "title": "结束标记2", "width": 90, "sortable": true },
      { "field": "planBeginDayFlag1", "title": "计划头跨1", "width": 90, "sortable": false },
      { "field": "planEndDayFlag1", "title": "计划尾跨1", "width": 90, "sortable": false },
      { "field": "planBeginDayFlag2", "title": "计划头跨2", "width": 90, "sortable": false },
      { "field": "planEndDayFlag2", "title": "计划尾跨2", "width": 90, "sortable": false },
      { "field": "planBeginDayFlag3", "title": "计划头跨3", "width": 90, "sortable": false },
      { "field": "planEndDayFlag3", "title": "计划尾跨3", "width": 90, "sortable": false },
      { "field": "approval", "title": "核准", "width": 80, "sortable": true },
      { "field": "approvaler", "title": "核准人", "width": 100, "sortable": true },
      { "field": "approvalTime", "title": "核准时间", "width": 170, "sortable": true },
      { "field": "monthApprove", "title": "月核准", "width": 90, "sortable": true },
      { "field": "approveStatus", "title": "已审核", "width": 80, "sortable": true },
      { "field": "ModifyTime", "title": "修改时间", "width": 170, "sortable": true },
      { "field": "type", "title": "类型", "width": 90, "sortable": true },
      { "field": "DateType", "title": "日期类型", "width": 100, "sortable": true },
      { "field": "ApprovalType", "title": "核准类型", "width": 100, "sortable": true },
      { "field": "AttendancePerformance", "title": "出勤绩效", "width": 100, "sortable": true },
      { "field": "OvertimeType", "title": "加班类型", "width": 100, "sortable": true },
      { "field": "ExceptionType", "title": "异常类型", "width": 100, "sortable": true },
      { "field": "labor", "title": "用工", "minWidth": 120, "sortable": false },
      { "field": "dpm_id", "title": "部门参数", "width": 100, "sortable": true },
      { "field": "ps_id", "title": "编制", "width": 100, "sortable": true },
      { "field": "cancel", "title": "作废", "width": 80, "sortable": true },
      { "field": "cancelTime", "title": "作废时间", "width": 170, "sortable": true },
      { "field": "PushAbsenteeism", "title": "推送旷工", "width": 120, "sortable": false },
      { "field": "PushAbsenteeismStatus", "title": "推送旷工状态", "width": 120, "sortable": true },
      { "field": "errorMessage", "title": "异常信息", "minWidth": 200, "sortable": false },
      { "field": "OperatorName", "title": "操作人", "width": 100, "sortable": true },
      { "field": "OperationTime", "title": "操作时间", "width": 170, "sortable": true }
    ]
  },
  "api": {
    "query": "__API_QUERY__",
    "delete": "",
    "export": "__API_EXPORT__"
  }
}';

DECLARE @api_query NVARCHAR(500) = NULL;
DECLARE @api_export NVARCHAR(500) = NULL;

SELECT TOP 1
  @api_query = JSON_VALUE(schema_json, '$.api.query'),
  @api_export = JSON_VALUE(schema_json, '$.api.export')
FROM dbo.vben_entitylist_desinger
WHERE code IN (N'v_att_lst_Cardrecord', N'mig_att_holiday_category', N'v_att_lst_Holiday')
  AND JSON_VALUE(schema_json, '$.api.query') IS NOT NULL;

IF @api_query IS NULL OR LTRIM(RTRIM(@api_query)) = N''
  SET @api_query = N'http://127.0.0.1:5155/api/DynamicQueryBeta/queryforvben';
IF @api_export IS NULL OR LTRIM(RTRIM(@api_export)) = N''
  SET @api_export = N'http://127.0.0.1:5155/api/DynamicQueryBeta/ExportExcel';

SET @schema_json = REPLACE(@schema_json, N'__API_QUERY__', REPLACE(@api_query, N'"', N'\"'));
SET @schema_json = REPLACE(@schema_json, N'__API_EXPORT__', REPLACE(@api_export, N'"', N'\"'));

/* ========== 待清理的叶子菜单：固定 id + 其它指向同一 entity 的旧菜单 ========== */
DECLARE @menu_cleanup TABLE (id UNIQUEIDENTIFIER PRIMARY KEY);

INSERT INTO @menu_cleanup(id)
SELECT @leaf_menu_id
WHERE EXISTS (SELECT 1 FROM dbo.vben_menus_new WHERE id = @leaf_menu_id);

INSERT INTO @menu_cleanup(id)
SELECT m.id
FROM dbo.vben_menus_new AS m
WHERE m.type = N'menu'
  AND m.id NOT IN (@mid_menu_id, @root_menu_id)
  AND m.id <> @leaf_menu_id
  AND m.meta IS NOT NULL
  AND UPPER(CAST(m.meta AS NVARCHAR(MAX))) LIKE N'%V_ATT_LST_DAYRESULT%'
  AND NOT EXISTS (SELECT 1 FROM @menu_cleanup AS c WHERE c.id = m.id);

INSERT INTO @menu_cleanup(id)
SELECT m.id
FROM dbo.vben_menus_new AS m
WHERE m.type = N'menu'
  AND m.id NOT IN (@mid_menu_id, @root_menu_id)
  AND m.id <> @leaf_menu_id
  AND m.path = @path_leaf
  AND NOT EXISTS (SELECT 1 FROM @menu_cleanup AS c WHERE c.id = m.id);

/* ========== 幂等：先卸权限与按钮，再删菜单 ========== */
DELETE rma
FROM dbo.vben_t_sys_role_menu_actions AS rma
INNER JOIN @menu_cleanup AS c ON c.id = rma.menu_id;

DELETE ma
FROM dbo.vben_menu_actions AS ma
INNER JOIN @menu_cleanup AS c ON c.id = ma.menu_id;

DELETE rm
FROM dbo.vben_t_sys_role_menus AS rm
INNER JOIN @menu_cleanup AS c ON c.id = rm.menus_id;

DELETE m
FROM dbo.vben_menus_new AS m
INNER JOIN @menu_cleanup AS c ON c.id = m.id;

DELETE FROM dbo.vben_entitylist_desinger WHERE id = @list_id OR code = @list_code;

/* ========== 列表 ========== */
INSERT INTO dbo.vben_entitylist_desinger (id, code, title, table_name, schema_json, created_at, updated_at)
VALUES (@list_id, @list_code, @title_leaf, @list_code, @schema_json, GETDATE(), GETDATE());

/* ========== 菜单叶子 ========== */
INSERT INTO dbo.vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@leaf_menu_id, @title_leaf, @path_leaf, @component, @meta_leaf, @mid_menu_id, 1, N'menu', 11);

INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id, add_time)
VALUES (NEWID(), @role_id, @leaf_menu_id, GETDATE());

INSERT INTO dbo.vben_menu_actions (id, menu_id, action_key, label, button_type, action, confirm_text, sort, status, form_code, requires_selection)
VALUES
  (@act_exp_id, @leaf_menu_id, N'export', N'导出', N'default', N'export', NULL, 40, 1, NULL, 0),
  (@act_reload_id, @leaf_menu_id, N'reload', N'刷新', N'primary', N'reload', NULL, 50, 1, NULL, 0);

INSERT INTO dbo.vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status, add_time)
VALUES
  (NEWID(), @role_id, @act_exp_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_reload_id, @leaf_menu_id, 1, GETDATE());

IF OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(N'v_att_lst_DayResult'), N'V') IS NULL
  AND OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(N'v_att_lst_DayResult'), N'U') IS NULL
  PRINT N'[1008] 警告：dbo.v_att_lst_DayResult 不存在，查询可能失败。';

PRINT N'OK: [1008] 考勤日常处理 → 考勤日结果 已迁移（列表=' + @list_code + N'，叶子 menuid=' + CONVERT(NVARCHAR(36), @leaf_menu_id) + N'）。';
