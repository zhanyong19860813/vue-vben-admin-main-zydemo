/*
  一键迁移：员工年假管理（普通列表）

  老系统：
    - 菜单：员工年假管理
    - entity: v_att_lst_VacationDay
    - url: datagrid.aspx?entity=v_att_lst_VacationDay

  新系统：
    - 列表：/EntityList/entityListFromDesigner
    - schema: vben_entitylist_desinger(code = v_att_lst_VacationDay)
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
DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000007'; -- 新增：员工年假管理
DECLARE @list_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000107';     -- vben_entitylist_desinger.id
DECLARE @code NVARCHAR(200) = N'v_att_lst_VacationDay';
DECLARE @title NVARCHAR(200) = N'员工年假管理';
DECLARE @path NVARCHAR(255) = N'/attendance/base/employee-vacation-day';
DECLARE @component NVARCHAR(255) = N'/EntityList/entityListFromDesigner';

DECLARE @meta NVARCHAR(500) =
  N'{"title":"员工年假管理","icon":"lucide:calendar-days","query":{"entityname":"v_att_lst_VacationDay","menuid":"A1000001-0001-4001-8001-000000000007"}}';

DECLARE @schema_json NVARCHAR(MAX) = N'{
  "title": "员工年假管理",
  "tableName": "v_att_lst_VacationDay",
  "primaryKey": "FID",
  "saveEntityName": "att_lst_VacationDay",
  "deleteEntityName": "att_lst_VacationDay",
  "actionModule": "/src/views/EntityList/stored-procedure.ts",
  "toolbar": { "actions": [
    {
      "key": "recalculate",
      "label": "重算",
      "type": "primary",
      "action": "executeProcedure",
      "procedureName": "dbo.att_pro_Vacation",
      "askYear": true,
      "yearParam": "year",
      "requiresSelection": false,
      "selectionParam": "emp_id",
      "confirm": "将重算所选年度的全员年假数据，是否继续？"
    }
  ] },
  "form": {
    "collapsed": false,
    "submitOnChange": true,
    "schema": [
      { "component": "Input", "fieldName": "EMP_ID", "label": "工号" },
      { "component": "Input", "fieldName": "name", "label": "姓名" },
      { "component": "Input", "fieldName": "FYear", "label": "年度" },
      { "component": "Input", "fieldName": "long_name", "label": "部门" }
    ]
  },
  "grid": {
    "pagerConfig": { "enabled": true, "pageSize": 50 },
    "sortConfig": { "remote": true, "defaultSort": { "field": "FYear", "order": "desc" } },
    "columns": [
      { "type": "checkbox", "width": 50 },
      { "type": "seq", "width": 60 },
      { "field": "EMP_ID", "title": "工号", "width": 100, "sortable": true },
      { "field": "name", "title": "姓名", "width": 120, "sortable": true },
      { "field": "long_name", "title": "部门", "minWidth": 180, "sortable": true },
      { "field": "dutyName", "title": "岗位", "minWidth": 140, "sortable": true },
      { "field": "FYear", "title": "年度", "width": 90, "sortable": true },
      { "field": "ThisVacationDay", "title": "当年年假", "width": 110, "sortable": true, "aggFunc": "sum" },
      { "field": "UserDay", "title": "已使用", "width": 100, "sortable": true, "aggFunc": "sum" },
      { "field": "RemainDay", "title": "剩余", "width": 100, "sortable": true, "aggFunc": "sum" },
      { "field": "LastRemainDay", "title": "上年结余", "width": 110, "sortable": true, "aggFunc": "sum" },
      { "field": "ActualVcationDay", "title": "实际年假", "width": 110, "sortable": true },
      { "field": "AdvanceUsedDay", "title": "预支已用", "width": 110, "sortable": true },
      { "field": "RemainVcationDay", "title": "可休剩余", "width": 110, "sortable": true },
      { "field": "frist_join_date", "title": "入职日期", "width": 120, "sortable": true },
      { "field": "EmpType", "title": "员工类型", "width": 100, "sortable": true },
      { "field": "EmpStatusName", "title": "状态", "width": 80, "sortable": true },
      { "field": "ModifyTime", "title": "修改时间", "width": 170, "sortable": true }
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
VALUES (@list_id, @code, @title, N'v_att_lst_VacationDay', @schema_json, GETDATE(), GETDATE());

-- ==================== 插入菜单（挂到 考勤基础资料） ====================
INSERT INTO vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@leaf_menu_id, @title, @path, @component, @meta, @base_menu_id, 1, N'menu', 80);

-- ==================== 授权：系统管理员 ====================
INSERT INTO vben_t_sys_role_menus (id, role_id, menus_id, add_time)
VALUES (NEWID(), @role_id, @leaf_menu_id, GETDATE());

PRINT N'OK: 员工年假管理 已迁移（列表+菜单+授权）。';

