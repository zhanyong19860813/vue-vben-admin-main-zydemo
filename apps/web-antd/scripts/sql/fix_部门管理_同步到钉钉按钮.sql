/*
  部门管理（DeptInfo）工具栏「同步到钉钉」未显示的原因：
  页面用 vben_v_user_role_menu_actions 按 action_key 过滤，需在 vben_menu_actions 登记 syncDingTalk，并授权角色。

  幂等：可重复执行。
  菜单 id 与 1010_migrate_menu_部门岗位管理_移动部门管理.sql 中「部门管理」一致。
*/

SET NOCOUNT ON;

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

DECLARE @dept_menu_id UNIQUEIDENTIFIER = '47F8BE3C-CC7E-4D9B-AE37-F2484631D990';

IF NOT EXISTS (
  SELECT 1
  FROM dbo.vben_menu_actions WITH (NOLOCK)
  WHERE menu_id = @dept_menu_id AND action_key = N'syncDingTalk'
)
BEGIN
  INSERT INTO dbo.vben_menu_actions (id, menu_id, action_key, label, button_type, action, sort, status, requires_selection, form_code)
  VALUES (NEWID(), @dept_menu_id, N'syncDingTalk', N'同步到钉钉', N'default', N'syncDingTalk', 65, 1, 1, NULL);
END

DECLARE @ma_id UNIQUEIDENTIFIER = (
  SELECT TOP 1 id
  FROM dbo.vben_menu_actions WITH (NOLOCK)
  WHERE menu_id = @dept_menu_id AND action_key = N'syncDingTalk'
);

IF @ma_id IS NOT NULL
   AND NOT EXISTS (
     SELECT 1
     FROM dbo.vben_t_sys_role_menu_actions WITH (NOLOCK)
     WHERE role_id = @role_id AND menu_action_id = @ma_id
   )
BEGIN
  INSERT INTO dbo.vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status)
  VALUES (NEWID(), @role_id, @ma_id, @dept_menu_id, 1);
END

PRINT N'OK: 部门管理 已登记「同步到钉钉」(syncDingTalk) 并授权系统管理员。非系统管理员角色请在角色菜单按钮里勾选。';
