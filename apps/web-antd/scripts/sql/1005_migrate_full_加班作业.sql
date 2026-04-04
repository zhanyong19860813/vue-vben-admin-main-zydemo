/*
  [1005] 一键迁移：考勤日常处理 → 加班作业（列表 + 表单 CRUD + 审核/取消审核）

  老系统：t_sys_function.name=加班作业，entity=v_att_lst_OverTime，父菜单=考勤日常处理
  物理表：dbo.att_lst_OverTime（视图 v_att_lst_OverTime 的 FROM 基表，主键 FID）

  新系统：component=/EntityList/entityListFromDesigner，path=/attendance/daily/overtime-work
  前置：父菜单 考勤日常处理 已存在（1002_migrate_full_刷卡资料查询.sql）

  幂等：仅删除本叶子菜单、本列表/表单、本菜单按钮及角色关联后重插。
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

DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000034';
DECLARE @list_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000134';
DECLARE @form_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000234';

DECLARE @list_code NVARCHAR(200) = N'v_att_lst_OverTime';
DECLARE @save_entity NVARCHAR(200) = N'att_lst_OverTime';
DECLARE @form_code NVARCHAR(80) = N'form_att_overtime_work';
DECLARE @title NVARCHAR(200) = N'加班作业';
DECLARE @path NVARCHAR(255) = N'/attendance/daily/overtime-work';
DECLARE @component NVARCHAR(255) = N'/EntityList/entityListFromDesigner';

DECLARE @act_add_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000358';
DECLARE @act_edit_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000359';
DECLARE @act_del_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000360';
DECLARE @act_audit_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000361';
DECLARE @act_cancel_audit_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000362';
DECLARE @act_exp_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000363';
DECLARE @act_reload_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000364';

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
  "saveEntityName": "att_lst_OverTime",
  "primaryKey": "FID",
  "schema": [
    { "component": "AutoComplete", "fieldName": "EMP_ID", "label": "工号", "componentProps": { "placeholder": "输入工号、姓名或部门搜索", "dataSourceType": "query", "tableName": "v_t_base_employee", "queryFields": "code,name,long_name,longdeptname", "labelField": "name", "valueField": "code", "searchField": "code,name,longdeptname", "pageSize": 15, "dropdownMatchSelectWidth": false, "responseMap": { "name": "name", "long_name": "long_name", "longdeptname": "long_name" }, "displayColumnsText": "code,工号\nname,姓名\nlongdeptname,部门" } },
    { "component": "Input", "fieldName": "name", "label": "姓名", "componentProps": { "placeholder": "选工号后自动带出", "readOnly": true } },
    { "component": "Input", "fieldName": "long_name", "label": "部门", "componentProps": { "placeholder": "选工号后自动带出", "readOnly": true } },
    { "component": "Input", "fieldName": "fType", "label": "加班类型", "componentProps": { "placeholder": "如 节日加班", "allowClear": true } },
    { "component": "DatePicker", "fieldName": "fDate", "label": "加班日期", "componentProps": { "placeholder": "选择日期", "format": "YYYY-MM-DD", "valueFormat": "YYYY-MM-DD", "allowClear": true } },
    { "component": "TimePicker", "fieldName": "fStartTime", "label": "开始时间", "componentProps": { "placeholder": "选择时间", "format": "HH:mm", "valueFormat": "HH:mm", "allowClear": true } },
    { "component": "TimePicker", "fieldName": "fEndTime", "label": "结束时间", "componentProps": { "placeholder": "选择时间", "format": "HH:mm", "valueFormat": "HH:mm", "allowClear": true } },
    { "component": "Switch", "fieldName": "IsSlotCard1", "label": "上班刷卡" },
    { "component": "Switch", "fieldName": "IsSlotCard2", "label": "下班刷卡" },
    { "component": "InputNumber", "fieldName": "overtime", "label": "加班时数", "componentProps": { "min": 0, "step": 0.5, "style": { "width": "100%" } } },
    { "component": "InputNumber", "fieldName": "days", "label": "天数", "componentProps": { "min": 0, "precision": 0, "style": { "width": "100%" } } },
    { "component": "Textarea", "fieldName": "fReason", "label": "加班原因", "formItemClass": "md:col-span-2", "componentProps": { "placeholder": "请输入", "rows": 3, "maxlength": 500, "showCount": true, "allowClear": true } },
    { "component": "Textarea", "fieldName": "Remark", "label": "备注", "formItemClass": "md:col-span-2", "componentProps": { "placeholder": "请输入", "rows": 2, "maxlength": 500, "showCount": true, "allowClear": true } },
    { "component": "Input", "fieldName": "ApproveStatus", "label": "审核状态", "componentProps": { "disabled": true } }
  ]
}';

DECLARE @schema_json NVARCHAR(MAX) = N'{
  "title": "加班作业",
  "tableName": "v_att_lst_OverTime",
  "primaryKey": "FID",
  "saveEntityName": "att_lst_OverTime",
  "deleteEntityName": "att_lst_OverTime",
  "actionModule": "/src/views/EntityList/overtimeWorkActions.ts",
  "toolbar": {
    "actions": [
      { "key": "add", "label": "新增", "type": "primary", "action": "add", "form_code": "form_att_overtime_work" },
      { "key": "edit", "label": "编辑", "type": "default", "action": "edit", "form_code": "form_att_overtime_work", "requiresSelection": true },
      { "key": "deleteSelected", "label": "删除", "action": "deleteSelected" },
      { "key": "auditOvertimeRows", "label": "审核", "type": "default", "action": "auditOvertimeRows" },
      { "key": "cancelAuditOvertimeRows", "label": "取消审核", "type": "default", "action": "cancelAuditOvertimeRows" },
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
      { "component": "DatePicker", "fieldName": "fDate", "label": "加班日期", "componentProps": { "format": "YYYY-MM-DD", "valueFormat": "YYYY-MM-DD", "allowClear": true } },
      { "component": "Input", "fieldName": "fType", "label": "加班类型" },
      { "component": "Input", "fieldName": "ApproveStatus", "label": "审核状态" }
    ]
  },
  "grid": {
    "pagerConfig": { "enabled": true, "pageSize": 50 },
    "sortConfig": { "remote": true, "defaultSort": { "field": "fDate", "order": "asc" } },
    "columns": [
      { "type": "checkbox", "width": 50 },
      { "type": "seq", "width": 60 },
      { "field": "EMP_ID", "title": "工号", "width": 96, "sortable": true },
      { "field": "name", "title": "姓名", "width": 100, "sortable": true },
      { "field": "long_name", "title": "部门", "minWidth": 140, "sortable": true },
      { "field": "dutyName", "title": "岗位", "width": 100, "sortable": true },
      { "field": "fType", "title": "加班类型", "width": 120, "sortable": true },
      { "field": "fDate", "title": "加班日期", "width": 120, "sortable": true },
      { "field": "fStartTime", "title": "开始", "width": 90, "sortable": true },
      { "field": "fEndTime", "title": "结束", "width": 90, "sortable": true },
      { "field": "overtime", "title": "时数", "width": 80, "sortable": true },
      { "field": "ApproveStatus", "title": "审核", "width": 90, "sortable": true },
      { "field": "fReason", "title": "原因", "minWidth": 140, "sortable": false },
      { "field": "OperatorName", "title": "操作人", "width": 100, "sortable": true },
      { "field": "OperationTime", "title": "操作时间", "width": 170, "sortable": true }
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
  RAISERROR(N'[1005] 当前库不存在列表对象 dbo.%s', 16, 1, @list_code);
  RETURN;
END

IF OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@save_entity), N'U') IS NULL
  PRINT N'[1005] 警告：dbo.' + @save_entity + N' 不存在，保存/删除可能失败。';

SET @meta = N'{"title":"加班作业","icon":"lucide:clock","query":{"entityname":"'
  + REPLACE(@list_code, N'\', N'\\')
  + N'","menuid":"A1000001-0001-4001-8001-000000000034"}}';

-- ==================== 幂等删除 ====================
DELETE FROM vben_t_sys_role_menu_actions
WHERE menu_id = @leaf_menu_id
  AND menu_action_id IN (@act_add_id, @act_edit_id, @act_del_id, @act_audit_id, @act_cancel_audit_id, @act_exp_id, @act_reload_id);

DELETE FROM vben_menu_actions
WHERE menu_id = @leaf_menu_id
  AND id IN (@act_add_id, @act_edit_id, @act_del_id, @act_audit_id, @act_cancel_audit_id, @act_exp_id, @act_reload_id);

DELETE FROM vben_t_sys_role_menus WHERE menus_id = @leaf_menu_id;
DELETE FROM vben_menus_new WHERE id = @leaf_menu_id;
DELETE FROM vben_entitylist_desinger WHERE id = @list_id OR code = @list_code;
DELETE FROM vben_form_desinger WHERE id = @form_id OR code = @form_code;

INSERT INTO vben_form_desinger (id, code, title, schema_json, list_code, created_at, updated_at)
VALUES (@form_id, @form_code, @title, @form_schema_json, @list_code, GETDATE(), GETDATE());

INSERT INTO vben_entitylist_desinger (id, code, title, table_name, schema_json, created_at, updated_at)
VALUES (@list_id, @list_code, @title, @list_code, @schema_json, GETDATE(), GETDATE());

INSERT INTO vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@leaf_menu_id, @title, @path, @component, @meta, @mid_menu_id, 1, N'menu', 25);

INSERT INTO vben_t_sys_role_menus (id, role_id, menus_id, add_time)
VALUES (NEWID(), @role_id, @leaf_menu_id, GETDATE());

INSERT INTO vben_menu_actions (id, menu_id, action_key, label, button_type, action, confirm_text, sort, status, form_code, requires_selection)
VALUES
  (@act_add_id, @leaf_menu_id, N'add', N'新增', N'primary', N'add', NULL, 10, 1, @form_code, 0),
  (@act_edit_id, @leaf_menu_id, N'edit', N'编辑', N'default', N'edit', NULL, 20, 1, @form_code, 1),
  (@act_del_id, @leaf_menu_id, N'deleteSelected', N'删除', N'default', N'deleteSelected', NULL, 30, 1, NULL, 0),
  (@act_audit_id, @leaf_menu_id, N'auditOvertimeRows', N'审核', N'default', N'auditOvertimeRows', NULL, 32, 1, NULL, 0),
  (@act_cancel_audit_id, @leaf_menu_id, N'cancelAuditOvertimeRows', N'取消审核', N'default', N'cancelAuditOvertimeRows', NULL, 34, 1, NULL, 0),
  (@act_exp_id, @leaf_menu_id, N'export', N'导出', N'default', N'export', NULL, 40, 1, NULL, 0),
  (@act_reload_id, @leaf_menu_id, N'reload', N'刷新', N'primary', N'reload', NULL, 50, 1, NULL, 0);

INSERT INTO vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status, add_time)
VALUES
  (NEWID(), @role_id, @act_add_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_edit_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_del_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_audit_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_cancel_audit_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_exp_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_reload_id, @leaf_menu_id, 1, GETDATE());

PRINT N'OK: [1005] 考勤日常处理 → 加班作业 已迁移；列表=' + @list_code + N'，保存表=' + @save_entity + N'。';
