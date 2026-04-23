/*
  流程引擎：新增「流程管理（数据库）」菜单（与静态「流程管理」并列）
  - 路径: /workflow/process-management-db
  - 组件: workflow/process-management-db/index

  说明：与 1015 相同，写入 vben_menus_new + vben_t_sys_role_menus；幂等可重复执行。
*/

SET NOCOUNT ON;

DECLARE @role_name NVARCHAR(50) = N'系统管理员';
DECLARE @role_id UNIQUEIDENTIFIER;
SELECT TOP 1 @role_id = id FROM dbo.vben_role WITH (NOLOCK) WHERE name = @role_name;

DECLARE @binding_menu_id UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000401';
DECLARE @menu_id UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000405';
DECLARE @now DATETIME = GETDATE();

DECLARE @workflow_root_id UNIQUEIDENTIFIER;
SELECT TOP 1 @workflow_root_id = parent_id
FROM dbo.vben_menus_new WITH (NOLOCK)
WHERE id = @binding_menu_id AND parent_id IS NOT NULL;

IF @workflow_root_id IS NULL
BEGIN
  SELECT TOP 1 @workflow_root_id = parent_id
  FROM dbo.vben_menus_new WITH (NOLOCK)
  WHERE name IN (N'流程引擎（静态）', N'流程设计器（静态）', N'流程定义版本')
    AND parent_id IS NOT NULL
  ORDER BY sort, id;
END

IF @workflow_root_id IS NULL
BEGIN
  SELECT TOP 1 @workflow_root_id = id
  FROM dbo.vben_menus_new WITH (NOLOCK)
  WHERE path = N'/workflow' OR name = N'流程引擎'
  ORDER BY sort, id;
END

IF @workflow_root_id IS NULL
BEGIN
  RAISERROR(N'未找到「流程引擎」父菜单。', 16, 1);
  RETURN;
END

IF EXISTS (SELECT 1 FROM dbo.vben_menus_new WITH (NOLOCK) WHERE id = @menu_id)
BEGIN
  UPDATE dbo.vben_menus_new
  SET
    name = N'流程管理（数据库）',
    path = N'/workflow/process-management-db',
    component = N'workflow/process-management-db/index',
    meta = N'{"title":"流程管理（数据库）","icon":"lucide:database"}',
    parent_id = @workflow_root_id,
    status = 1,
    type = N'menu',
    sort = 38
  WHERE id = @menu_id;
END
ELSE
BEGIN
  INSERT INTO dbo.vben_menus_new
    (id, name, path, component, meta, parent_id, status, type, sort)
  VALUES
    (@menu_id, N'流程管理（数据库）', N'/workflow/process-management-db',
     N'workflow/process-management-db/index',
     N'{"title":"流程管理（数据库）","icon":"lucide:database"}', @workflow_root_id, 1, N'menu', 38);
END

IF @role_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM dbo.vben_t_sys_role_menus WITH (NOLOCK)
    WHERE role_id = @role_id AND menus_id = @menu_id
  )
BEGIN
  INSERT INTO dbo.vben_t_sys_role_menus
    (id, role_id, menus_id, bar_items, operate_range_type, add_time)
  VALUES
    (NEWID(), @role_id, @menu_id, N'*', N'ALL', @now);
END

INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id, bar_items, operate_range_type, add_time)
SELECT
  NEWID(),
  r.role_id,
  @menu_id,
  r.bar_items,
  r.operate_range_type,
  @now
FROM dbo.vben_t_sys_role_menus r WITH (NOLOCK)
WHERE r.menus_id = @binding_menu_id
  AND NOT EXISTS (
    SELECT 1
    FROM dbo.vben_t_sys_role_menus x WITH (NOLOCK)
    WHERE x.role_id = r.role_id AND x.menus_id = @menu_id
  );

PRINT N'OK: 流程管理（数据库）菜单已写入。';
