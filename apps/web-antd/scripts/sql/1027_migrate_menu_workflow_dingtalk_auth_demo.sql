/*
  流程引擎 > 钉钉免登 Demo 菜单（持久化到数据库）
  说明：
  1) 仅插入菜单表 vben_menus_new
  2) 如需授权给角色，请将下方 role_id 替换为实际角色后执行授权 SQL
*/

DECLARE @menu_id UNIQUEIDENTIFIER = 'A0DF9255-4A9D-44F3-A4E2-D1A770000001';
DECLARE @parent_id UNIQUEIDENTIFIER;

SELECT TOP 1 @parent_id = id
FROM dbo.vben_menus_new
WHERE [path] = '/workflow';

IF @parent_id IS NULL
BEGIN
  SELECT TOP 1 @parent_id = id
  FROM dbo.vben_menus_new
  WHERE [name] IN ('Workflow', '流程引擎')
  ORDER BY sort, id;
END

IF NOT EXISTS (SELECT 1 FROM dbo.vben_menus_new WHERE id = @menu_id OR [path] = '/workflow/dingtalk-auth-demo')
BEGIN
  INSERT INTO dbo.vben_menus_new
    (id, [name], [path], component, parent_id, [type], meta, [status], sort)
  VALUES
    (
      @menu_id,
      'WorkflowDingTalkAuthDemo',
      '/workflow/dingtalk-auth-demo',
      '/workflow/dingtalk-auth-demo/index',
      @parent_id,
      'menu',
      N'{"title":"钉钉免登 Demo","icon":"lucide:shield-check"}',
      1,
      9999
    );
END
GO

/* 可选：给角色授权菜单
DECLARE @role_id UNIQUEIDENTIFIER = '替换为你的角色ID';
IF NOT EXISTS (
  SELECT 1 FROM dbo.vben_t_sys_role_menus
  WHERE role_id = @role_id AND menus_id = @menu_id
)
BEGIN
  INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id)
  VALUES (NEWID(), @role_id, @menu_id);
END
GO
*/

