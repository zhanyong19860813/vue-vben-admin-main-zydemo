/*
  幂等迁移：新增「部门岗位管理」分组菜单，并将「部门管理」(DeptInfo) 移动到该分组下；
  同时写入菜单按钮 vben_menu_actions + 角色按钮授权 vben_t_sys_role_menu_actions（默认 系统管理员）。

  说明：
  - 该脚本不删除/重建 DeptInfo 菜单本身，只调整 parent_id（保留原 path/component/meta.query.menuid）。
  - DeptInfo 页面按钮 key 与 vben_menu_actions.action_key 必须一致（含 syncDingTalk 同步到钉钉）。
*/

DECLARE @role_name NVARCHAR(50) = N'系统管理员';
DECLARE @role_id UNIQUEIDENTIFIER;

SELECT TOP 1 @role_id = r.id
FROM dbo.vben_role r
WHERE r.name = @role_name;

IF @role_id IS NULL
BEGIN
  RAISERROR(N'Role not found: %s', 16, 1, @role_name);
  RETURN;
END

DECLARE @dept_menu_id UNIQUEIDENTIFIER = '47F8BE3C-CC7E-4D9B-AE37-F2484631D990'; -- 部门管理（已存在）
DECLARE @group_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000120'; -- 部门岗位管理（新）

/* 1) upsert 分组菜单（顶级） */
IF NOT EXISTS (SELECT 1 FROM dbo.vben_menus_new WHERE id = @group_menu_id)
BEGIN
  INSERT INTO dbo.vben_menus_new (id, parent_id, name, path, component, meta, status, type, sort)
  VALUES
  (
    @group_menu_id,
    NULL,
    N'部门岗位管理',
    N'/dept-post',
    N'LAYOUT',
    N'{"icon":"mdi:account-group","title":"部门岗位管理","query":{"menuid":"A1000001-0001-4001-8001-000000000120"}}',
    1,
    N'menu',
    100
  );
END
ELSE
BEGIN
  UPDATE dbo.vben_menus_new
  SET name = N'部门岗位管理',
      path = N'/dept-post',
      component = N'LAYOUT',
      meta = N'{"icon":"mdi:account-group","title":"部门岗位管理","query":{"menuid":"A1000001-0001-4001-8001-000000000120"}}',
      status = 1,
      type = N'menu',
      sort = ISNULL(sort, 100),
      parent_id = NULL
  WHERE id = @group_menu_id;
END

/* 2) 移动「部门管理」到新分组下 */
IF EXISTS (SELECT 1 FROM dbo.vben_menus_new WHERE id = @dept_menu_id)
BEGIN
  UPDATE dbo.vben_menus_new
  SET parent_id = @group_menu_id
  WHERE id = @dept_menu_id;
END
ELSE
BEGIN
  DECLARE @dept_menu_id_text NVARCHAR(50);
  SET @dept_menu_id_text = CAST(@dept_menu_id AS NVARCHAR(50));
  RAISERROR(N'Menu not found: 部门管理 (%s)', 16, 1, @dept_menu_id_text);
  RETURN;
END

/* 3) 菜单授权：系统管理员 */
DELETE FROM dbo.vben_t_sys_role_menus
WHERE role_id = @role_id AND menus_id IN (@group_menu_id, @dept_menu_id);

INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id)
VALUES
  (NEWID(), @role_id, @group_menu_id),
  (NEWID(), @role_id, @dept_menu_id);

/* 4) 菜单按钮：先删再插（幂等） */
DECLARE @action_keys TABLE(action_key NVARCHAR(50), action_label NVARCHAR(50), sort INT, requires_selection BIT);
INSERT INTO @action_keys(action_key, action_label, sort, requires_selection) VALUES
  (N'add',          N'新增',     5,  0),
  (N'expandAll',    N'展开全部', 10, 0),
  (N'collapseAll',  N'折叠全部', 20, 0),
  (N'refresh',      N'刷新',     30, 0),
  (N'edit',         N'修改',     40, 1),
  (N'disable',      N'停用',     50, 1),
  (N'enable',       N'启用',     60, 1),
  (N'syncDingTalk', N'同步到钉钉', 65, 1);

/* 删除旧 action + 旧 role-action 绑定 */
DELETE rma
FROM dbo.vben_t_sys_role_menu_actions rma
JOIN dbo.vben_menu_actions ma ON ma.id = rma.menu_action_id
WHERE ma.menu_id = @dept_menu_id
  AND ma.action_key IN (SELECT action_key FROM @action_keys);

DELETE FROM dbo.vben_menu_actions
WHERE menu_id = @dept_menu_id
  AND action_key IN (SELECT action_key FROM @action_keys);

/* 插入 action */
INSERT INTO dbo.vben_menu_actions (id, menu_id, action_key, label, button_type, action, sort, status, requires_selection, form_code)
SELECT
  NEWID(),
  @dept_menu_id,
  k.action_key,
  k.action_label,
  CASE WHEN k.action_key = N'edit' THEN N'primary' ELSE N'default' END AS button_type,
  k.action_key AS action,
  k.sort,
  1 AS status,
  k.requires_selection,
  NULL
FROM @action_keys k;

/* 插入 role-action 绑定 */
INSERT INTO dbo.vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status)
SELECT NEWID(), @role_id, ma.id, @dept_menu_id, 1
FROM dbo.vben_menu_actions ma
WHERE ma.menu_id = @dept_menu_id
  AND ma.action_key IN (SELECT action_key FROM @action_keys);

PRINT N'OK: moved DeptInfo under 部门岗位管理; actions granted to 系统管理员.';

