/*
  [1004] 一键迁移：考勤日常处理 → 签卡作业（列表设计器 + 表单 + CRUD）

  【重要】列表对象名从哪来？
    脚本不会连接你的库自动探测，默认值只是「常见老项目」写法；必须与老系统菜单里 datagrid.aspx?entity= 一致。
    例如你方签卡菜单为 v_att_lst_RegRecord，则 @list_code 填该名；若填错库中不存在的名，会报 208（与白名单无关）。

  【执行前必做】在「考勤业务库」中执行：
        SELECT name FROM sys.views WHERE name LIKE N'%Reg%' OR name LIKE N'%Sign%' OR name LIKE N'%Card%';
    或打开老系统签卡菜单，看浏览器/源码里 datagrid.aspx?entity= 后面的名字，与下列变量保持一致：

    - @list_code      = 列表 queryforvben 的 TableName（多为 v_ 开头的视图名）
    - @save_entity    = DataSave/BatchDelete 的物理表名（v_att_lst_RegRecord 对应 dbo.att_lst_Cardrecord，见视图定义）

  改完 @list_code / @save_entity 后再执行本脚本；若列与下列 schema 不一致，再在
  vben_entitylist_desinger / vben_form_desinger 里调 schema_json。

  新系统：
    - 列表：/EntityList/entityListFromDesigner
    - path：/attendance/daily/card-signing-work

  前置：须已存在父菜单「考勤日常处理」（见 1002_migrate_full_刷卡资料查询.sql）

  幂等：仅删除本菜单叶子、本列表/表单设计器、本菜单按钮及角色关联。
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

DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000033';
DECLARE @list_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000133';
DECLARE @form_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000233';

/* 与老系统签卡菜单 entity 一致（你方为 v_att_lst_RegRecord）；保存须用视图基表 att_lst_Cardrecord，勿用 att_lst_RegRecord */
DECLARE @list_code NVARCHAR(200) = N'v_att_lst_RegRecord';
DECLARE @save_entity NVARCHAR(200) = N'att_lst_Cardrecord';

DECLARE @form_code NVARCHAR(80) = N'form_att_sign_card';
DECLARE @title NVARCHAR(200) = N'签卡作业';
DECLARE @path NVARCHAR(255) = N'/attendance/daily/card-signing-work';
DECLARE @component NVARCHAR(255) = N'/EntityList/entityListFromDesigner';

DECLARE @act_add_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000351';
DECLARE @act_edit_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000352';
DECLARE @act_del_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000353';
DECLARE @act_exp_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000354';
DECLARE @act_reload_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000355';
DECLARE @act_audit_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000356';
DECLARE @act_cancel_audit_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000357';

DECLARE @meta NVARCHAR(600);

DECLARE @form_schema_json NVARCHAR(MAX) = N'{
  "layout": { "cols": 2, "labelWidth": 110, "labelAlign": "right" },
  "saveEntityName": "att_lst_Cardrecord",
  "primaryKey": "FID",
  "schema": [
    { "component": "AutoComplete", "fieldName": "EMP_ID", "label": "工号", "componentProps": { "placeholder": "输入工号、姓名或部门搜索", "dataSourceType": "query", "tableName": "v_t_base_employee", "queryFields": "code,name,long_name,longdeptname", "labelField": "name", "valueField": "code", "searchField": "code,name,longdeptname", "pageSize": 15, "dropdownMatchSelectWidth": false, "responseMap": { "name": "name", "long_name": "long_name", "longdeptname": "long_name" }, "displayColumnsText": "code,工号\nname,姓名\nlongdeptname,部门" } },
    { "component": "Input", "fieldName": "name", "label": "姓名", "componentProps": { "placeholder": "选工号后自动带出" } },
    { "component": "Input", "fieldName": "long_name", "label": "部门", "componentProps": { "placeholder": "选工号后自动带出" } },
    { "component": "DatePicker", "fieldName": "SlotCardDate", "label": "签卡日期", "componentProps": { "placeholder": "选择日期", "format": "YYYY-MM-DD", "valueFormat": "YYYY-MM-DD", "allowClear": true } },
    { "component": "TimePicker", "fieldName": "SlotCardTime", "label": "签卡时间", "componentProps": { "placeholder": "选择时间", "format": "HH:mm", "valueFormat": "HH:mm", "allowClear": true } },
    { "component": "Select", "fieldName": "AppState", "label": "状态", "componentProps": { "placeholder": "请选择", "allowClear": true, "options": [ { "label": "审批中", "value": "审批中" }, { "label": "已审核", "value": "已审核" }, { "label": "未审核", "value": "未审核" } ] } },
    { "component": "Textarea", "fieldName": "CardReason", "label": "签卡原因", "formItemClass": "md:col-span-2", "componentProps": { "placeholder": "请输入签卡原因", "rows": 3, "maxlength": 200, "showCount": true, "allowClear": true } }
  ]
}';

DECLARE @schema_json NVARCHAR(MAX) = N'{
  "title": "签卡作业",
  "tableName": "v_att_lst_RegRecord",
  "primaryKey": "FID",
  "saveEntityName": "att_lst_Cardrecord",
  "deleteEntityName": "att_lst_Cardrecord",
  "actionModule": "/src/views/EntityList/signCardRecordActions.ts",
  "toolbar": {
    "actions": [
      { "key": "add", "label": "新增", "type": "primary", "action": "add", "form_code": "form_att_sign_card" },
      { "key": "edit", "label": "编辑", "type": "default", "action": "edit", "form_code": "form_att_sign_card", "requiresSelection": true },
      { "key": "deleteSelected", "label": "删除", "action": "deleteSelected" },
      { "key": "auditSignCards", "label": "审核", "type": "default", "action": "auditSignCards" },
      { "key": "cancelAuditSignCards", "label": "取消审核", "type": "default", "action": "cancelAuditSignCards" },
      { "key": "export", "label": "导出", "action": "export" },
      { "key": "reload", "label": "刷新", "action": "reload", "type": "primary" }
    ]
  },
  "form": {
    "collapsed": false,
    "submitOnChange": true,
    "schema": [
      { "component": "Input", "fieldName": "EMP_ID", "label": "工号" },
      { "component": "Input", "fieldName": "name", "label": "姓名" },
      { "component": "Input", "fieldName": "long_name", "label": "部门" },
      { "component": "Input", "fieldName": "SlotCardDate", "label": "签卡日期" },
      { "component": "Input", "fieldName": "SlotCardTime", "label": "签卡时间" },
      { "component": "Input", "fieldName": "AppState", "label": "状态" },
      { "component": "Input", "fieldName": "CardReason", "label": "签卡原因" }
    ]
  },
  "grid": {
    "pagerConfig": { "enabled": true, "pageSize": 50 },
    "sortConfig": { "remote": true, "defaultSort": { "field": "FID", "order": "desc" } },
    "columns": [
      { "type": "checkbox", "width": 50 },
      { "type": "seq", "width": 60 },
      { "field": "EMP_ID", "title": "工号", "width": 96, "sortable": true },
      { "field": "name", "title": "姓名", "width": 100, "sortable": true },
      { "field": "long_name", "title": "部门", "minWidth": 160, "sortable": true },
      { "field": "dutyName", "title": "岗位", "width": 110, "sortable": true },
      { "field": "SlotCardDate", "title": "签卡日期", "width": 120, "sortable": true },
      { "field": "SlotCardTime", "title": "签卡时间", "width": 110, "sortable": true },
      { "field": "AppState", "title": "状态", "width": 90, "sortable": true },
      { "field": "CardReason", "title": "签卡原因", "minWidth": 140, "sortable": false },
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

-- 模板默认为 RegRecord + Cardrecord；若你改 @list_code / @save_entity，此处同步替换进 JSON
SET @schema_json = REPLACE(@schema_json, N'v_att_lst_RegRecord', @list_code);
SET @schema_json = REPLACE(@schema_json, N'att_lst_Cardrecord', @save_entity);
SET @form_schema_json = REPLACE(@form_schema_json, N'att_lst_Cardrecord', @save_entity);

SET @meta = N'{"title":"签卡作业","icon":"lucide:pen-line","query":{"entityname":"'
  + REPLACE(@list_code, N'\', N'\\')
  + N'","menuid":"A1000001-0001-4001-8001-000000000033"}}';

-- 业务库须存在列表对象（视图或表），否则后续页面查询必 208
IF OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@list_code), N'V') IS NULL
   AND OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@list_code), N'U') IS NULL
BEGIN
  DECLARE @msg208 NVARCHAR(500) = N'[1004] 当前库不存在 dbo.' + @list_code
    + N'。请改为老系统签卡页 entity= 对应的对象名（修改脚本顶部 @list_code）后再执行。';
  RAISERROR(@msg208, 16, 1);
  RETURN;
END

IF OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@save_entity), N'U') IS NULL
  PRINT N'[1004] 警告：dbo.' + @save_entity + N' 表不存在，新增/删除可能失败；请核对 @save_entity。';

-- ==================== 幂等删除（仅本叶子） ====================
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

-- ==================== 表单设计器 ====================
INSERT INTO vben_form_desinger (id, code, title, schema_json, list_code, created_at, updated_at)
VALUES (@form_id, @form_code, @title, @form_schema_json, @list_code, GETDATE(), GETDATE());

-- ==================== 列表 schema ====================
INSERT INTO vben_entitylist_desinger (id, code, title, table_name, schema_json, created_at, updated_at)
VALUES (@list_id, @list_code, @title, @list_code, @schema_json, GETDATE(), GETDATE());

-- ==================== 菜单叶子 ====================
INSERT INTO vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@leaf_menu_id, @title, @path, @component, @meta, @mid_menu_id, 1, N'menu', 15);

INSERT INTO vben_t_sys_role_menus (id, role_id, menus_id, add_time)
VALUES (NEWID(), @role_id, @leaf_menu_id, GETDATE());

-- ==================== 菜单按钮 + 系统管理员 ====================
INSERT INTO vben_menu_actions (id, menu_id, action_key, label, button_type, action, confirm_text, sort, status, form_code, requires_selection)
VALUES
  (@act_add_id, @leaf_menu_id, N'add', N'新增', N'primary', N'add', NULL, 10, 1, @form_code, 0),
  (@act_edit_id, @leaf_menu_id, N'edit', N'编辑', N'default', N'edit', NULL, 20, 1, @form_code, 1),
  (@act_del_id, @leaf_menu_id, N'deleteSelected', N'删除', N'default', N'deleteSelected', NULL, 30, 1, NULL, 0),
  (@act_audit_id, @leaf_menu_id, N'auditSignCards', N'审核', N'default', N'auditSignCards', NULL, 32, 1, NULL, 0),
  (@act_cancel_audit_id, @leaf_menu_id, N'cancelAuditSignCards', N'取消审核', N'default', N'cancelAuditSignCards', NULL, 34, 1, NULL, 0),
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

PRINT N'OK: [1004] 考勤日常处理 → 签卡作业 已迁移；列表对象=' + @list_code + N'，保存表=' + @save_entity + N'。';
