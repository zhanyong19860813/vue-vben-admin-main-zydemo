/*
  [1002] 一键迁移：考勤管理 → 考勤日常处理 → 刷卡资料查询（只读列表）

  老系统：
    - t_sys_function：刷卡资料查询（parent=考勤日常处理 AE75689A-...）
    - entity: v_att_lst_Cardrecord
    - url: datagrid.aspx?entity=v_att_lst_Cardrecord&condition=1=2（默认不拉全表，需条件查询）

  新系统：
    - 新建分组：考勤日常处理（mid，component 空，避免三级双 LAYOUT）
    - 列表：/EntityList/entityListFromDesigner
    - 仅查询 + 导出 + 刷新（无新增/编辑/删除）

  前置：根菜单「考勤管理」须已存在（A1000001-0001-4001-8001-000000000001）

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

DECLARE @root_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000001';
IF NOT EXISTS (SELECT 1 FROM vben_menus_new WHERE id = @root_menu_id)
BEGIN
  RAISERROR(N'根菜单不存在：考勤管理 A1000001-0001-4001-8001-000000000001。请先初始化考勤模块菜单。', 16, 1);
  RETURN;
END

DECLARE @mid_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000030';
DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000031';
DECLARE @list_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000130';

DECLARE @list_code NVARCHAR(200) = N'v_att_lst_Cardrecord';
DECLARE @title_leaf NVARCHAR(200) = N'刷卡资料查询';
DECLARE @title_mid NVARCHAR(200) = N'考勤日常处理';
DECLARE @path_mid NVARCHAR(255) = N'/attendance/daily';
DECLARE @path_leaf NVARCHAR(255) = N'/attendance/daily/card-record';
DECLARE @component NVARCHAR(255) = N'/EntityList/entityListFromDesigner';

DECLARE @act_exp_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000340';
DECLARE @act_reload_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000341';

DECLARE @meta_mid NVARCHAR(500) =
  N'{"title":"考勤日常处理","icon":"lucide:clipboard-list","query":{"menuid":"A1000001-0001-4001-8001-000000000030"}}';

DECLARE @meta_leaf NVARCHAR(500) =
  N'{"title":"刷卡资料查询","icon":"lucide:credit-card","query":{"entityname":"v_att_lst_Cardrecord","menuid":"A1000001-0001-4001-8001-000000000031"}}';

DECLARE @schema_json NVARCHAR(MAX) = N'{
  "title": "刷卡资料查询",
  "tableName": "v_att_lst_Cardrecord",
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
      { "component": "Input", "fieldName": "AppState", "label": "状态" },
      { "component": "Input", "fieldName": "longdeptname", "label": "部门" },
      { "component": "Input", "fieldName": "SlotCardDate", "label": "刷卡日期" }
    ]
  },
  "grid": {
    "pagerConfig": { "enabled": true, "pageSize": 50 },
    "sortConfig": { "remote": true, "defaultSort": { "field": "SlotCardDate", "order": "desc" } },
    "columns": [
      { "type": "seq", "width": 60 },
      { "field": "EMP_ID", "title": "工号", "width": 96, "sortable": true },
      { "field": "name", "title": "姓名", "width": 100, "sortable": true },
      { "field": "longdeptname", "title": "部门", "minWidth": 160, "sortable": true },
      { "field": "dutyName", "title": "岗位", "width": 100, "sortable": true },
      { "field": "SlotCardDate", "title": "刷卡日期", "width": 170, "sortable": true },
      { "field": "SlotCardTime", "title": "刷卡时间", "width": 120, "sortable": true },
      { "field": "AppState", "title": "状态", "width": 80, "sortable": true },
      { "field": "AttendanceCard", "title": "卡号信息", "minWidth": 140, "sortable": false },
      { "field": "IsOk", "title": "是否有效", "width": 90, "sortable": true },
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
FROM vben_entitylist_desinger
WHERE code = N'mig_att_holiday_category';

IF @api_query IS NULL OR LTRIM(RTRIM(@api_query)) = N''
  SET @api_query = N'http://127.0.0.1:5155/api/DynamicQueryBeta/queryforvben';
IF @api_export IS NULL
  SET @api_export = N'';

SET @schema_json = REPLACE(@schema_json, N'__API_QUERY__', REPLACE(@api_query, N'"', N'\"'));
SET @schema_json = REPLACE(@schema_json, N'__API_EXPORT__', REPLACE(@api_export, N'"', N'\"'));

-- ==================== 幂等删除 ====================
DELETE FROM vben_t_sys_role_menu_actions
WHERE menu_id = @leaf_menu_id
  AND menu_action_id IN (@act_exp_id, @act_reload_id);

DELETE FROM vben_menu_actions
WHERE menu_id = @leaf_menu_id
  AND id IN (@act_exp_id, @act_reload_id);

DELETE FROM vben_t_sys_role_menus WHERE role_id = @role_id AND menus_id IN (@leaf_menu_id, @mid_menu_id);
DELETE FROM vben_menus_new WHERE id = @leaf_menu_id;
DELETE FROM vben_menus_new WHERE id = @mid_menu_id;
DELETE FROM vben_entitylist_desinger WHERE id = @list_id OR code = @list_code;

-- ==================== 列表 schema ====================
INSERT INTO vben_entitylist_desinger (id, code, title, table_name, schema_json, created_at, updated_at)
VALUES (@list_id, @list_code, @title_leaf, N'v_att_lst_Cardrecord', @schema_json, GETDATE(), GETDATE());

-- ==================== 菜单：分组 + 叶子 ====================
INSERT INTO vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@mid_menu_id, @title_mid, @path_mid, N'', @meta_mid, @root_menu_id, 1, N'menu', 26);

INSERT INTO vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@leaf_menu_id, @title_leaf, @path_leaf, @component, @meta_leaf, @mid_menu_id, 1, N'menu', 10);

INSERT INTO vben_t_sys_role_menus (id, role_id, menus_id, add_time)
VALUES
  (NEWID(), @role_id, @mid_menu_id, GETDATE()),
  (NEWID(), @role_id, @leaf_menu_id, GETDATE());

-- ==================== 菜单按钮 + 系统管理员权限 ====================
INSERT INTO vben_menu_actions (id, menu_id, action_key, label, button_type, action, confirm_text, sort, status, form_code, requires_selection)
VALUES
  (@act_exp_id, @leaf_menu_id, N'export', N'导出', N'default', N'export', NULL, 40, 1, NULL, 0),
  (@act_reload_id, @leaf_menu_id, N'reload', N'刷新', N'primary', N'reload', NULL, 50, 1, NULL, 0);

INSERT INTO vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status, add_time)
VALUES
  (NEWID(), @role_id, @act_exp_id, @leaf_menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_reload_id, @leaf_menu_id, 1, GETDATE());

PRINT N'OK: [1002] 考勤日常处理 → 刷卡资料查询 已迁移（只读 v_att_lst_Cardrecord + 菜单 + 导出/刷新权限）。';
