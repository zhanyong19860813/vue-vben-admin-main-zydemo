/*
  [1001] 一键迁移：考勤管理 → 考勤数据权限 → 人员班次权限（列表设计器）

  老系统：
    - t_sys_function：人员班次权限（parent=考勤数据权限）
    - entity: v_att_lst_ShiftsSetting
    - order: EMP_ID, BCName

  新系统：
    - 与「数据权限配置」同父级：考勤数据权限（mid A1000001-0001-4001-8001-000000000020）
    - 列表：/EntityList/entityListFromDesigner
    - 查询视图：v_att_lst_ShiftsSetting；保存/删除表：att_lst_ShiftsSetting（PK: FID）

  前置：须已存在父菜单「考勤数据权限」（见 migrate_full_数据权限配置.sql）

  幂等：可重复执行（先删后插，仅本菜单与 schema）
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

DECLARE @mid_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000020';
IF NOT EXISTS (SELECT 1 FROM vben_menus_new WHERE id = @mid_menu_id)
BEGIN
  RAISERROR(N'父菜单不存在：考勤数据权限 A1000001-0001-4001-8001-000000000020。请先执行 migrate_full_数据权限配置.sql。', 16, 1);
  RETURN;
END

DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000022';
DECLARE @list_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000122';
DECLARE @form_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000222';

DECLARE @list_code NVARCHAR(200) = N'v_att_lst_ShiftsSetting';
DECLARE @form_code NVARCHAR(50) = N'form_att_shifts_setting';
DECLARE @title NVARCHAR(200) = N'人员班次权限';
DECLARE @path NVARCHAR(255) = N'/attendance/data-permission/shift-user-setting';
DECLARE @component NVARCHAR(255) = N'/EntityList/entityListFromDesigner';

DECLARE @act_add_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000331';
DECLARE @act_edit_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000332';
DECLARE @act_del_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000333';
DECLARE @act_exp_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000334';
DECLARE @act_reload_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000335';

DECLARE @meta_leaf NVARCHAR(500) =
  N'{"title":"人员班次权限","icon":"lucide:users","query":{"entityname":"v_att_lst_ShiftsSetting","menuid":"A1000001-0001-4001-8001-000000000022"}}';

DECLARE @form_schema_json NVARCHAR(MAX) = N'{
  "layout": { "cols": 2, "labelWidth": 120, "labelAlign": "right" },
  "saveEntityName": "att_lst_ShiftsSetting",
  "primaryKey": "FID",
  "schema": [
    { "component": "Input", "fieldName": "EMP_ID", "label": "员工工号" },
    { "component": "Input", "fieldName": "BCID", "label": "班次方案ID(Guid)" },
    { "component": "Input", "fieldName": "isdisabled", "label": "是否停用" }
  ]
}';

DECLARE @schema_json NVARCHAR(MAX) = N'{
  "title": "人员班次权限",
  "tableName": "v_att_lst_ShiftsSetting",
  "primaryKey": "FID",
  "saveEntityName": "att_lst_ShiftsSetting",
  "deleteEntityName": "att_lst_ShiftsSetting",
  "toolbar": {
    "actions": [
      { "key": "add", "label": "新增", "type": "primary", "action": "add", "form_code": "form_att_shifts_setting" },
      { "key": "edit", "label": "编辑", "type": "default", "action": "edit", "form_code": "form_att_shifts_setting", "requiresSelection": true },
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
      { "component": "Input", "fieldName": "EMP_ID", "label": "员工工号" },
      { "component": "Input", "fieldName": "name", "label": "姓名" },
      { "component": "Input", "fieldName": "code_name", "label": "班次方案" },
      { "component": "Input", "fieldName": "BCID", "label": "班次方案ID" }
    ]
  },
  "grid": {
    "pagerConfig": { "enabled": true, "pageSize": 50 },
    "sortConfig": { "remote": true, "defaultSort": { "field": "EMP_ID", "order": "asc" } },
    "columns": [
      { "type": "checkbox", "width": 50 },
      { "type": "seq", "width": 60 },
      { "field": "EMP_ID", "title": "工号", "width": 96, "sortable": true },
      { "field": "username", "title": "登录账号", "width": 100, "sortable": true },
      { "field": "name", "title": "姓名", "width": 100, "sortable": true },
      { "field": "code_name", "title": "班次方案", "minWidth": 160, "sortable": true },
      { "field": "begin_time", "title": "开始", "width": 80, "sortable": true },
      { "field": "end_time", "title": "结束", "width": 80, "sortable": true },
      { "field": "BCName", "title": "BCName", "width": 120, "sortable": true },
      { "field": "OpenrationName", "title": "操作人", "width": 100, "sortable": true },
      { "field": "OpenrationTime", "title": "操作时间", "width": 170, "sortable": true },
      { "field": "isdisabled", "title": "停用", "width": 72, "sortable": true }
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
IF @api_delete IS NULL
  SET @api_delete = N'';
IF @api_export IS NULL
  SET @api_export = N'';

SET @schema_json = REPLACE(@schema_json, N'__API_QUERY__', REPLACE(@api_query, N'"', N'\"'));
SET @schema_json = REPLACE(@schema_json, N'__API_DELETE__', REPLACE(@api_delete, N'"', N'\"'));
SET @schema_json = REPLACE(@schema_json, N'__API_EXPORT__', REPLACE(@api_export, N'"', N'\"'));

-- ==================== 幂等删除（仅本叶子） ====================
DELETE FROM vben_t_sys_role_menu_actions
WHERE menu_id = @leaf_menu_id
  AND menu_action_id IN (@act_add_id, @act_edit_id, @act_del_id, @act_exp_id, @act_reload_id);

DELETE FROM vben_menu_actions
WHERE menu_id = @leaf_menu_id
  AND id IN (@act_add_id, @act_edit_id, @act_del_id, @act_exp_id, @act_reload_id);

DELETE FROM vben_t_sys_role_menus WHERE role_id = @role_id AND menus_id = @leaf_menu_id;
DELETE FROM vben_menus_new WHERE id = @leaf_menu_id;
DELETE FROM vben_entitylist_desinger WHERE id = @list_id OR code = @list_code;
DELETE FROM vben_form_desinger WHERE id = @form_id OR code = @form_code;

-- ==================== 表单设计器 ====================
INSERT INTO vben_form_desinger (id, code, title, schema_json, list_code, created_at, updated_at)
VALUES (@form_id, @form_code, @title, @form_schema_json, @list_code, GETDATE(), GETDATE());

-- ==================== 列表 schema ====================
INSERT INTO vben_entitylist_desinger (id, code, title, table_name, schema_json, created_at, updated_at)
VALUES (@list_id, @list_code, @title, N'v_att_lst_ShiftsSetting', @schema_json, GETDATE(), GETDATE());

-- ==================== 菜单叶子（排在数据权限配置前，与老系统 sort 一致） ====================
INSERT INTO vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@leaf_menu_id, @title, @path, @component, @meta_leaf, @mid_menu_id, 1, N'menu', 8);

INSERT INTO vben_t_sys_role_menus (id, role_id, menus_id, add_time)
VALUES (NEWID(), @role_id, @leaf_menu_id, GETDATE());

-- ==================== 菜单按钮 + 系统管理员权限 ====================
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

PRINT N'OK: [1001] 考勤数据权限 → 人员班次权限 已迁移（v_att_lst_ShiftsSetting + 菜单 + 按钮权限）。';
