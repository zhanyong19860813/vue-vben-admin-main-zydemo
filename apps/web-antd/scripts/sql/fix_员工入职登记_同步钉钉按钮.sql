/*
  员工入职登记（hr/employee-onboarding）工具栏增加「同步钉钉」按钮并授权。
  幂等：可重复执行。
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

DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000003'; -- 员工入职登记

IF NOT EXISTS (
  SELECT 1
  FROM dbo.vben_menu_actions WITH (NOLOCK)
  WHERE menu_id = @leaf_menu_id AND action_key = N'hr_onb_sync_dingtalk'
)
BEGIN
  INSERT INTO dbo.vben_menu_actions
    (id, menu_id, action_key, label, button_type, action, sort, status, requires_selection, form_code)
  VALUES
    (NEWID(), @leaf_menu_id, N'hr_onb_sync_dingtalk', N'同步钉钉', N'default', N'hr_onb_sync_dingtalk', 25, 1, 1, NULL);
END

DECLARE @ma_id UNIQUEIDENTIFIER = (
  SELECT TOP 1 id
  FROM dbo.vben_menu_actions WITH (NOLOCK)
  WHERE menu_id = @leaf_menu_id AND action_key = N'hr_onb_sync_dingtalk'
);

IF @ma_id IS NOT NULL
   AND NOT EXISTS (
     SELECT 1
     FROM dbo.vben_t_sys_role_menu_actions WITH (NOLOCK)
     WHERE role_id = @role_id AND menu_action_id = @ma_id
   )
BEGIN
  INSERT INTO dbo.vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status)
  VALUES (NEWID(), @role_id, @ma_id, @leaf_menu_id, 1);
END

PRINT N'OK: 员工入职登记 已登记「同步钉钉」(hr_onb_sync_dingtalk) 并授权系统管理员。';

