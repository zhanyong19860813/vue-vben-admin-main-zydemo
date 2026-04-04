/*
  修复/增强：加班规则设定（v_att_lst_overtimeRules）
  - 新增/编辑：弹出表单设计器表单（vben_form_desinger）
  - 列表页增加【新增】【编辑】按钮（toolbar.actions）
  - 确保存在 checkbox 列（否则无法勾选行用于编辑/删除）

  幂等：可重复执行
*/

SET NOCOUNT ON;

DECLARE @list_code NVARCHAR(200) = N'v_att_lst_overtimeRules';
DECLARE @form_code NVARCHAR(50) = N'form_att_overtime_rules';
DECLARE @form_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000206';

-- 1) 创建/更新表单设计器配置（vben_form_desinger）
DECLARE @form_schema_json NVARCHAR(MAX) = N'{
  "layout": { "cols": 2, "labelWidth": 110, "labelAlign": "right" },
  "schema": [
    { "component": "Input", "fieldName": "de_id", "label": "部门编码" },
    { "component": "Input", "fieldName": "name", "label": "部门名称" },
    { "component": "Input", "fieldName": "ps_id", "label": "岗位编码" },
    { "component": "Input", "fieldName": "postname", "label": "岗位名称" },

    { "component": "Input", "fieldName": "RiChang", "label": "日常规则" },
    { "component": "InputNumber", "fieldName": "RiChangHours", "label": "日常小时", "componentProps": { "precision": 2, "min": 0 } },
    { "component": "Input", "fieldName": "Jiari", "label": "假日规则" },
    { "component": "InputNumber", "fieldName": "JiariHours", "label": "假日小时", "componentProps": { "precision": 2, "min": 0 } },
    { "component": "Input", "fieldName": "Jieri", "label": "节日规则" },
    { "component": "InputNumber", "fieldName": "JieriHours", "label": "节日小时", "componentProps": { "precision": 2, "min": 0 } },

    { "component": "InputNumber", "fieldName": "G1000", "label": "G1000", "componentProps": { "precision": 0, "min": 0 } }
  ]
}';

DELETE FROM vben_form_desinger WHERE id = @form_id OR code = @form_code;
INSERT INTO vben_form_desinger (id, code, title, schema_json, list_code, created_at, updated_at)
VALUES (@form_id, @form_code, N'加班规则设定', @form_schema_json, @list_code, GETDATE(), GETDATE());

-- 2) 列表增加 toolbar.actions（新增/编辑），并确保 checkbox 列存在
DECLARE @actions NVARCHAR(MAX) = N'[
  { "key": "add", "label": "新增", "type": "primary", "action": "add", "form_code": "form_att_overtime_rules" },
  { "key": "edit", "label": "编辑", "type": "default", "action": "edit", "form_code": "form_att_overtime_rules", "requiresSelection": true }
]';

-- toolbar.actions
UPDATE vben_entitylist_desinger
SET schema_json = JSON_MODIFY(schema_json, '$.toolbar.actions', JSON_QUERY(@actions)),
    updated_at = GETDATE()
WHERE code = @list_code;

-- grid.columns 追加 checkbox（若已存在则不重复追加）
IF EXISTS (SELECT 1 FROM vben_entitylist_desinger WHERE code = @list_code AND schema_json NOT LIKE '%"type":"checkbox"%')
BEGIN
  UPDATE vben_entitylist_desinger
  SET schema_json = JSON_MODIFY(
                    schema_json,
                    'append $.grid.columns',
                    JSON_QUERY(N'{"type":"checkbox","width":50}')
                  ),
      updated_at = GETDATE()
  WHERE code = @list_code;
END

PRINT N'OK: 加班规则设定 已增加 新增/编辑 按钮，并创建表单设计器表单。';

