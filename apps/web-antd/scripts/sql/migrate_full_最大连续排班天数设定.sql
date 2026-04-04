/*
  一键迁移：最大连续排班天数设定（树形列表）

  老系统：
    - 菜单：最大连续排班天数设定
    - entity: v_att_lst_ShiftsRules
    - 平铺数据 + parent_id，按 sort 排序（treedatagrid）

  新系统：
    - 列表：/EntityList/entityListFromDesigner
    - schema: vben_entitylist_desinger(code = v_att_lst_ShiftsRules)
    - 菜单挂载：考勤管理(/attendance) → 考勤基础资料(/attendance/base) → 本菜单

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

DECLARE @base_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000002'; -- 考勤基础资料（已存在）
DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000005'; -- 新增：最大连续排班天数设定
DECLARE @list_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000105';     -- vben_entitylist_desinger.id
DECLARE @code NVARCHAR(200) = N'v_att_lst_ShiftsRules';
DECLARE @title NVARCHAR(200) = N'最大连续排班天数设定';
DECLARE @path NVARCHAR(255) = N'/attendance/base/max-shifts-days-rule';
DECLARE @component NVARCHAR(255) = N'/EntityList/entityListFromDesigner';

DECLARE @meta NVARCHAR(500) =
  N'{"title":"最大连续排班天数设定","icon":"lucide:git-branch","query":{"entityname":"v_att_lst_ShiftsRules","menuid":"A1000001-0001-4001-8001-000000000005"}}';

DECLARE @schema_json NVARCHAR(MAX) = N'{
  "title": "最大连续排班天数设定",
  "tableName": "v_att_lst_ShiftsRules",
  "primaryKey": "id",
  "saveEntityName": "v_att_lst_ShiftsRules",
  "deleteEntityName": "",
  "toolbar": {
    "actions": []
  },
  "form": {
    "collapsed": false,
    "submitOnChange": true,
    "schema": [
      { "component": "Input", "fieldName": "name", "label": "名称" },
      { "component": "Input", "fieldName": "DPM_Name", "label": "部门/组织" }
    ]
  },
  "grid": {
    "pagerConfig": { "enabled": true, "pageSize": 50 },
    "sortConfig": { "remote": true, "defaultSort": { "field": "sort", "order": "asc" } },
    "treeConfig": {
      "transform": true,
      "rowField": "id",
      "parentField": "parent_id",
      "children": "children",
      "expandAll": false,
      "accordion": false
    },
    "columns": [
      { "type": "seq", "width": 60 },
      { "field": "name", "title": "名称", "minWidth": 220, "treeNode": true, "sortable": true },
      { "field": "MaxShiftsDays", "title": "最大连续排班天数", "width": 160, "sortable": true },
      { "field": "MinRestDays", "title": "最小休息天数", "width": 140, "sortable": true },
      { "field": "is_MaxRest", "title": "是否启用最大休息", "width": 140, "sortable": true },
      { "field": "is_MinRest", "title": "是否启用最小休息", "width": 140, "sortable": true },
      { "field": "sort", "title": "排序", "width": 90, "sortable": true },
      { "field": "ModifyName", "title": "修改人", "width": 120, "sortable": true },
      { "field": "ModifyTime", "title": "修改时间", "width": 170, "sortable": true }
    ]
  },
  "api": {
    "query": "__API_QUERY__",
    "delete": "__API_DELETE__",
    "export": "__API_EXPORT__"
  }
}';

-- 尽量复用库里已存在配置的 API（避免环境差异：有的库里存完整 URL）
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

-- ==================== 幂等删除（先授权→菜单→列表） ====================
DELETE FROM vben_t_sys_role_menus WHERE role_id = @role_id AND menus_id = @leaf_menu_id;
DELETE FROM vben_menus_new WHERE id = @leaf_menu_id;
DELETE FROM vben_entitylist_desinger WHERE id = @list_id OR code = @code;

-- ==================== 插入列表 schema ====================
INSERT INTO vben_entitylist_desinger (id, code, title, table_name, schema_json, created_at, updated_at)
VALUES (@list_id, @code, @title, N'v_att_lst_ShiftsRules', @schema_json, GETDATE(), GETDATE());

-- ==================== 插入菜单（挂到 考勤基础资料） ====================
INSERT INTO vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@leaf_menu_id, @title, @path, @component, @meta, @base_menu_id, 1, N'menu', 60);

-- ==================== 授权：系统管理员 ====================
INSERT INTO vben_t_sys_role_menus (id, role_id, menus_id, add_time)
VALUES (NEWID(), @role_id, @leaf_menu_id, GETDATE());

PRINT N'OK: 最大连续排班天数设定 已迁移（列表+菜单+授权）。';

