/*
  流程引擎：新增「流程表单绑定」菜单（后端菜单加载用）
  - 路径: /workflow/binding
  - 组件: demos/workflow-binding/index
  - 默认授权：系统管理员
  幂等：可重复执行
*/

SET NOCOUNT ON;

DECLARE @role_name NVARCHAR(50) = N'系统管理员';
DECLARE @role_id UNIQUEIDENTIFIER;
SELECT TOP 1 @role_id = id FROM dbo.vben_role WITH (NOLOCK) WHERE name = @role_name;
IF @role_id IS NULL
BEGIN
  RAISERROR(N'未找到角色：%s', 16, 1, @role_name);
  RETURN;
END

DECLARE @workflow_root_id UNIQUEIDENTIFIER;
/* 优先：从现有「流程引擎（静态）/流程设计器（静态）/流程定义版本」反推同级父菜单 */
SELECT TOP 1 @workflow_root_id = parent_id
FROM dbo.vben_menus_new WITH (NOLOCK)
WHERE name IN (N'流程引擎（静态）', N'流程设计器（静态）', N'流程定义版本')
  AND parent_id IS NOT NULL
ORDER BY sort, id;

/* 兜底：再按路径/名称找 */
IF @workflow_root_id IS NULL
BEGIN
  SELECT TOP 1 @workflow_root_id = id
  FROM dbo.vben_menus_new WITH (NOLOCK)
  WHERE path = N'/workflow' OR name = N'流程引擎'
  ORDER BY sort, id;
END

IF @workflow_root_id IS NULL
BEGIN
  RAISERROR(N'未找到「流程引擎」父菜单（path=/workflow）。请先确认流程引擎菜单已存在。', 16, 1);
  RETURN;
END

DECLARE @menu_id UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000401';
DECLARE @now DATETIME = GETDATE();

IF EXISTS (SELECT 1 FROM dbo.vben_menus_new WITH (NOLOCK) WHERE id = @menu_id)
BEGIN
  UPDATE dbo.vben_menus_new
  SET
    name = N'流程表单绑定',
    path = N'/workflow/binding',
    component = N'demos/workflow-binding/index',
    meta = N'{"title":"流程表单绑定","icon":"lucide:link"}',
    parent_id = @workflow_root_id,
    status = 1,
    type = N'menu',
    sort = 35
  WHERE id = @menu_id;
END
ELSE
BEGIN
  INSERT INTO dbo.vben_menus_new
    (id, name, path, component, meta, parent_id, status, type, sort)
  VALUES
    (@menu_id, N'流程表单绑定', N'/workflow/binding', N'demos/workflow-binding/index',
     N'{"title":"流程表单绑定","icon":"lucide:link"}', @workflow_root_id, 1, N'menu', 35);
END

IF NOT EXISTS (
  SELECT 1
  FROM dbo.vben_t_sys_role_menus WITH (NOLOCK)
  WHERE role_id = @role_id AND menus_id = @menu_id
)
BEGIN
  INSERT INTO dbo.vben_t_sys_role_menus
    (id, role_id, menus_id, bar_items, operate_range_type, add_time)
  VALUES
    (NEWID(), @role_id, @menu_id, N'*', N'ALL', @now);
END

PRINT N'OK: 已新增/更新 菜单「流程表单绑定」并授权系统管理员。';

/* 验证输出 */
SELECT
  m.id,
  m.name,
  m.path,
  m.component,
  m.parent_id,
  p.name AS parent_name,
  m.status,
  m.sort
FROM dbo.vben_menus_new m
LEFT JOIN dbo.vben_menus_new p ON p.id = m.parent_id
WHERE m.id = @menu_id OR m.name = N'流程表单绑定';


