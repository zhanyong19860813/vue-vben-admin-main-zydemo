/*
  已执行过 migrate_full_数据权限配置.sql 的库：补齐「选人｜部门」按钮 + actionModule + 菜单按钮权限

  幂等：可重复执行（按 pickDeptEmp / 固定 GUID 先删后插）
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

DECLARE @leaf_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000021';
DECLARE @act_pick_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000326';

-- 1) schema：actionModule
UPDATE vben_entitylist_desinger
SET schema_json = JSON_MODIFY(CAST(schema_json AS NVARCHAR(MAX)), '$.actionModule', '/src/views/EntityList/dataPowerPermissionActions.ts')
WHERE code = N'v_att_lst_Power';

-- 2) schema：toolbar 增加按钮（仅当尚无 pickDeptEmp）
UPDATE vben_entitylist_desinger
SET schema_json = REPLACE(
  CAST(schema_json AS NVARCHAR(MAX)),
  N'"action": "reload", "type": "primary" }',
  N'"action": "reload", "type": "primary" }, { "key": "pickDeptEmp", "label": "选人｜部门", "type": "primary", "action": "openDataPowerEditor", "requiresSelection": false }'
)
WHERE code = N'v_att_lst_Power'
  AND CAST(schema_json AS NVARCHAR(MAX)) NOT LIKE N'%pickDeptEmp%';

-- 3) 菜单按钮 + 角色
DELETE FROM vben_t_sys_role_menu_actions WHERE menu_action_id = @act_pick_id;
DELETE FROM vben_menu_actions WHERE id = @act_pick_id;

INSERT INTO vben_menu_actions (id, menu_id, action_key, label, button_type, action, confirm_text, sort, status, form_code, requires_selection)
VALUES (@act_pick_id, @leaf_menu_id, N'pickDeptEmp', N'选人｜部门', N'primary', N'openDataPowerEditor', NULL, 45, 1, NULL, 0);

INSERT INTO vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status, add_time)
VALUES (NEWID(), @role_id, @act_pick_id, @leaf_menu_id, 1, GETDATE());

-- 已跑过旧版 fix（requiresSelection true / requires_selection 1）的库：纠正为不强制勾选
UPDATE vben_entitylist_desinger
SET schema_json = REPLACE(
  CAST(schema_json AS NVARCHAR(MAX)),
  N'"key": "pickDeptEmp", "label": "选人｜部门", "type": "primary", "action": "openDataPowerEditor", "requiresSelection": true',
  N'"key": "pickDeptEmp", "label": "选人｜部门", "type": "primary", "action": "openDataPowerEditor", "requiresSelection": false'
)
WHERE code = N'v_att_lst_Power'
  AND CAST(schema_json AS NVARCHAR(MAX)) LIKE N'%pickDeptEmp%';

UPDATE vben_menu_actions
SET requires_selection = 0
WHERE menu_id = @leaf_menu_id AND action_key = N'pickDeptEmp';

PRINT N'OK: 数据权限配置 已增加「选人｜部门」与 actionModule（若 REPLACE 未匹配请手工检查 toolbar.actions 顺序）。';
