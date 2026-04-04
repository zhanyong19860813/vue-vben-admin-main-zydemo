/*
  修复：加班规则设定（v_att_lst_overtimeRules）
  - 复选框列必须在 columns 最前面（否则 vxe 可能不渲染/体验很差）
  - 强制写入 toolbar.actions（新增/编辑）确保按钮存在

  幂等：可重复执行
*/

SET NOCOUNT ON;

DECLARE @list_code NVARCHAR(200) = N'v_att_lst_overtimeRules';

-- 1) toolbar.actions 强制写入（新增/编辑）
DECLARE @actions NVARCHAR(MAX) = N'[
  { "key": "add", "label": "新增", "type": "primary", "action": "add", "form_code": "form_att_overtime_rules" },
  { "key": "edit", "label": "编辑", "type": "default", "action": "edit", "form_code": "form_att_overtime_rules", "requiresSelection": true }
]';

UPDATE vben_entitylist_desinger
SET schema_json = JSON_MODIFY(schema_json, '$.toolbar.actions', JSON_QUERY(@actions)),
    updated_at = GETDATE()
WHERE code = @list_code;

-- 2) grid.columns：把 checkbox 移到第一列（去重后重建数组）
DECLARE @schema NVARCHAR(MAX);
SELECT TOP 1 @schema = schema_json FROM vben_entitylist_desinger WHERE code = @list_code;
IF @schema IS NULL
BEGIN
  RAISERROR(N'List schema not found: %s', 16, 1, @list_code);
  RETURN;
END

DECLARE @newCols NVARCHAR(MAX);

;WITH cols AS (
  SELECT
    CAST([key] AS INT) AS idx,
    value AS obj
  FROM OPENJSON(@schema, '$.grid.columns')
  WHERE ISNULL(JSON_VALUE(value, '$.type'), '') <> 'checkbox'
)
SELECT
  @newCols =
    N'[' +
    STRING_AGG(obj, N',') WITHIN GROUP (ORDER BY idx) +
    N']'
FROM (
  SELECT 0 AS idx, N'{"type":"checkbox","width":50}' AS obj
  UNION ALL
  SELECT idx + 1 AS idx, obj
  FROM cols
) s;

UPDATE vben_entitylist_desinger
SET schema_json = JSON_MODIFY(schema_json, '$.grid.columns', JSON_QUERY(@newCols)),
    updated_at = GETDATE()
WHERE code = @list_code;

PRINT N'OK: 已将 checkbox 列置顶，并补齐新增/编辑按钮。';

