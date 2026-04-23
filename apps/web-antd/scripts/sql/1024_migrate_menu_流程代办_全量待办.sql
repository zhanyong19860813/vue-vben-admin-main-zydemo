/*
  流程引擎：新增「流程代办」菜单（后端菜单加载用 — 全量待办总览）
  - 路径: /workflow/todo-all
  - 组件: workflow/todo-all/index  → views/workflow/todo-all/index.vue
  - 依赖后端: GET /api/workflow-engine/runtime/todo/all

  说明：
  - GetMenuFromDb / vben_v_user_role_menus 需写入 vben_t_sys_role_menus。
  - 与 1015/1022 一致：挂到与「流程表单绑定」同一父级；复制「流程表单绑定」已有角色权限到新菜单。
  - 本页为硬编码页，无 vben_entitylist_desinger / vben_menu_actions。

  幂等：可重复执行
*/

SET NOCOUNT ON;

DECLARE @role_name NVARCHAR(50) = N'系统管理员';
DECLARE @role_id UNIQUEIDENTIFIER;
SELECT TOP 1 @role_id = id FROM dbo.vben_role WITH (NOLOCK) WHERE name = @role_name;

DECLARE @binding_menu_id UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000401'; /* 流程表单绑定 */
DECLARE @menu_id UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000406';
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
  RAISERROR(N'未找到「流程引擎」父菜单。请先确认流程引擎或「流程表单绑定」菜单已存在。', 16, 1);
  RETURN;
END

IF EXISTS (SELECT 1 FROM dbo.vben_menus_new WITH (NOLOCK) WHERE id = @menu_id)
BEGIN
  UPDATE dbo.vben_menus_new
  SET
    name = N'流程代办',
    path = N'/workflow/todo-all',
    component = N'workflow/todo-all/index',
    meta = N'{"title":"流程代办","icon":"lucide:users"}',
    parent_id = @workflow_root_id,
    status = 1,
    type = N'menu',
    sort = 39
  WHERE id = @menu_id;
END
ELSE
BEGIN
  INSERT INTO dbo.vben_menus_new
    (id, name, path, component, meta, parent_id, status, type, sort)
  VALUES
    (@menu_id, N'流程代办', N'/workflow/todo-all', N'workflow/todo-all/index',
     N'{"title":"流程代办","icon":"lucide:users"}', @workflow_root_id, 1, N'menu', 39);
END

/* 兜底：系统管理员 */
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

/* 复制「流程表单绑定」已有角色的菜单权限 → 新菜单 */
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

PRINT N'OK: 已新增/更新菜单「流程代办」，并已按「流程表单绑定」的角色范围授权。';

SELECT
  m.id,
  m.name,
  m.path,
  m.component,
  m.parent_id,
  p.name AS parent_name,
  m.status,
  m.sort
FROM dbo.vben_menus_new m WITH (NOLOCK)
LEFT JOIN dbo.vben_menus_new p WITH (NOLOCK) ON p.id = m.parent_id
WHERE m.id = @menu_id;

SELECT e.name AS role_name, r.role_id, r.menus_id
FROM dbo.vben_t_sys_role_menus r WITH (NOLOCK)
JOIN dbo.vben_role e WITH (NOLOCK) ON e.id = r.role_id
WHERE r.menus_id = @menu_id;
