/*
  员工年假管理：补齐“重算”按钮（列表schema + 菜单按钮 + 系统管理员按钮权限）
  菜单ID：A1000001-0001-4001-8001-000000000007
*/

SET NOCOUNT ON;

DECLARE @menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000007';
DECLARE @list_code NVARCHAR(200) = N'v_att_lst_VacationDay';
DECLARE @role_name NVARCHAR(50) = N'系统管理员';
DECLARE @role_id UNIQUEIDENTIFIER;
SELECT TOP 1 @role_id = id FROM vben_role WHERE name = @role_name;
IF @role_id IS NULL
BEGIN
  RAISERROR(N'Role not found: %s', 16, 1, @role_name);
  RETURN;
END

-- 固定按钮ID（幂等）
DECLARE @act_recalc_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000308';

-- 1) 列表 schema 按钮（确保 QueryTable 能渲染）
DECLARE @actions NVARCHAR(MAX) = N'[
  {
    "key": "recalculate",
    "label": "重算",
    "type": "primary",
    "action": "executeProcedure",
    "procedureName": "dbo.att_pro_Vacation",
    "askYear": true,
    "yearParam": "year",
    "requiresSelection": false,
    "selectionParam": "emp_id",
    "confirm": "将重算所选年度的全员年假数据，是否继续？"
  }
]';

UPDATE vben_entitylist_desinger
SET schema_json = JSON_MODIFY(
                  JSON_MODIFY(schema_json, '$.actionModule', '/src/views/EntityList/stored-procedure.ts'),
                  '$.toolbar.actions',
                  JSON_QUERY(@actions)
                ),
    updated_at = GETDATE()
WHERE code = @list_code;

-- 2) 菜单按钮
DELETE FROM vben_t_sys_role_menu_actions
WHERE menu_id = @menu_id AND menu_action_id = @act_recalc_id AND role_id = @role_id;

DELETE FROM vben_menu_actions
WHERE menu_id = @menu_id AND id = @act_recalc_id;

INSERT INTO vben_menu_actions
  (id, menu_id, action_key, label, button_type, action, confirm_text, sort, status, form_code, requires_selection)
VALUES
  (@act_recalc_id, @menu_id, N'recalculate', N'重算', N'primary', N'executeProcedure',
   N'将重算所选年度的全员年假数据，是否继续？', 10, 1, NULL, 0);

-- 3) 系统管理员按钮权限
INSERT INTO vben_t_sys_role_menu_actions
  (id, role_id, menu_action_id, menu_id, status, add_time)
VALUES
  (NEWID(), @role_id, @act_recalc_id, @menu_id, 1, GETDATE());

PRINT N'OK: 员工年假管理 重算按钮 已补齐（schema/menu_actions/role_menu_actions）。';

