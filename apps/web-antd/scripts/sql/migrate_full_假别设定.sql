/*
  =============================================================================
  一键迁移：老系统「考勤管理 → 考勤基础资料 → 假别设定」
  执行前请修改 @api_query（若 API 地址不是本机 5155）；角色默认按名称「系统管理员」解析
  重复执行：会先删除本脚本涉及的列表（同 id 或同 code）、三级菜单及其全部角色的菜单授权，再重新插入。
  说明：
  - vben_entitylist_desinger.code = mig_att_holiday_category
  - 菜单 meta.query.entityname 必须与此 code 一致（entityListFromDesigner 按 code 拉 schema_json）
  - 列表列与老系统 t_set_datagrid.entity=v_att_lst_HolidayCategory 对齐
  =============================================================================
*/

SET NOCOUNT ON;

DECLARE @role_id UNIQUEIDENTIFIER;
SELECT @role_id = id FROM dbo.vben_role WHERE name = N'系统管理员';
IF @role_id IS NULL
BEGIN
  RAISERROR(N'未找到角色「系统管理员」。请执行：SELECT id, name FROM dbo.vben_role ORDER BY name;', 16, 1);
  RETURN;
END

DECLARE @api_query NVARCHAR(500) = N'http://127.0.0.1:5155/api/DynamicQueryBeta/queryforvben';

/* 固定 GUID（重复执行前先按下列 id / code 清理再插入） */
DECLARE @id_list UNIQUEIDENTIFIER = 'C3A10001-0001-4001-9001-000000000001'; /* vben_entitylist_desinger */
DECLARE @id_root UNIQUEIDENTIFIER = 'C3A10001-0001-4001-9001-000000000011'; /* 菜单根 */
DECLARE @id_mid UNIQUEIDENTIFIER  = 'C3A10001-0001-4001-9001-000000000012'; /* 二级 */
DECLARE @id_leaf UNIQUEIDENTIFIER = 'C3A10001-0001-4001-9001-000000000013'; /* 叶子 */

DECLARE @code NVARCHAR(100) = N'mig_att_holiday_category';
DECLARE @now DATETIME = GETDATE();

DECLARE @schema_json NVARCHAR(MAX) = N'{"title":"假别设定","tableName":"v_att_lst_HolidayCategory","primaryKey":"FID","toolbar":{"actions":[]},"form":{"collapsed":false,"submitOnChange":false,"schema":[{"component":"Input","fieldName":"HC_ID","label":"假别代号"},{"component":"Input","fieldName":"HC_Name","label":"假别说明"}]},"grid":{"columns":[{"type":"checkbox","width":50},{"type":"seq","width":50},{"field":"HC_ID","title":"假别代号","width":100,"sortable":true},{"field":"HC_Name","title":"假别说明","minWidth":140,"sortable":true,"showOverflow":true},{"field":"HC_Min","title":"最小请假值","width":110,"sortable":true},{"field":"HC_Max","title":"最大请假值","width":110,"sortable":true},{"field":"HC_Unit","title":"假别单位","width":100},{"field":"HC_LegalNum","title":"法定数","width":90,"sortable":true},{"field":"HC_FailureTime","title":"失效日期","width":120,"sortable":true},{"field":"HC_ApplyPeriod","title":"申请期限","width":100,"sortable":true},{"field":"HC_Paidleave","title":"是否有薪假","width":110,"sortable":true}],"pagerConfig":{"enabled":true,"pageSize":20},"sortConfig":{"remote":true,"defaultSort":{"field":"HC_ID","order":"asc"}}},"api":{"query":"'
  + @api_query
  + N'"}}';

/* 0) 已存在则先删：授权 → 子菜单 → 父菜单 → 列表（避免主键/重复 code） */
DELETE FROM dbo.vben_t_sys_role_menus WHERE menus_id IN (@id_leaf, @id_mid, @id_root);

DELETE FROM dbo.vben_menus_new WHERE id = @id_leaf;
DELETE FROM dbo.vben_menus_new WHERE id = @id_mid;
DELETE FROM dbo.vben_menus_new WHERE id = @id_root;

DELETE FROM dbo.vben_entitylist_desinger WHERE id = @id_list OR code = @code;

PRINT N'已清理：vben_t_sys_role_menus（上述三菜单）、vben_menus_new（三级）、vben_entitylist_desinger（id 或 code）';

/* 1) 列表设计器数据 */
INSERT INTO dbo.vben_entitylist_desinger (id, code, title, table_name, schema_json, created_at, updated_at)
VALUES (@id_list, @code, N'假别设定', N'v_att_lst_HolidayCategory', @schema_json, @now, @now);
PRINT N'已插入 vben_entitylist_desinger: ' + @code;

/* 2) 菜单三级 */
INSERT INTO dbo.vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (
  @id_root, N'考勤管理', N'/migrated/attendance', N'LAYOUT',
  N'{"title":"考勤管理","icon":"lucide:calendar-days","query":{"menuid":"C3A10001-0001-4001-9001-000000000011"}}',
  NULL, 1, N'menu', 60
);

INSERT INTO dbo.vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (
  @id_mid, N'考勤基础资料', N'/migrated/attendance/base', N'LAYOUT',
  N'{"title":"考勤基础资料","icon":"lucide:folder-tree","query":{"menuid":"C3A10001-0001-4001-9001-000000000012"}}',
  @id_root, 1, N'menu', 10
);

INSERT INTO dbo.vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (
  @id_leaf, N'假别设定', N'/migrated/attendance/base/holiday-category', N'/EntityList/entityListFromDesigner',
  N'{"title":"假别设定","icon":"lucide:calendar-off","query":{"entityname":"mig_att_holiday_category","menuid":"C3A10001-0001-4001-9001-000000000013"}}',
  @id_mid, 1, N'menu', 40
);

PRINT N'已插入三级菜单';

/* 3) 角色授权：三级菜单各一条（系统管理员） */
INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id, bar_items, operate_range_type, add_time)
VALUES (NEWID(), @role_id, @id_root, N'*', N'ALL', @now);

INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id, bar_items, operate_range_type, add_time)
VALUES (NEWID(), @role_id, @id_mid, N'*', N'ALL', @now);

INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id, bar_items, operate_range_type, add_time)
VALUES (NEWID(), @role_id, @id_leaf, N'*', N'ALL', @now);

PRINT N'已为「系统管理员」写入菜单授权';
PRINT N'完成。请重新登录或刷新菜单。';
