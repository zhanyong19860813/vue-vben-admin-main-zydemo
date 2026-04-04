/*
  一键迁移：加班规则设定（普通列表）

  老系统：
    - 菜单：加班规则设定
    - entity: v_att_lst_overtimeRules
    - datagrid.aspx?entity=v_att_lst_overtimeRules&order=de_id,ps_id&desc=NO&allowedit=true

  新系统：
    - 列表：/EntityList/entityListFromDesigner
    - schema: vben_entitylist_desinger(code = v_att_lst_overtimeRules)
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
DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000006'; -- 新增：加班规则设定
DECLARE @list_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000106';     -- vben_entitylist_desinger.id
DECLARE @code NVARCHAR(200) = N'v_att_lst_overtimeRules';
DECLARE @title NVARCHAR(200) = N'加班规则设定';
DECLARE @path NVARCHAR(255) = N'/attendance/base/overtime-rules';
DECLARE @component NVARCHAR(255) = N'/EntityList/entityListFromDesigner';

DECLARE @meta NVARCHAR(500) =
  N'{"title":"加班规则设定","icon":"lucide:clock","query":{"entityname":"v_att_lst_overtimeRules","menuid":"A1000001-0001-4001-8001-000000000006"}}';

DECLARE @schema_json NVARCHAR(MAX) = N'{
  "title": "加班规则设定",
  "tableName": "v_att_lst_overtimeRules",
  "primaryKey": "FID",
  "saveEntityName": "att_lst_overtimeRules",
  "deleteEntityName": "att_lst_overtimeRules",
  "toolbar": { "actions": [] },
  "form": {
    "collapsed": false,
    "submitOnChange": true,
    "schema": [
      { "component": "Input", "fieldName": "de_id", "label": "部门编码" },
      { "component": "Input", "fieldName": "name", "label": "部门名称" },
      { "component": "Input", "fieldName": "ps_id", "label": "岗位编码" },
      { "component": "Input", "fieldName": "postname", "label": "岗位名称" }
    ]
  },
  "grid": {
    "pagerConfig": { "enabled": true, "pageSize": 50 },
    "sortConfig": { "remote": true, "defaultSort": { "field": "de_id", "order": "asc" } },
    "columns": [
      { "type": "seq", "width": 60 },
      { "field": "de_id", "title": "部门编码", "width": 110, "sortable": true },
      { "field": "name", "title": "部门名称", "minWidth": 180, "sortable": true },
      { "field": "ps_id", "title": "岗位编码", "width": 100, "sortable": true },
      { "field": "postname", "title": "岗位名称", "minWidth": 160, "sortable": true },

      { "field": "RiChang", "title": "日常规则", "minWidth": 140, "sortable": true },
      { "field": "RiChangHours", "title": "日常小时", "width": 110, "sortable": true },
      { "field": "Jiari", "title": "假日规则", "minWidth": 140, "sortable": true },
      { "field": "JiariHours", "title": "假日小时", "width": 110, "sortable": true },
      { "field": "Jieri", "title": "节日规则", "minWidth": 140, "sortable": true },
      { "field": "JieriHours", "title": "节日小时", "width": 110, "sortable": true },

      { "field": "G1000", "title": "G1000", "width": 90, "sortable": true }
    ]
  },
  "api": {
    "query": "__API_QUERY__",
    "delete": "__API_DELETE__",
    "export": "__API_EXPORT__"
  }
}';

-- 复用库里已存在配置的 API（避免环境差异：有的库里存完整 URL）
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
VALUES (@list_id, @code, @title, N'v_att_lst_overtimeRules', @schema_json, GETDATE(), GETDATE());

-- ==================== 插入菜单（挂到 考勤基础资料） ====================
INSERT INTO vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@leaf_menu_id, @title, @path, @component, @meta, @base_menu_id, 1, N'menu', 70);

-- ==================== 授权：系统管理员 ====================
INSERT INTO vben_t_sys_role_menus (id, role_id, menus_id, add_time)
VALUES (NEWID(), @role_id, @leaf_menu_id, GETDATE());

PRINT N'OK: 加班规则设定 已迁移（列表+菜单+授权）。';

