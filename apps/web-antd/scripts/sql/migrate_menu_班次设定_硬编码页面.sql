/*
  班次设定：硬编码前端页（不走列表设计器）

  前端组件：apps/web-antd/src/views/attendance/ShiftBcSetting.vue
  菜单 component 须与 glob 解析一致：/attendance/ShiftBcSetting → views/attendance/ShiftBcSetting.vue

  幂等：先删后插（本菜单 id 固定）
*/

SET NOCOUNT ON;

DECLARE @role_name NVARCHAR(50) = N'系统管理员';
DECLARE @role_id UNIQUEIDENTIFIER;
SELECT TOP 1 @role_id = r.id FROM vben_role r WHERE r.name = @role_name;
IF @role_id IS NULL
BEGIN
  RAISERROR(N'Role not found: %s', 16, 1, @role_name);
  RETURN;
END

DECLARE @base_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000002'; -- 考勤基础资料
DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000009'; -- 班次设定
DECLARE @title NVARCHAR(200) = N'班次设定';
DECLARE @path NVARCHAR(255) = N'/attendance/base/shift-bc-setting';
DECLARE @component NVARCHAR(255) = N'/attendance/ShiftBcSetting';

-- 无 meta.query：静态页，不做 entityList 权限按钮过滤
DECLARE @meta NVARCHAR(500) = N'{"title":"班次设定","icon":"lucide:clock-3"}';

DELETE FROM vben_t_sys_role_menus WHERE role_id = @role_id AND menus_id = @leaf_menu_id;
DELETE FROM vben_menus_new WHERE id = @leaf_menu_id;

INSERT INTO vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@leaf_menu_id, @title, @path, @component, @meta, @base_menu_id, 1, N'menu', 61);

INSERT INTO vben_t_sys_role_menus (id, role_id, menus_id, add_time)
VALUES (NEWID(), @role_id, @leaf_menu_id, GETDATE());

PRINT N'OK: 班次设定 菜单已指向硬编码页 ShiftBcSetting.vue（+系统管理员菜单授权）。';
