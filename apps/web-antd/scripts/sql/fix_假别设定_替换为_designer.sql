/*
  =============================================================================
  修复：把旧菜单「假别设定」切换为列表设计器渲染
    - 旧叶子 component：/migration/HolidayCategory
    - 目标 component：/EntityList/entityListFromDesigner
  同时删除我之前脚本新增的 /migrated/... 那套菜单分支（避免重复“假别设定”出现）
  注意：不删除 vben_entitylist_desinger（code=mig_att_holiday_category），因为页面需要它加载 schema_json。
  =============================================================================
*/

SET NOCOUNT ON;

DECLARE @old_leaf_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000003'; -- 旧「假别设定」leaf
DECLARE @code NVARCHAR(100) = N'mig_att_holiday_category';

/* 1) 更新旧叶子菜单：component + meta.query（entityname/m enuid） */
IF EXISTS (SELECT 1 FROM dbo.vben_menus_new WHERE id = @old_leaf_id)
BEGIN
  UPDATE dbo.vben_menus_new
  SET
    component = N'/EntityList/entityListFromDesigner',
    meta = N'{"title":"假别设定","icon":"lucide:calendar-off","query":{"entityname":"mig_att_holiday_category","menuid":"A1000001-0001-4001-8001-000000000003"}}'
  WHERE id = @old_leaf_id;

  PRINT N'已更新旧菜单：component=/EntityList/entityListFromDesigner，并写入 meta.query.entityname=' + @code;
END
ELSE
BEGIN
  PRINT N'未找到旧 leaf 菜单 id（A1000001-...-0003），跳过更新。请先确认 vben_menus_new。';
END

/* 2) 删除我之前插入的 /migrated/... 菜单分支（可避免重复“假别设定”） */
DECLARE @new_root_id UNIQUEIDENTIFIER = 'C3A10001-0001-4001-9001-000000000011';
DECLARE @new_mid_id UNIQUEIDENTIFIER  = 'C3A10001-0001-4001-9001-000000000012';
DECLARE @new_leaf_id UNIQUEIDENTIFIER = 'C3A10001-0001-4001-9001-000000000013';

DELETE FROM dbo.vben_t_sys_role_menus
WHERE menus_id IN (@new_root_id, @new_mid_id, @new_leaf_id);

DELETE FROM dbo.vben_menus_new
WHERE id IN (@new_leaf_id, @new_mid_id, @new_root_id);

PRINT N'已删除我新增的 /migrated/... 菜单分支（避免重复）。';
PRINT N'完成：请重新登录或刷新菜单。';

