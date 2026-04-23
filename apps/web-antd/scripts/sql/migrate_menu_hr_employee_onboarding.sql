/*
  =============================================================================
  人力资源 → 人事管理 → 员工入职登记
  一键写入：三级菜单 + 系统管理员菜单授权 + 工具栏按钮 + 按钮授权

  前端页面：apps/web-antd/src/views/hr/employee-onboarding/index.vue
  路由（与库表 path 对齐）：/hr /hr/personnel /hr/personnel/employee-onboarding

  幂等：先按本脚本固定 GUID 删除再插入，可重复执行。

  执行后：重新登录或刷新菜单；角色默认「系统管理员」（可按需改 @role_name）。
  说明：若同时保留 apps/web-antd/src/router/routes/modules/hr.ts 静态路由，可能出现
        重复菜单项，生产可只保留库表菜单并删除静态 hr 模块。
  =============================================================================
*/

SET NOCOUNT ON;

DECLARE @role_name NVARCHAR(50) = N'系统管理员';
DECLARE @role_id UNIQUEIDENTIFIER;
SELECT TOP 1 @role_id = r.id FROM dbo.vben_role r WHERE r.name = @role_name;
IF @role_id IS NULL
BEGIN
  RAISERROR(N'未找到角色「系统管理员」。SELECT id, name FROM dbo.vben_role;', 16, 1);
  RETURN;
END

DECLARE @id_root UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000001';
DECLARE @id_mid  UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000002';
DECLARE @id_leaf UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000003';

DECLARE @act_entry   UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000101';
DECLARE @act_edit    UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000102';
DECLARE @act_setdate UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000103';
DECLARE @act_export  UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000104';
DECLARE @act_pcard   UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000105';
DECLARE @act_synczk  UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000106';
DECLARE @act_syncjl  UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000107';
DECLARE @act_parch   UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000108';
DECLARE @act_reload  UNIQUEIDENTIFIER = 'A2000001-0001-4001-8001-000000000109';

DECLARE @now DATETIME = GETDATE();

/* ==================== 清理（子 → 父） ==================== */
DELETE FROM dbo.vben_t_sys_role_menu_actions
WHERE menu_id = @id_leaf
  AND menu_action_id IN (
    @act_entry, @act_edit, @act_setdate, @act_export, @act_pcard,
    @act_synczk, @act_syncjl, @act_parch, @act_reload
  );

DELETE FROM dbo.vben_menu_actions
WHERE menu_id = @id_leaf
  AND id IN (
    @act_entry, @act_edit, @act_setdate, @act_export, @act_pcard,
    @act_synczk, @act_syncjl, @act_parch, @act_reload
  );

DELETE FROM dbo.vben_t_sys_role_menus WHERE menus_id IN (@id_leaf, @id_mid, @id_root);
DELETE FROM dbo.vben_menus_new WHERE id = @id_leaf;
DELETE FROM dbo.vben_menus_new WHERE id = @id_mid;
DELETE FROM dbo.vben_menus_new WHERE id = @id_root;

/* ==================== 菜单（三级） ==================== */
INSERT INTO dbo.vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (
  @id_root,
  N'人力资源',
  N'/hr',
  N'LAYOUT',
  N'{"title":"人力资源","icon":"lucide:users-round","order":450,"query":{"menuid":"A2000001-0001-4001-8001-000000000001"}}',
  NULL,
  1,
  N'menu',
  450
);

INSERT INTO dbo.vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (
  @id_mid,
  N'人事管理',
  N'/hr/personnel',
  N'LAYOUT',
  N'{"title":"人事管理","icon":"lucide:contact","query":{"menuid":"A2000001-0001-4001-8001-000000000002"}}',
  @id_root,
  1,
  N'menu',
  10
);

INSERT INTO dbo.vben_menus_new (id, name, path, component, meta, parent_id, status, type, sort)
VALUES (
  @id_leaf,
  N'员工入职登记',
  N'/hr/personnel/employee-onboarding',
  N'hr/employee-onboarding/index',
  N'{"title":"员工入职登记","icon":"lucide:user-plus","keepAlive":true,"query":{"menuid":"A2000001-0001-4001-8001-000000000003"}}',
  @id_mid,
  1,
  N'menu',
  10
);

/* ==================== 角色 → 菜单 ==================== */
INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id, bar_items, operate_range_type, add_time)
VALUES (NEWID(), @role_id, @id_root, N'*', N'ALL', @now);

INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id, bar_items, operate_range_type, add_time)
VALUES (NEWID(), @role_id, @id_mid, N'*', N'ALL', @now);

INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id, bar_items, operate_range_type, add_time)
VALUES (NEWID(), @role_id, @id_leaf, N'*', N'ALL', @now);

/* ==================== 菜单按钮（action_key 与前端 HR_ONB_ACTION 一致） ==================== */
INSERT INTO dbo.vben_menu_actions (
  id, menu_id, action_key, label, button_type, action, confirm_text, sort, status, form_code, requires_selection
)
VALUES
  (@act_entry,   @id_leaf, N'hr_onb_entry',        N'员工入职',       N'primary', N'hr_onb_entry',        NULL, 10, 1, NULL, 0),
  (@act_edit,    @id_leaf, N'hr_onb_edit',         N'修改',           N'default', N'hr_onb_edit',         NULL, 20, 1, NULL, 1),
  (@act_synczk,  @id_leaf, N'hr_onb_sync_dingtalk', N'同步钉钉',      N'default', N'hr_onb_sync_dingtalk', NULL, 25, 1, NULL, 1),
  (@act_setdate, @id_leaf, N'hr_onb_setdate',      N'调整入职转正',   N'default', N'hr_onb_setdate',      NULL, 30, 1, NULL, 0),
  (@act_export,  @id_leaf, N'hr_onb_export',       N'导出',           N'default', N'hr_onb_export',       NULL, 40, 1, NULL, 0),
  (@act_pcard,   @id_leaf, N'hr_onb_print_card',   N'工牌打印',       N'default', N'hr_onb_print_card',   NULL, 50, 1, NULL, 0),
  (@act_parch,   @id_leaf, N'hr_onb_print_archive', N'档案信息打印', N'default', N'hr_onb_print_archive', NULL, 60, 1, NULL, 1);

/* 标签长度上限 50：「调整入职/转正日期」截短为「调整入职转正」；需在界面完整文案可改 nvarchar 列宽后恢复 */

/* ==================== 系统管理员 → 按钮 ==================== */
INSERT INTO dbo.vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status, add_time)
VALUES
  (NEWID(), @role_id, @act_entry,   @id_leaf, 1, @now),
  (NEWID(), @role_id, @act_edit,    @id_leaf, 1, @now),
  (NEWID(), @role_id, @act_synczk,  @id_leaf, 1, @now),
  (NEWID(), @role_id, @act_setdate, @id_leaf, 1, @now),
  (NEWID(), @role_id, @act_export,  @id_leaf, 1, @now),
  (NEWID(), @role_id, @act_pcard,   @id_leaf, 1, @now),
  (NEWID(), @role_id, @act_parch,   @id_leaf, 1, @now);

PRINT N'OK: 人力资源/人事管理/员工入职登记 菜单、授权与按钮权限已写入。请重新登录。';
