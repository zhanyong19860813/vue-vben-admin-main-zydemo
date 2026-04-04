/*
  1) dbo.vben_menus_new：考勤管理 → 考勤基础资料 → 假别设定（+ 可选人事黑名单）
  2) dbo.vben_t_sys_role_menus：角色菜单授权（默认授予「系统管理员」）

  前端页面：apps/web-antd/src/views/migration/HolidayCategory.vue、HRMBlacklist.vue
*/

-- 一级：考勤管理
INSERT INTO dbo.vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (
  'A1000001-0001-4001-8001-000000000001',
  N'考勤管理',
  N'/attendance',
  N'LAYOUT',
  N'{"title":"考勤管理","icon":"lucide:calendar-days","query":{"menuid":"a1000001-0001-4001-8001-000000000001"}}',
  NULL,
  1,
  N'menu',
  50
);

-- 二级：考勤基础资料
INSERT INTO dbo.vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (
  'A1000001-0001-4001-8001-000000000002',
  N'考勤基础资料',
  N'/attendance/base',
  N'LAYOUT',
  N'{"title":"考勤基础资料","icon":"lucide:folder-tree","query":{"menuid":"a1000001-0001-4001-8001-000000000002"}}',
  'A1000001-0001-4001-8001-000000000001',
  1,
  N'menu',
  10
);

-- 三级：假别设定（老系统实体 v_att_lst_HolidayCategory）
INSERT INTO dbo.vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (
  'A1000001-0001-4001-8001-000000000003',
  N'假别设定',
  N'/attendance/base/holiday-category',
  N'/migration/HolidayCategory',
  N'{"title":"假别设定","icon":"lucide:calendar-off","query":{"menuid":"a1000001-0001-4001-8001-000000000003"}}',
  'A1000001-0001-4001-8001-000000000002',
  1,
  N'menu',
  40
);

/*
  可选：人事黑名单迁移页（与「假别设定」并列在「考勤基础资料」下）
  不需要可整段删除或注释掉。
*/
INSERT INTO dbo.vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (
  'A1000001-0001-4001-8001-000000000004',
  N'人事黑名单（迁移）',
  N'/attendance/base/hrm-blacklist',
  N'/migration/HRMBlacklist',
  N'{"title":"人事黑名单（迁移）","icon":"lucide:user-x","query":{"menuid":"a1000001-0001-4001-8001-000000000004"}}',
  'A1000001-0001-4001-8001-000000000002',
  1,
  N'menu',
  50
);

/*
  =============================================================================
  角色菜单授权：dbo.vben_t_sys_role_menus
  （与 RoleManage / form-model-AddMenu 保存一致：bar_items='*', operate_range_type='ALL'）
  父级菜单也要各插一条，否则侧栏可能缺「考勤管理」「考勤基础资料」。
  =============================================================================
*/

SET NOCOUNT ON;

DECLARE @role_id UNIQUEIDENTIFIER;
SELECT @role_id = id FROM dbo.vben_role WHERE name = N'系统管理员';
IF @role_id IS NULL
BEGIN
  RAISERROR(N'未找到角色「系统管理员」。请执行：SELECT id, name FROM dbo.vben_role ORDER BY name;', 16, 1);
  RETURN;
END

INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id, bar_items, operate_range_type, add_time)
VALUES (NEWID(), @role_id, 'A1000001-0001-4001-8001-000000000001', N'*', N'ALL', GETDATE());

INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id, bar_items, operate_range_type, add_time)
VALUES (NEWID(), @role_id, 'A1000001-0001-4001-8001-000000000002', N'*', N'ALL', GETDATE());

INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id, bar_items, operate_range_type, add_time)
VALUES (NEWID(), @role_id, 'A1000001-0001-4001-8001-000000000003', N'*', N'ALL', GETDATE());

-- 若未插入「人事黑名单」菜单，请删除下一行
INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id, bar_items, operate_range_type, add_time)
VALUES (NEWID(), @role_id, 'A1000001-0001-4001-8001-000000000004', N'*', N'ALL', GETDATE());
