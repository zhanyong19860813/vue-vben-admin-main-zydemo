/*
  加班规则设定：补齐“菜单按钮(vben_menu_actions)+按钮权限(系统管理员)+列表toolbar显示”

  目标菜单：
    A1000001-0001-4001-8001-000000000006  加班规则设定

  目标表单：
    vben_form_desinger.code = form_att_overtime_rules

  说明：
    - QueryTable 实际渲染按钮来自列表 schema 的 toolbar.actions；
      这里同时写入 vben_menu_actions + role 权限，保证“菜单按钮体系”也完整。
    - 幂等：可重复执行（先删后插 / upsert）
*/

SET NOCOUNT ON;

DECLARE @menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000006';
DECLARE @list_code NVARCHAR(200) = N'v_att_lst_overtimeRules';
DECLARE @form_code NVARCHAR(100) = N'form_att_overtime_rules';

DECLARE @role_name NVARCHAR(50) = N'系统管理员';
DECLARE @role_id UNIQUEIDENTIFIER;
SELECT TOP 1 @role_id = r.id FROM vben_role r WHERE r.name = @role_name;
IF @role_id IS NULL
BEGIN
  RAISERROR(N'Role not found: %s', 16, 1, @role_name);
  RETURN;
END

-- 固定按钮ID（便于幂等/对齐权限）
DECLARE @act_add_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000306';
DECLARE @act_edit_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000307';

-- 0) 前置校验：表单是否存在（不存在也能插按钮，但点击会提示未找到 form_code）
IF NOT EXISTS (SELECT 1 FROM vben_form_desinger WHERE code = @form_code)
BEGIN
  PRINT N'WARN: vben_form_desinger 未找到 form_code=' + @form_code + N'（按钮可插入，但点击会提示未找到表单）';
END

-- 1) 写入菜单按钮（vben_menu_actions）
DELETE FROM vben_t_sys_role_menu_actions
WHERE role_id = @role_id AND menu_id = @menu_id AND menu_action_id IN (@act_add_id, @act_edit_id);

DELETE FROM vben_menu_actions
WHERE menu_id = @menu_id AND id IN (@act_add_id, @act_edit_id);

INSERT INTO vben_menu_actions (id, menu_id, action_key, label, button_type, action, confirm_text, sort, status, form_code, requires_selection)
VALUES
  (@act_add_id, @menu_id, N'add',  N'新增', N'primary', N'add',  NULL, 10, 1, @form_code, 0),
  (@act_edit_id,@menu_id, N'edit', N'编辑', N'default', N'edit', NULL, 20, 1, @form_code, 1);

-- 2) 系统管理员：菜单按钮权限（vben_t_sys_role_menu_actions）
INSERT INTO vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status, add_time)
VALUES
  (NEWID(), @role_id, @act_add_id,  @menu_id, 1, GETDATE()),
  (NEWID(), @role_id, @act_edit_id, @menu_id, 1, GETDATE());

-- 3) 同步写入列表 schema 的 toolbar.actions（确保页面显示按钮并可弹表单）
DECLARE @actions NVARCHAR(MAX) = N'[
  { "key": "add", "label": "新增", "type": "primary", "action": "add", "form_code": "form_att_overtime_rules" },
  { "key": "edit", "label": "编辑", "type": "default", "action": "edit", "form_code": "form_att_overtime_rules", "requiresSelection": true }
]';

UPDATE vben_entitylist_desinger
SET schema_json = JSON_MODIFY(schema_json, '$.toolbar.actions', JSON_QUERY(@actions)),
    updated_at = GETDATE()
WHERE code = @list_code;

-- 4) 确保 checkbox 列存在（编辑 requiresSelection 需要勾选行）
IF EXISTS (SELECT 1 FROM vben_entitylist_desinger WHERE code = @list_code AND schema_json NOT LIKE '%"type":"checkbox"%')
BEGIN
  UPDATE vben_entitylist_desinger
  SET schema_json = JSON_MODIFY(schema_json, 'append $.grid.columns', JSON_QUERY(N'{"type":"checkbox","width":50}')),
      updated_at = GETDATE()
  WHERE code = @list_code;
END

PRINT N'OK: 已生成菜单【新增/编辑】按钮，并授权系统管理员；列表toolbar已同步。';

