/*
  表单设计器列表（vben_entitylist_desinger.code = formDesingerList）queryforvben 返回 400 的常见原因：

  - schema_json.primaryKey 误为 FID，但 vben_form_desinger 表主键列为 id，且无 grid.sortConfig.defaultSort 时，
    前端会把 SortBy 设为 FID → 列不存在 → 400。

  本脚本：将 primaryKey 改为 id，并设置 defaultSort 为 updated_at desc（表上存在该列）。

  幂等：可重复执行。

  说明：前端 QueryTable 已对「主键不在 grid 列中」做了 SortBy 兜底；仍建议修正库内配置，避免删除/导出等依赖 primaryKey 的行为异常。
*/

SET NOCOUNT ON;

DECLARE @code NVARCHAR(80) = N'formDesingerList';

IF NOT EXISTS (SELECT 1 FROM dbo.vben_entitylist_desinger WHERE code = @code)
BEGIN
  RAISERROR(N'未找到 vben_entitylist_desinger.code = formDesingerList，跳过。', 16, 1);
  RETURN;
END

UPDATE dbo.vben_entitylist_desinger
SET schema_json = JSON_MODIFY(
    JSON_MODIFY(
      CAST(schema_json AS NVARCHAR(MAX)),
      N'$.primaryKey',
      N'id'
    ),
    N'$.grid.sortConfig.defaultSort',
    JSON_QUERY(N'{"field":"updated_at","order":"desc"}')
  ),
  updated_at = GETDATE()
WHERE code = @code;

PRINT N'OK: 表单设计器列表 schema 已修正 primaryKey=id，defaultSort=updated_at desc。';
