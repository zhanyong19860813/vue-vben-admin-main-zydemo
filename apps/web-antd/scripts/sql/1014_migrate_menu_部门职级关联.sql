/*
  幂等迁移：【部门岗位管理】=>【部门职级关联】
  页面：hr/dep-rank-association/index（左树 v_t_base_department + 右表 v_base_dep_rank）
*/

DECLARE @role_name NVARCHAR(50) = N'系统管理员';
DECLARE @role_id UNIQUEIDENTIFIER;
SELECT TOP 1 @role_id = id FROM dbo.vben_role WHERE name = @role_name;
IF @role_id IS NULL
BEGIN
  RAISERROR(N'Role not found: %s', 16, 1, @role_name);
  RETURN;
END

DECLARE @parent_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000120'; -- 部门岗位管理
DECLARE @menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000124';        -- 部门职级关联

IF NOT EXISTS (SELECT 1 FROM dbo.vben_menus_new WHERE id = @menu_id)
BEGIN
  INSERT INTO dbo.vben_menus_new
    (id, name, path, component, meta, parent_id, status, type, sort)
  VALUES
    (
      @menu_id,
      N'部门职级关联',
      N'/dept-post/dep-rank-association',
      N'hr/dep-rank-association/index',
      N'{"icon":"mdi:account-tie","title":"部门职级关联","query":{"menuid":"A1000001-0001-4001-8001-000000000124"}}',
      @parent_menu_id,
      1,
      N'menu',
      124
    );
END
ELSE
BEGIN
  UPDATE dbo.vben_menus_new
  SET name = N'部门职级关联',
      path = N'/dept-post/dep-rank-association',
      component = N'hr/dep-rank-association/index',
      meta = N'{"icon":"mdi:account-tie","title":"部门职级关联","query":{"menuid":"A1000001-0001-4001-8001-000000000124"}}',
      parent_id = @parent_menu_id,
      status = 1,
      type = N'menu',
      sort = ISNULL(sort, 124)
  WHERE id = @menu_id;
END

DELETE FROM dbo.vben_t_sys_role_menus
WHERE role_id = @role_id AND menus_id = @menu_id;

INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id)
VALUES (NEWID(), @role_id, @menu_id);

DECLARE @action_keys TABLE(action_key NVARCHAR(50), label NVARCHAR(50), sort INT, requires_selection BIT, button_type NVARCHAR(20));
INSERT INTO @action_keys(action_key, label, sort, requires_selection, button_type) VALUES
  (N'add',            N'新增',         10, 0, N'primary'),
  (N'edit',           N'修改',         20, 1, N'default'),
  (N'deleteSelected', N'删除',         30, 1, N'danger'),
  (N'inherit',        N'子部门继承',   35, 1, N'default'),
  (N'reload',         N'刷新',         40, 0, N'default');

DELETE rma
FROM dbo.vben_t_sys_role_menu_actions rma
JOIN dbo.vben_menu_actions ma ON ma.id = rma.menu_action_id
WHERE ma.menu_id = @menu_id
  AND ma.action_key IN (SELECT action_key FROM @action_keys);

DELETE FROM dbo.vben_menu_actions
WHERE menu_id = @menu_id
  AND action_key IN (SELECT action_key FROM @action_keys);

INSERT INTO dbo.vben_menu_actions
  (id, menu_id, action_key, label, button_type, action, confirm_text, sort, status, form_code, requires_selection)
SELECT
  NEWID(),
  @menu_id,
  k.action_key,
  k.label,
  k.button_type,
  k.action_key,
  CASE WHEN k.action_key = N'deleteSelected' THEN N'已选择记录,确认删除?' ELSE NULL END,
  k.sort,
  1,
  NULL,
  k.requires_selection
FROM @action_keys k;

INSERT INTO dbo.vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status)
SELECT NEWID(), @role_id, ma.id, @menu_id, 1
FROM dbo.vben_menu_actions ma
WHERE ma.menu_id = @menu_id
  AND ma.action_key IN (SELECT action_key FROM @action_keys);

PRINT N'OK: 部门职级关联菜单与按钮权限迁移完成。';
