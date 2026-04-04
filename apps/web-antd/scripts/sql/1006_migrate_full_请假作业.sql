/*
  [1006] 一键迁移：考勤日常处理 → 请假作业（列表 + 表单 CRUD）

  老系统：t_sys_function.name=请假作业，entity=v_att_lst_Holiday，父=考勤日常处理
  物理表：dbo.att_lst_Holiday（视图 FROM），主键 FID；老系统按钮：新增/修改/删除/导出（无审核）

  新系统：path=/attendance/daily/leave-work，component=/EntityList/entityListFromDesigner
  前置：1002（父菜单 考勤日常处理）

  幂等：删本叶子、列表/表单设计器、本菜单按钮及角色关联后重插。
*/

SET NOCOUNT ON;

DECLARE @role_name NVARCHAR(50) = N'系统管理员';
DECLARE @role_id UNIQUEIDENTIFIER;
SELECT TOP 1 @role_id = r.id FROM vben_role r WHERE r.name = @role_name;
IF @role_id IS NULL
BEGIN
  RAISERROR(N'Role not found: %s', 16, 1, @role_name);
  RETURN;
END

DECLARE @mid_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000030';
IF NOT EXISTS (SELECT 1 FROM vben_menus_new WHERE id = @mid_menu_id)
BEGIN
  RAISERROR(N'父菜单不存在：考勤日常处理。请先执行 1002_migrate_full_刷卡资料查询.sql。', 16, 1);
  RETURN;
END

DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000035';
DECLARE @list_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000135';
DECLARE @form_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000235';

DECLARE @list_code NVARCHAR(200) = N'v_att_lst_Holiday';
DECLARE @save_entity NVARCHAR(200) = N'att_lst_Holiday';
DECLARE @form_code NVARCHAR(80) = N'form_att_leave_work';
DECLARE @title NVARCHAR(200) = N'请假作业';
DECLARE @path NVARCHAR(255) = N'/attendance/daily/leave-work';
DECLARE @component NVARCHAR(255) = N'/EntityList/entityListFromDesigner';

DECLARE @act_add_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000365';
DECLARE @act_edit_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000366';
DECLARE @act_del_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000367';
DECLARE @act_exp_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000368';
DECLARE @act_reload_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000369';

DECLARE @meta NVARCHAR(600);

DECLARE @form_schema_json NVARCHAR(MAX) = N'{
  "layout": {
    "cols": 2,
    "labelWidth": 108,
    "labelAlign": "right",
    "modalWidth": 920,
    "formItemGapPx": 5,
    "wrapperClass": "w-full min-w-0"
  },
  "saveEntityName": "att_lst_Holiday",
  "primaryKey": "FID",
  "schema": [
    { "component": "Input", "fieldName": "HD_ID", "label": "请假单号", "componentProps": { "placeholder": "可空则由后台生成", "allowClear": true } },
    { "component": "AutoComplete", "fieldName": "HC_ID", "label": "假别代号", "componentProps": { "placeholder": "搜索假别", "dataSourceType": "query", "tableName": "v_att_lst_HolidayCategory", "queryFields": "HC_ID,HC_Name", "labelField": "HC_Name", "valueField": "HC_ID", "searchField": "HC_ID,HC_Name", "pageSize": 20, "dropdownMatchSelectWidth": false, "responseMap": { "HC_Name": "HC_Name" }, "displayColumnsText": "HC_ID,代号\nHC_Name,假别名称" } },
    { "component": "Input", "fieldName": "HC_Name", "label": "假别名称", "componentProps": { "readOnly": true, "placeholder": "选假别后带出" } },
    { "component": "AutoComplete", "fieldName": "EMP_ID", "label": "工号", "componentProps": { "placeholder": "输入工号、姓名或部门搜索", "dataSourceType": "query", "tableName": "v_t_base_employee", "queryFields": "code,name,long_name,longdeptname", "labelField": "name", "valueField": "code", "searchField": "code,name,longdeptname", "pageSize": 15, "dropdownMatchSelectWidth": false, "responseMap": { "name": "name", "long_name": "long_name", "longdeptname": "long_name" }, "displayColumnsText": "code,工号\nname,姓名\nlongdeptname,部门" } },
    { "component": "Input", "fieldName": "name", "label": "姓名", "componentProps": { "readOnly": true } },
    { "component": "Input", "fieldName": "long_name", "label": "部门", "componentProps": { "readOnly": true } },
    { "component": "DatePicker", "fieldName": "HD_StartDate", "label": "开始日期", "componentProps": { "format": "YYYY-MM-DD", "valueFormat": "YYYY-MM-DD", "allowClear": true } },
    { "component": "TimePicker", "fieldName": "HD_StartTime", "label": "开始时间", "componentProps": { "format": "HH:mm", "valueFormat": "HH:mm", "allowClear": true } },
    { "component": "DatePicker", "fieldName": "HD_EndDate", "label": "结束日期", "componentProps": { "format": "YYYY-MM-DD", "valueFormat": "YYYY-MM-DD", "allowClear": true } },
    { "component": "TimePicker", "fieldName": "HD_EndTime", "label": "结束时间", "componentProps": { "format": "HH:mm", "valueFormat": "HH:mm", "allowClear": true } },
    { "component": "InputNumber", "fieldName": "HD_Days", "label": "请假天数", "componentProps": { "min": 0, "step": 0.5, "style": { "width": "100%" } } },
    { "component": "DatePicker", "fieldName": "HD_WageDate", "label": "计薪日期", "componentProps": { "format": "YYYY-MM-DD", "valueFormat": "YYYY-MM-DD", "allowClear": true } },
    { "component": "Textarea", "fieldName": "HD_Reason", "label": "请假原因", "formItemClass": "md:col-span-2", "componentProps": { "rows": 3, "maxlength": 1000, "showCount": true, "allowClear": true } },
    { "component": "Textarea", "fieldName": "HD_Remark", "label": "备注", "formItemClass": "md:col-span-2", "componentProps": { "rows": 2, "maxlength": 500, "showCount": true, "allowClear": true } },
    { "component": "Input", "fieldName": "HD_WGID", "label": "流程/单号", "componentProps": { "allowClear": true } }
  ]
}';

DECLARE @schema_json NVARCHAR(MAX) = N'{
  "title": "请假作业",
  "tableName": "v_att_lst_Holiday",
  "primaryKey": "FID",
  "saveEntityName": "att_lst_Holiday",
  "deleteEntityName": "att_lst_Holiday",
  "toolbar": {
    "actions": [
      { "key": "add", "label": "新增", "type": "primary", "action": "add", "form_code": "form_att_leave_work" },
      { "key": "edit", "label": "编辑", "type": "default", "action": "edit", "form_code": "form_att_leave_work", "requiresSelection": true },
      { "key": "deleteSelected", "label": "删除", "action": "deleteSelected" },
      { "key": "export", "label": "导出", "action": "export" },
      { "key": "reload", "label": "刷新", "action": "reload", "type": "primary" }
    ]
  },
  "form": {
    "collapsed": false,
    "submitOnChange": true,
    "wrapperClass": "grid-cols-1 md:grid-cols-2 lg:grid-cols-2",
    "schema": [
      { "component": "Input", "fieldName": "EMP_ID", "label": "工号" },
      { "component": "Input", "fieldName": "name", "label": "姓名" },
      { "component": "Input", "fieldName": "HD_ID", "label": "请假单号" },
      { "component": "Input", "fieldName": "HC_Name", "label": "假别" },
      { "component": "DatePicker", "fieldName": "HD_StartDate", "label": "开始日期", "componentProps": { "format": "YYYY-MM-DD", "valueFormat": "YYYY-MM-DD", "allowClear": true } }
    ]
  },
  "grid": {
    "pagerConfig": { "enabled": true, "pageSize": 50 },
    "sortConfig": { "remote": true, "defaultSort": { "field": "HD_ID", "order": "asc" } },
    "columns": [
      { "type": "checkbox", "width": 50 },
      { "type": "seq", "width": 60 },
      { "field": "HD_ID", "title": "请假单号", "width": 160, "sortable": true, "cellRender": { "name": "CellFieldFallback", "props": { "fallbackField": "FID" } } },
      { "field": "EMP_ID", "title": "工号", "width": 90, "sortable": true },
      { "field": "name", "title": "姓名", "width": 100, "sortable": true },
      { "field": "long_name", "title": "部门", "minWidth": 140, "sortable": true },
      { "field": "duty_name", "title": "岗位", "width": 100, "sortable": true },
      { "field": "HC_Name", "title": "假别", "width": 120, "sortable": true },
      { "field": "HC_Unit", "title": "单位", "width": 70, "sortable": true },
      { "field": "HD_StartDate", "title": "开始日期", "width": 120, "sortable": true },
      { "field": "HD_StartTime", "title": "开始", "width": 90, "sortable": true },
      { "field": "HD_EndDate", "title": "结束日期", "width": 120, "sortable": true },
      { "field": "HD_EndTime", "title": "结束", "width": 90, "sortable": true },
      { "field": "HD_Days", "title": "天数", "width": 80, "sortable": true },
      { "field": "HD_Reason", "title": "原因", "minWidth": 140, "sortable": false },
      { "field": "HD_OperatorName", "title": "操作人", "width": 100, "sortable": true },
      { "field": "HD_MakeDate", "title": "录入时间", "width": 170, "sortable": true },
      { "field": "HD_CheckDate", "title": "审核时间", "width": 170, "sortable": true },
      { "field": "HD_WGID", "title": "流程号", "width": 100, "sortable": true }
    ]
  },
  "api": {
    "query": "__API_QUERY__",
    "delete": "__API_DELETE__",
    "export": "__API_EXPORT__"
  }
}';

DECLARE @api_query NVARCHAR(500) = NULL;
DECLARE @api_delete NVARCHAR(500) = NULL;
DECLARE @api_export NVARCHAR(500) = NULL;

SELECT TOP 1
  @api_query = JSON_VALUE(schema_json, '$.api.query'),
  @api_delete = JSON_VALUE(schema_json, '$.api.delete'),
  @api_export = JSON_VALUE(schema_json, '$.api.export')
FROM vben_entitylist_desinger
WHERE code = N'mig_att_holiday_category';

IF @api_query IS NULL OR LTRIM(RTRIM(@api_query)) = N''
  SET @api_query = N'http://127.0.0.1:5155/api/DynamicQueryBeta/queryforvben';
IF @api_delete IS NULL OR LTRIM(RTRIM(@api_delete)) = N''
  SET @api_delete = N'http://127.0.0.1:5155/api/DataBatchDelete/BatchDelete';
IF @api_export IS NULL
  SET @api_export = N'';

SET @schema_json = REPLACE(@schema_json, N'__API_QUERY__', REPLACE(@api_query, N'"', N'\"'));
SET @schema_json = REPLACE(@schema_json, N'__API_DELETE__', REPLACE(@api_delete, N'"', N'\"'));
SET @schema_json = REPLACE(@schema_json, N'__API_EXPORT__', REPLACE(@api_export, N'"', N'\"'));

IF OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@list_code), N'V') IS NULL
   AND OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@list_code), N'U') IS NULL
BEGIN
  RAISERROR(N'[1006] 当前库不存在列表对象 dbo.%s', 16, 1, @list_code);
  RETURN;
END

IF OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@save_entity), N'U') IS NULL
  PRINT N'[1006] 警告：dbo.' + @save_entity + N' 不存在，保存/删除可能失败。';

SET @meta = N'{"title":"请假作业","icon":"lucide:calendar-days","query":{"entityname":"'
  + REPLACE(@list_code, N'\', N'\\')
  + N'","menuid":"A1000001-0001-4001-8001-000000000035"}}';

DELETE FROM vben_t_sys_role_menu_actions
WHERE menu_id = @leaf_menu_id
  AND menu_action_id IN (@act_add_id, @act_edit_id, @act_del_id, @act_exp_id, @act_reload_id);

DELETE FROM vben_menu_actions
WHERE menu_id = @leaf_menu_id
  AND id IN (@act_add_id, @act_edit_id, @act_del_id, @act_exp_id, @act_reload_id);

DELETE FROM vben_t_sys_role_menus WHERE menus_id = @leaf_menu_id;
DELETE FROM vben_menus_new WHERE id = @leaf_menu_id;
DELETE FROM vben_entitylist_desinger WHERE id = @list_id OR code = @list_code;
DELETE FROM vben_form_desinger WHERE id = @form_id OR code = @form_code;

INSERT INTO vben_form_desinger (id, code, title, schema_json, list_code, created_at, updated_at)
VALUES (@form_id, @form_code, @title, @form_schema_json, @list_code, GETDATE(), GETDATE());

INSERT INTO vben_entitylist_desinger (id, code, title, table_name, schema_json, created_at, updated_at)
VALUES (@list_id, @list_code, @title, @list_code, @schema_json, GETDATE(), GETDATE());

INSERT INTO vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@leaf_menu_id, @title, @path, @component, @meta, @mid_menu_id, 1, N'menu', 27);

INSERT INTO vben_t_sys_role_menus (id, role_id, menus_id, add_time)
VALUES (NEWID(), @role_id, @leaf_menu_id, GETDATE());

INSERT INTO vben_menu_actions (id, menu_id, action_key, label, button_type, action, confirm_text, sort, status, form_code, requires_selection)
VALUES
  (@act_add_id, @leaf_menu_id, N'add', N'新增', N'primary', N'add', NULL, 10, 1, @form_code, 0),
  (@act_edit_id, @leaf_menu_id, N'edit', N'编辑', N'default', N'edit', NULL, 20, 1, @form_code, 1),
  (@act_del_id, @leaf_menu_id, N'deleteSelected', N'删除', N'default', N'deleteSelected', NULL, 30, 1, NULL, 0),
  (@act_exp_id, @leaf_menu_id, N'export', N'导出', N'default', N'export', NULL, 40, 1, NULL, 0),
  (@act_reload_id, @leaf_menu_id, N'reload', N'刷新', N'primary', N'reload', NULL, 50, 1, NULL, 0);

INSERT INTO vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status, add_time)
VALUES
  (NEWID(), @role_id, @act_add_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_edit_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_del_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_exp_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_reload_id, @leaf_menu_id, 1, GETDATE());

PRINT N'OK: [1006] 考勤日常处理 → 请假作业 已迁移；列表=' + @list_code + N'，保存表=' + @save_entity + N'。';
