/*
  一键迁移：法定假日设定（普通列表）

  老系统：
    - 菜单：法定假日设定
    - entity: v_att_lst_StatutoryHoliday
    - url: datagrid.aspx?entity=v_att_lst_StatutoryHoliday

  新系统：
    - 列表：/EntityList/entityListFromDesigner
    - schema: vben_entitylist_desinger(code = v_att_lst_StatutoryHoliday)
    - 表单：vben_form_desinger(code = form_statutory_holiday)，供新增/编辑弹窗
    - 菜单挂载：考勤管理 → 考勤基础资料 → 本菜单
    - 菜单按钮 + 系统管理员按钮权限（与 QueryTable 权限过滤一致）

  幂等：可重复执行（先删后插）
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

DECLARE @base_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000002';
DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000008';
DECLARE @list_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000108';
DECLARE @form_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000208';

DECLARE @list_code NVARCHAR(200) = N'v_att_lst_StatutoryHoliday';
DECLARE @form_code NVARCHAR(50) = N'form_statutory_holiday';
DECLARE @title NVARCHAR(200) = N'法定假日设定';
DECLARE @path NVARCHAR(255) = N'/attendance/base/statutory-holiday';
DECLARE @component NVARCHAR(255) = N'/EntityList/entityListFromDesigner';

DECLARE @act_add_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000311';
DECLARE @act_edit_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000312';
DECLARE @act_del_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000313';
DECLARE @act_exp_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000314';
DECLARE @act_reload_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000315';

DECLARE @meta NVARCHAR(500) =
  N'{"title":"法定假日设定","icon":"lucide:calendar-range","query":{"entityname":"v_att_lst_StatutoryHoliday","menuid":"A1000001-0001-4001-8001-000000000008"}}';

DECLARE @form_schema_json NVARCHAR(MAX) = N'{
  "layout": { "cols": 2, "labelWidth": 110, "labelAlign": "right" },
  "saveEntityName": "att_lst_StatutoryHoliday",
  "primaryKey": "FID",
  "schema": [
    { "component": "Input", "fieldName": "Holidaydate", "label": "假日日期" },
    { "component": "Input", "fieldName": "explain", "label": "说明" },
    { "component": "Switch", "fieldName": "IsHoliday", "label": "是否假日" }
  ]
}';

DECLARE @schema_json NVARCHAR(MAX) = N'{
  "title": "法定假日设定",
  "tableName": "v_att_lst_StatutoryHoliday",
  "primaryKey": "FID",
  "saveEntityName": "att_lst_StatutoryHoliday",
  "deleteEntityName": "att_lst_StatutoryHoliday",
  "toolbar": {
    "actions": [
      { "key": "add", "label": "新增", "type": "primary", "action": "add", "form_code": "form_statutory_holiday" },
      { "key": "edit", "label": "编辑", "type": "default", "action": "edit", "form_code": "form_statutory_holiday", "requiresSelection": true },
      { "key": "deleteSelected", "label": "删除", "action": "deleteSelected" },
      { "key": "export", "label": "导出", "action": "export" },
      { "key": "reload", "label": "刷新", "action": "reload", "type": "primary" }
    ]
  },
  "form": {
    "collapsed": false,
    "submitOnChange": true,
    "schema": [
      { "component": "Input", "fieldName": "Holidaydate", "label": "假日日期" },
      { "component": "Input", "fieldName": "explain", "label": "说明" },
      { "component": "Switch", "fieldName": "IsHoliday", "label": "是否假日" }
    ]
  },
  "grid": {
    "pagerConfig": { "enabled": true, "pageSize": 50 },
    "sortConfig": { "remote": true, "defaultSort": { "field": "Holidaydate", "order": "desc" } },
    "columns": [
      { "type": "checkbox", "width": 50 },
      { "type": "seq", "width": 60 },
      { "field": "HolidaydateYear", "title": "年度", "width": 90, "sortable": true },
      { "field": "Holidaydate", "title": "假日日期", "width": 120, "sortable": true },
      { "field": "explain", "title": "说明", "minWidth": 120, "sortable": true },
      { "field": "IsHolidayName", "title": "是否假日", "width": 100, "sortable": true },
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
IF @api_delete IS NULL
  SET @api_delete = N'';
IF @api_export IS NULL
  SET @api_export = N'';

SET @schema_json = REPLACE(@schema_json, N'__API_QUERY__', REPLACE(@api_query, N'"', N'\"'));
SET @schema_json = REPLACE(@schema_json, N'__API_DELETE__', REPLACE(@api_delete, N'"', N'\"'));
SET @schema_json = REPLACE(@schema_json, N'__API_EXPORT__', REPLACE(@api_export, N'"', N'\"'));

-- ==================== 幂等删除 ====================
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
VALUES (@list_id, @list_code, @title, N'v_att_lst_StatutoryHoliday', @schema_json, GETDATE(), GETDATE());

-- ==================== 菜单 ====================
INSERT INTO vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@leaf_menu_id, @title, @path, @component, @meta, @base_menu_id, 1, N'menu', 63);

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

PRINT N'OK: 法定假日设定 已迁移（表单+列表+菜单+按钮权限+授权）。';
