/*
  一键迁移：考勤管理 → 考勤数据权限 → 数据权限配置（列表设计器）

  数据：
    - 列表查询视图：v_att_lst_Power
    - 新增/编辑/删除实体表：att_lst_Power（PK: FID）

  新系统：
    - 列表：/EntityList/entityListFromDesigner
    - schema: vben_entitylist_desinger(code = v_att_lst_Power)
    - 表单：vben_form_desinger(code = form_att_data_power)
    - 菜单：考勤管理(LAYOUT) → 考勤数据权限(分组 component='') → 本菜单
    - 菜单按钮 + 系统管理员按钮权限

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

DECLARE @root_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000001'; -- 考勤管理（须已存在）
IF NOT EXISTS (SELECT 1 FROM vben_menus_new WHERE id = @root_menu_id)
BEGIN
  RAISERROR(N'根菜单不存在：A1000001-0001-4001-8001-000000000001（考勤管理）。请先初始化考勤模块菜单。', 16, 1);
  RETURN;
END
DECLARE @mid_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000020'; -- 考勤数据权限（新建分组）
DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000021'; -- 数据权限配置
DECLARE @list_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000121';
DECLARE @form_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000221';

DECLARE @list_code NVARCHAR(200) = N'v_att_lst_Power';
DECLARE @form_code NVARCHAR(50) = N'form_att_data_power';
DECLARE @title NVARCHAR(200) = N'数据权限配置';
DECLARE @mid_title NVARCHAR(200) = N'考勤数据权限';
DECLARE @path NVARCHAR(255) = N'/attendance/data-permission/config';
DECLARE @mid_path NVARCHAR(255) = N'/attendance/data-permission';
DECLARE @component NVARCHAR(255) = N'/EntityList/entityListFromDesigner';

DECLARE @act_add_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000321';
DECLARE @act_edit_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000322';
DECLARE @act_del_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000323';
DECLARE @act_exp_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000324';
DECLARE @act_reload_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000325';
DECLARE @act_pick_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000326';

DECLARE @meta_mid NVARCHAR(500) =
  N'{"title":"考勤数据权限","icon":"lucide:shield","query":{"menuid":"A1000001-0001-4001-8001-000000000020"}}';

DECLARE @meta_leaf NVARCHAR(500) =
  N'{"title":"数据权限配置","icon":"lucide:database","query":{"entityname":"v_att_lst_Power","menuid":"A1000001-0001-4001-8001-000000000021"}}';

DECLARE @form_schema_json NVARCHAR(MAX) = N'{
  "layout": { "cols": 2, "labelWidth": 120, "labelAlign": "right" },
  "saveEntityName": "att_lst_Power",
  "primaryKey": "FID",
  "schema": [
    { "component": "Input", "fieldName": "manager_id", "label": "管理员/负责人工号" },
    { "component": "Input", "fieldName": "dept_id", "label": "部门ID(Guid)" },
    { "component": "Input", "fieldName": "emp_id", "label": "被授权员工工号" }
  ]
}';

DECLARE @schema_json NVARCHAR(MAX) = N'{
  "title": "数据权限配置",
  "actionModule": "/src/views/EntityList/dataPowerPermissionActions.ts",
  "tableName": "v_att_lst_Power",
  "primaryKey": "FID",
  "saveEntityName": "att_lst_Power",
  "deleteEntityName": "att_lst_Power",
  "toolbar": {
    "actions": [
      { "key": "add", "label": "新增", "type": "primary", "action": "add", "form_code": "form_att_data_power" },
      { "key": "edit", "label": "编辑", "type": "default", "action": "edit", "form_code": "form_att_data_power", "requiresSelection": true },
      { "key": "deleteSelected", "label": "删除", "action": "deleteSelected" },
      { "key": "export", "label": "导出", "action": "export" },
      { "key": "reload", "label": "刷新", "action": "reload", "type": "primary" },
      { "key": "pickDeptEmp", "label": "选人｜部门", "type": "primary", "action": "openDataPowerEditor", "requiresSelection": false }
    ]
  },
  "form": {
    "collapsed": false,
    "submitOnChange": true,
    "wrapperClass": "grid-cols-1 md:grid-cols-2 lg:grid-cols-2",
    "schema": [
      { "component": "Input", "fieldName": "manager_name", "label": "管理员姓名" },
      { "component": "Input", "fieldName": "emp_id", "label": "员工工号" },
      { "component": "Input", "fieldName": "type", "label": "类型" },
      { "component": "Input", "fieldName": "dept_name", "label": "部门名称" }
    ]
  },
  "grid": {
    "pagerConfig": { "enabled": true, "pageSize": 50 },
    "sortConfig": { "remote": true, "defaultSort": { "field": "manager_id", "order": "asc" } },
    "columns": [
      { "type": "checkbox", "width": 50 },
      { "type": "seq", "width": 60 },
      { "field": "type", "title": "类型", "width": 80, "sortable": true },
      { "field": "manager_id", "title": "管理员工号", "width": 110, "sortable": true },
      { "field": "manager_name", "title": "管理员姓名", "width": 100, "sortable": true },
      { "field": "manager_longname", "title": "管理员组织", "minWidth": 140, "sortable": true },
      { "field": "manager_dutyName", "title": "职务", "width": 100, "sortable": true },
      { "field": "dept_name", "title": "部门名称", "minWidth": 120, "sortable": true },
      { "field": "emp_id", "title": "员工工号", "width": 100, "sortable": true },
      { "field": "emp_name", "title": "员工姓名", "width": 100, "sortable": true }
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

-- ==================== 幂等删除（叶子 → 分组 → schema） ====================
DELETE FROM vben_t_sys_role_menu_actions
WHERE menu_id = @leaf_menu_id
  AND menu_action_id IN (@act_add_id, @act_edit_id, @act_del_id, @act_exp_id, @act_reload_id, @act_pick_id);

DELETE FROM vben_menu_actions
WHERE menu_id = @leaf_menu_id
  AND id IN (@act_add_id, @act_edit_id, @act_del_id, @act_exp_id, @act_reload_id, @act_pick_id);

DELETE FROM vben_t_sys_role_menus WHERE role_id = @role_id AND menus_id IN (@leaf_menu_id, @mid_menu_id);
DELETE FROM vben_menus_new WHERE id = @leaf_menu_id;
DELETE FROM vben_menus_new WHERE id = @mid_menu_id;

DELETE FROM vben_entitylist_desinger WHERE id = @list_id OR code = @list_code;
DELETE FROM vben_form_desinger WHERE id = @form_id OR code = @form_code;

-- ==================== 表单设计器 ====================
INSERT INTO vben_form_desinger (id, code, title, schema_json, list_code, created_at, updated_at)
VALUES (@form_id, @form_code, @title, @form_schema_json, @list_code, GETDATE(), GETDATE());

-- ==================== 列表 schema ====================
INSERT INTO vben_entitylist_desinger (id, code, title, table_name, schema_json, created_at, updated_at)
VALUES (@list_id, @list_code, @title, N'v_att_lst_Power', @schema_json, GETDATE(), GETDATE());

-- ==================== 菜单：二级分组（不占 layout，避免三级双 LAYOUT） ====================
INSERT INTO vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@mid_menu_id, @mid_title, @mid_path, N'', @meta_mid, @root_menu_id, 1, N'menu', 28);

-- ==================== 菜单：叶子 ====================
INSERT INTO vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@leaf_menu_id, @title, @path, @component, @meta_leaf, @mid_menu_id, 1, N'menu', 10);

INSERT INTO vben_t_sys_role_menus (id, role_id, menus_id, add_time)
VALUES
  (NEWID(), @role_id, @mid_menu_id, GETDATE()),
  (NEWID(), @role_id, @leaf_menu_id, GETDATE());

-- ==================== 菜单按钮 + 系统管理员权限 ====================
INSERT INTO vben_menu_actions (id, menu_id, action_key, label, button_type, action, confirm_text, sort, status, form_code, requires_selection)
VALUES
  (@act_add_id, @leaf_menu_id, N'add', N'新增', N'primary', N'add', NULL, 10, 1, @form_code, 0),
  (@act_edit_id, @leaf_menu_id, N'edit', N'编辑', N'default', N'edit', NULL, 20, 1, @form_code, 1),
  (@act_del_id, @leaf_menu_id, N'deleteSelected', N'删除', N'default', N'deleteSelected', NULL, 30, 1, NULL, 0),
  (@act_exp_id, @leaf_menu_id, N'export', N'导出', N'default', N'export', NULL, 40, 1, NULL, 0),
  (@act_reload_id, @leaf_menu_id, N'reload', N'刷新', N'primary', N'reload', NULL, 50, 1, NULL, 0),
  (@act_pick_id, @leaf_menu_id, N'pickDeptEmp', N'选人｜部门', N'primary', N'openDataPowerEditor', NULL, 45, 1, NULL, 0);

INSERT INTO vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status, add_time)
VALUES
  (NEWID(), @role_id, @act_add_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_edit_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_del_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_exp_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_reload_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_pick_id, @leaf_menu_id, 1, GETDATE());

PRINT N'OK: 考勤数据权限 → 数据权限配置 已迁移（v_att_lst_Power + 菜单分组 + 按钮权限）。';
