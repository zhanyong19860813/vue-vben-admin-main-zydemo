/*
  =============================================================================
  修复：三级菜单（父/子都用了 component='LAYOUT'）导致页面空白/闪烁

  做法：把父级（component='LAYOUT' 的中间节点）下的所有子菜单
        直接挂到它的父级（即把三层压成两层）
        然后删除中间节点本身。

  针对当前你库里的「考勤管理」模块（attendance）：
    root: A1000001-0001-4001-8001-000000000001（考勤管理，component=LAYOUT）
    mid : A1000001-0001-4001-8001-000000000002（考勤基础资料，component=LAYOUT）
    children of mid:
      - 假别设定（/EntityList/entityListFromDesigner）
      - 人事黑名单（/migration/HRMBlacklist）
  =============================================================================
*/

SET NOCOUNT ON;

DECLARE @root_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000001';
DECLARE @mid_id  UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000002';

BEGIN TRAN;
BEGIN TRY
  /* 1) 把 mid 下的所有子菜单 parent_id 改为 root */
  UPDATE dbo.vben_menus_new
  SET parent_id = @root_id
  WHERE parent_id = @mid_id;

  /* 2) 删除 mid 的角色菜单授权 */
  DELETE FROM dbo.vben_t_sys_role_menus
  WHERE menus_id = @mid_id;

  /* 3) 删除 mid 菜单节点本身（确保它没有其它子菜单后再删也行） */
  DELETE FROM dbo.vben_menus_new
  WHERE id = @mid_id;

  COMMIT;
  PRINT N'完成：已将 attendance 的三级结构压缩为两级（删除 mid，并把 children 挂到 root）。';
END TRY
BEGIN CATCH
  IF @@TRANCOUNT > 0 ROLLBACK;
  DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
  PRINT N'失败：' + @msg;
  THROW;
END CATCH;

