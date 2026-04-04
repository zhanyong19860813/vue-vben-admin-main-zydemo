/*
  修复：最大连续排班天数设定（v_att_lst_ShiftsRules）列表的 API URL

  现象：
    - 列表能打开但无数据
    - 刷新提示“内部服务器错误”

  原因（本项目常见）：
    - 某些库里 vben_entitylist_desinger.schema_json.api.query 保存的是“完整 URL”
      而当前记录保存成了“相对 /api/...”，导致 requestClient 组合 URL 异常。

  策略：
    - 从库里已正常使用的配置（mig_att_holiday_category）读取 api.query/delete/export
    - 写回到 v_att_lst_ShiftsRules 的 schema_json.api.*
*/

SET NOCOUNT ON;

DECLARE @code NVARCHAR(200) = N'v_att_lst_ShiftsRules';
DECLARE @ref_code NVARCHAR(200) = N'mig_att_holiday_category';

DECLARE @api_query NVARCHAR(500) = NULL;
DECLARE @api_delete NVARCHAR(500) = NULL;
DECLARE @api_export NVARCHAR(500) = NULL;

SELECT TOP 1
  @api_query = JSON_VALUE(schema_json, '$.api.query'),
  @api_delete = JSON_VALUE(schema_json, '$.api.delete'),
  @api_export = JSON_VALUE(schema_json, '$.api.export')
FROM vben_entitylist_desinger
WHERE code = @ref_code;

IF @api_query IS NULL OR LTRIM(RTRIM(@api_query)) = N''
BEGIN
  RAISERROR(N'Reference schema not found or missing api.query: %s', 16, 1, @ref_code);
  RETURN;
END

UPDATE vben_entitylist_desinger
SET schema_json = JSON_MODIFY(
                  JSON_MODIFY(
                    JSON_MODIFY(schema_json, '$.api.query', @api_query),
                    '$.api.delete', @api_delete
                  ),
                  '$.api.export', @api_export
                ),
    updated_at = GETDATE()
WHERE code = @code;

PRINT N'OK: schema_json.api.* 已同步。';

