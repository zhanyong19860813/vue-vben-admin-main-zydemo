/*
  [1008] 一键迁移：考勤日常处理 → 考勤日结果（只读列表 v_att_lst_DayResult）

  与 1002 刷卡资料查询 同模式：列表设计器 + 导出/刷新，无新增/编辑/删除。

  列表列：与 dbo.v_att_lst_DayResult 视图字段对齐；**表头合并**：**第一段、第二段、第三段** 三个父表头紧挨排列（每段下 **5 列**：计划开始、上班、计划结束、段状态、下班），接迟到/早退等指标列与「异常说明」等。
  t_set_datagrid 同 sort 下多列按 name 排序与界面列序不完全一致，以老 UI 为准。假别列绑定 attHolidayName（视图补列）。
  本脚本会尝试 ALTER VIEW，增加 hc.HC_Name AS attHolidayName。
  老系统 t_set_datagrid 若列名/顺序不同，可在列表设计器里再改；多余列可用工具栏「列设置」隐藏。

  行为：
    - 工具栏「执行日结」：前端弹窗收集日期 / 部门 / 人员后调用 StoneApi Procedure/execute → dbo.att_pro_DayResult（超时 600s）
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

DECLARE @act_day_settle_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000372';
DECLARE @act_exp_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000370';
DECLARE @act_reload_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000371';

DECLARE @meta_leaf NVARCHAR(700) =
  N'{"title":"考勤日结果","icon":"lucide:calendar-check","query":{"entityname":"v_att_lst_DayResult","menuid":"A1000001-0001-4001-8001-000000000036"}}';

DECLARE @schema_json NVARCHAR(MAX) = N'{
  "title": "考勤日结果",
  "tableName": "v_att_lst_DayResult",
  "primaryKey": "FID",
  "actionModule": "/src/views/EntityList/dayResultActions.ts",
  "toolbar": {
    "actions": [
      { "key": "executeDaySettlement", "label": "执行日结", "action": "executeDaySettlement", "type": "primary" },
      { "key": "export", "label": "导出", "action": "export" },
      { "key": "reload", "label": "刷新", "action": "reload" }
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
      { "component": "RangePicker", "fieldName": "attdate", "label": "出勤日期", "componentProps": { "format": "YYYY-MM-DD", "valueFormat": "YYYY-MM-DD", "placeholder": ["开始日期", "结束日期"], "allowClear": true } },
      { "component": "Input", "fieldName": "attStatus", "label": "出勤状态ID" },
      { "component": "Input", "fieldName": "attStatusName", "label": "出勤状态" },
      { "component": "Input", "fieldName": "approval", "label": "审批状态" },
      { "component": "Input", "fieldName": "monthApprove", "label": "月结果审核状态" },
      { "component": "Input", "fieldName": "OperatorName", "label": "操作人" }
    ]
  },
  "grid": {
    "maxHeight": "calc(100vh - 260px)",
    "pagerConfig": { "enabled": true, "pageSize": 300 },
    "sortConfig": { "remote": true, "defaultSort": { "field": "attdate", "order": "asc" } },
    "toolbarConfig": { "custom": true },
    "columns": [
      { "type": "seq", "width": 60 },
      { "field": "EMP_ID", "title": "工号", "width": 96, "sortable": true },
      { "field": "name", "title": "姓名", "width": 100, "sortable": true },
      { "field": "long_name", "title": "部门", "minWidth": 160, "sortable": true },
      { "field": "dutyName", "title": "职务", "width": 100, "sortable": true },
      { "field": "approval", "title": "审批状态", "width": 80, "sortable": true },
      { "field": "attdate", "title": "出勤日期", "width": 120, "sortable": true },
      { "field": "monthApprove", "title": "月结果审核状态", "width": 100, "sortable": true },
      { "field": "PushAbsenteeismStatus", "title": "是否推送旷工", "width": 110, "sortable": true },
      { "field": "weekday", "title": "星期", "width": 90, "sortable": true },
      { "field": "attStatusName", "title": "出勤状态", "width": 100, "sortable": true },
      { "field": "ApprovalType", "title": "审批Type", "width": 90, "sortable": true },
      { "field": "code_name", "title": "班次名称", "minWidth": 140, "sortable": false },
      { "field": "DateType", "title": "日期类型", "width": 100, "sortable": true },
      { "field": "OvertimeType", "title": "加班类型", "width": 100, "sortable": true },
      { "field": "attDay", "title": "出勤天数", "width": 90, "sortable": true, "aggFunc": "sum" },
      { "field": "AttendancePerformance", "title": "出勤表现", "width": 100, "sortable": true },
      { "field": "ExceptionType", "title": "异常类型", "width": 100, "sortable": true },
      { "title": "第一段", "children": [
        { "field": "BCST1", "title": "计划开始时间1", "width": 100, "sortable": false },
        { "field": "ST1", "title": "上班时间1", "width": 90, "sortable": false },
        { "field": "BCET1", "title": "计划结束时间1", "width": 100, "sortable": false },
        { "field": "attStatus1Name", "title": "第一段状态", "width": 90, "sortable": true },
        { "field": "ET1", "title": "下班时间1", "width": 90, "sortable": false }
      ]},
      { "title": "第二段", "children": [
        { "field": "BCST2", "title": "计划开始时间2", "width": 100, "sortable": false },
        { "field": "ST2", "title": "上班时间2", "width": 90, "sortable": false },
        { "field": "BCET2", "title": "计划结束时间2", "width": 100, "sortable": false },
        { "field": "attStatus2Name", "title": "第二段状态", "width": 90, "sortable": true },
        { "field": "ET2", "title": "下班时间2", "width": 90, "sortable": false }
      ]},
      { "title": "第三段", "children": [
        { "field": "BCST3", "title": "计划开始时间3", "width": 100, "sortable": false },
        { "field": "ST3", "title": "上班时间3", "width": 90, "sortable": false },
        { "field": "BCET3", "title": "计划结束时间3", "width": 100, "sortable": false },
        { "field": "attStatus3Name", "title": "第三段状态", "width": 90, "sortable": true },
        { "field": "ET3", "title": "下班时间3", "width": 90, "sortable": false }
      ]},
      { "field": "attLate", "title": "迟到数(m)", "width": 90, "sortable": true, "aggFunc": "sum" },
      { "field": "attEarly", "title": "早退数(m)", "width": 90, "sortable": true, "aggFunc": "sum" },
      { "field": "attAbsenteeism", "title": "旷工数(d)", "width": 90, "sortable": true },
      { "field": "attTime", "title": "出勤时数", "width": 100, "sortable": true },
      { "field": "attovertime15", "title": "日常加班", "width": 90, "sortable": true },
      { "field": "attovertime20", "title": "公休日加班", "width": 100, "sortable": true },
      { "field": "attovertime30", "title": "法定节假日加班", "width": 120, "sortable": true },
      { "field": "attHoliday", "title": "请假天数(d)", "width": 100, "sortable": true },
      { "field": "isHoliday", "title": "是否假日", "width": 100, "sortable": true },
      { "field": "attHolidayName", "title": "假别", "minWidth": 120, "sortable": false },
      { "field": "errorMessage", "title": "异常说明", "minWidth": 160, "sortable": false },
      { "field": "OperatorName", "title": "操作人", "width": 100, "sortable": true },
      { "field": "OperationTime", "title": "操作时间", "width": 170, "sortable": true },
      { "field": "approvaler", "title": "审批者", "width": 100, "sortable": true },
      { "field": "approvalTime", "title": "审批时间", "width": 170, "sortable": true },
      { "field": "approveStatus", "title": "审批类型", "width": 100, "sortable": true },
      { "field": "cancel", "title": "取消审核者", "width": 110, "sortable": true },
      { "field": "cancelTime", "title": "取消审核时间", "width": 170, "sortable": true },
      { "field": "labor", "title": "劳务派遣", "minWidth": 120, "sortable": false },
      { "field": "FID", "title": "FID", "width": 80, "visible": false, "sortable": false },
      { "field": "ShiftID", "title": "班次ID", "width": 80, "visible": false, "sortable": false },
      { "field": "attHolidayID", "title": "假别ID", "width": 80, "visible": false, "sortable": false },
      { "field": "attStatus", "title": "出勤状态ID", "width": 100, "visible": false, "sortable": false },
      { "field": "dpm_id", "title": "dpm_id", "width": 100, "visible": false, "sortable": false },
      { "field": "PushAbsenteeism", "title": "PushAbsenteeism", "width": 80, "visible": false, "sortable": false },
      { "field": "frist_join_date", "title": "入职日期", "width": 120, "visible": false, "sortable": true },
      { "field": "ps_id", "title": "编制", "width": 100, "visible": false, "sortable": true },
      { "field": "ModifyTime", "title": "修改时间", "width": 170, "visible": false, "sortable": true },
      { "field": "type", "title": "类型", "width": 90, "visible": false, "sortable": true },
      { "field": "dept_id", "title": "部门ID", "width": 100, "visible": false, "sortable": false },
      { "field": "begin_time_tag1", "title": "开始标记1", "width": 90, "visible": false, "sortable": true },
      { "field": "end_time_tag1", "title": "结束标记1", "width": 90, "visible": false, "sortable": true },
      { "field": "begin_time_tag2", "title": "开始标记2", "width": 90, "visible": false, "sortable": true },
      { "field": "end_time_tag2", "title": "结束标记2", "width": 90, "visible": false, "sortable": true },
      { "field": "planBeginDayFlag1", "title": "计划头跨1", "width": 90, "visible": false, "sortable": false },
      { "field": "planEndDayFlag1", "title": "计划尾跨1", "width": 90, "visible": false, "sortable": false },
      { "field": "planBeginDayFlag2", "title": "计划头跨2", "width": 90, "visible": false, "sortable": false },
      { "field": "planEndDayFlag2", "title": "计划尾跨2", "width": 90, "visible": false, "sortable": false },
      { "field": "planBeginDayFlag3", "title": "计划头跨3", "width": 90, "visible": false, "sortable": false },
      { "field": "planEndDayFlag3", "title": "计划尾跨3", "width": 90, "visible": false, "sortable": false },
      { "field": "attStatus1", "title": "段1状态码", "width": 90, "visible": false, "sortable": true },
      { "field": "attStatus2", "title": "段2状态码", "width": 90, "visible": false, "sortable": true },
      { "field": "attStatus3", "title": "段3状态码", "width": 90, "visible": false, "sortable": true }
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

/* ========== 视图：补 attHolidayName（列表「节日」列绑定；依赖已有 JOIN hc） ========== */
BEGIN
  DECLARE @__vsql1008 NVARCHAR(MAX);
  IF OBJECT_ID(N'dbo.v_att_lst_DayResult', N'V') IS NOT NULL
  BEGIN
    SET @__vsql1008 = OBJECT_DEFINITION(OBJECT_ID(N'dbo.v_att_lst_DayResult'));
    IF @__vsql1008 IS NOT NULL
       AND CHARINDEX(N'attHolidayName', @__vsql1008) = 0
       AND CHARINDEX(N'dr.attHolidayID,', @__vsql1008) > 0
    BEGIN
      SET @__vsql1008 = REPLACE(@__vsql1008, N'CREATE VIEW', N'ALTER VIEW');
      SET @__vsql1008 = REPLACE(@__vsql1008, N'dr.attHolidayID,', N'dr.attHolidayID, hc.HC_Name AS attHolidayName,');
      EXEC sp_executesql @__vsql1008;
      PRINT N'[1008] ALTER VIEW v_att_lst_DayResult：已增加 attHolidayName。';
    END
  END
END

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
  (@act_day_settle_id, @leaf_menu_id, N'executeDaySettlement', N'执行日结', N'primary', N'executeDaySettlement', NULL, 30, 1, NULL, 0),
  (@act_exp_id, @leaf_menu_id, N'export', N'导出', N'default', N'export', NULL, 40, 1, NULL, 0),
  (@act_reload_id, @leaf_menu_id, N'reload', N'刷新', N'default', N'reload', NULL, 50, 1, NULL, 0);

INSERT INTO dbo.vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status, add_time)
VALUES
  (NEWID(), @role_id, @act_day_settle_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_exp_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_reload_id, @leaf_menu_id, 1, GETDATE());

IF OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(N'v_att_lst_DayResult'), N'V') IS NULL
  AND OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(N'v_att_lst_DayResult'), N'U') IS NULL
  PRINT N'[1008] 警告：dbo.v_att_lst_DayResult 不存在，查询可能失败。';

PRINT N'OK: [1008] 考勤日常处理 → 考勤日结果 已迁移（列表=' + @list_code + N'，叶子 menuid=' + CONVERT(NVARCHAR(36), @leaf_menu_id) + N'）。';
