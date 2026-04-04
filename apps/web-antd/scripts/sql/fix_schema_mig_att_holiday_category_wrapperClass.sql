/*
  =============================================================================
  修复：假别设定（code=mig_att_holiday_category）页面出现左/顶部空白
  原因推测：form 只有 2 个字段，但默认表单 wrapperClass 在大屏使用 3 列网格，
  第 3 列为空导致布局出现明显留白。
  
  处理方式：仅为该 schema 的 $.form.wrapperClass 改为 2 列网格，
  其它 schema 不受影响。
  =============================================================================
*/

SET NOCOUNT ON;

DECLARE @code NVARCHAR(100) = N'mig_att_holiday_category';
DECLARE @newWrapperClass NVARCHAR(200) =
  N'grid-cols-1 md:grid-cols-2 lg:grid-cols-2';

-- 查看修改前 wrapperClass
SELECT
  code,
  JSON_VALUE(schema_json, '$.form.wrapperClass') AS before_wrapperClass
FROM dbo.vben_entitylist_desinger
WHERE code = @code;

IF NOT EXISTS (SELECT 1 FROM dbo.vben_entitylist_desinger WHERE code = @code)
BEGIN
  RAISERROR(N'未找到 vben_entitylist_desinger.code=%s', 16, 1, @code);
  RETURN;
END

IF ISJSON((SELECT TOP 1 schema_json FROM dbo.vben_entitylist_desinger WHERE code = @code)) <> 1
BEGIN
  RAISERROR(N'schema_json 不是合法 JSON，无法 JSON_MODIFY：code=%s', 16, 1, @code);
  RETURN;
END

UPDATE dbo.vben_entitylist_desinger
SET schema_json = JSON_MODIFY(schema_json, '$.form.wrapperClass', @newWrapperClass)
WHERE code = @code;

-- 查看修改后 wrapperClass
SELECT
  code,
  JSON_VALUE(schema_json, '$.form.wrapperClass') AS after_wrapperClass
FROM dbo.vben_entitylist_desinger
WHERE code = @code;

PRINT N'完成：已更新假别设定 form.wrapperClass，建议刷新页面重新验证留白效果。';

