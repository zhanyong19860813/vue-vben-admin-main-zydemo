/*
  签卡作业列表首次加载 queryforvben 返回 400 的常见原因：
  1) 列表 schema 的 defaultSort.field 在列表视图/表中不存在。
  2) SimpleWhere 中非字符串值（前端已统一 stringify，见 QueryTable）。

  本脚本：将已入库的签卡列表设计的 defaultSort 改为主键 FID desc（多数考勤表有 FID；若无请手改 JSON 里 field）。

  定位行的顺序（与 1004 是否改过 @list_code 无关）：
    1) vben_entitylist_desinger.id = 1004 脚本中的固定 list_id
    2) code = 下方 @list_code
    3) code = v_att_lst_RegRecord / v_att_lst_SignCard（历史占位名）

  幂等：可重复执行（结果相同）。
*/

SET NOCOUNT ON;

/* 与 1004_migrate_full_签卡作业.sql 中 @list_code 保持一致；若仍找不到会按 list_id / 备用 code 再找 */
DECLARE @list_code NVARCHAR(200) = N'v_att_lst_RegRecord';
DECLARE @list_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000133';

DECLARE @target_id UNIQUEIDENTIFIER;

SELECT @target_id = id FROM vben_entitylist_desinger WHERE id = @list_id;

IF @target_id IS NULL
  SELECT @target_id = id FROM vben_entitylist_desinger WHERE code = @list_code;

IF @target_id IS NULL
  SELECT @target_id = id FROM vben_entitylist_desinger WHERE code = N'v_att_lst_RegRecord';

IF @target_id IS NULL
  SELECT @target_id = id FROM vben_entitylist_desinger WHERE code = N'v_att_lst_SignCard';

IF @target_id IS NULL
BEGIN
  RAISERROR(N'未找到签卡作业列表设计器行。请先执行 1004_migrate_full_签卡作业.sql，或查询：SELECT id, code, title FROM vben_entitylist_desinger WHERE title LIKE N''%签卡%'';', 16, 1);
  RETURN;
END

UPDATE vben_entitylist_desinger
SET schema_json = JSON_MODIFY(
  schema_json,
  '$.grid.sortConfig.defaultSort',
  JSON_QUERY(N'{"field":"FID","order":"desc"}')
),
    updated_at = GETDATE()
WHERE id = @target_id;

DECLARE @resolved_code NVARCHAR(200);
SELECT @resolved_code = code FROM vben_entitylist_desinger WHERE id = @target_id;

PRINT N'OK: id=' + CONVERT(NVARCHAR(36), @target_id) + N', code=' + ISNULL(@resolved_code, N'') + N' 列表 defaultSort 已设为 FID desc。';
