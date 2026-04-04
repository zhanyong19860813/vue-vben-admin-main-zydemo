/*
  [1003] 一键迁移：考勤日常处理 → 排班作业（硬编码页）

  老系统：
    - t_sys_function: 排班作业
    - page/url: jobScheduling_datagrid.aspx
    - entity: v_att_lst_JobScheduling

  新系统（MVP）：
    - 在“考勤日常处理”（mid）下新增叶子菜单“排班作业”
    - 前端组件：apps/web-antd/src/views/attendance/JobSchedulingWork.vue
    - 路由 path：/attendance/daily/job-scheduling-work

  前置：建议先执行
    - 1002_migrate_full_刷卡资料查询.sql（创建 mid：A1000001-0001-4001-8001-000000000030）
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

DECLARE @mid_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000030'; -- 考勤日常处理
IF NOT EXISTS (SELECT 1 FROM vben_menus_new WHERE id = @mid_menu_id)
BEGIN
  DECLARE @err_mid_missing NVARCHAR(500);
  SET @err_mid_missing = N'父菜单不存在：考勤日常处理。请先执行 1002_migrate_full_刷卡资料查询.sql。';
  RAISERROR(@err_mid_missing, 16, 1);
  RETURN;
END

DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000032';
DECLARE @title NVARCHAR(200) = N'排班作业';
DECLARE @path NVARCHAR(255) = N'/attendance/daily/job-scheduling-work';
DECLARE @component NVARCHAR(255) = N'/attendance/JobSchedulingWork';
DECLARE @meta NVARCHAR(500) =
  N'{"title":"排班作业","icon":"lucide:calendar-clock"}';

-- idempotent: leaf -> role menu -> menu
DELETE FROM vben_t_sys_role_menus WHERE menus_id = @leaf_menu_id;
DELETE FROM vben_menus_new WHERE id = @leaf_menu_id;

INSERT INTO vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (@leaf_menu_id, @title, @path, @component, @meta, @mid_menu_id, 1, N'menu', 20);

INSERT INTO vben_t_sys_role_menus (id, role_id, menus_id, add_time)
VALUES (NEWID(), @role_id, @leaf_menu_id, GETDATE());

PRINT N'OK: [1003] 考勤日常处理 → 排班作业 已新增硬编码页菜单。';

