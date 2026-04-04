/*
  签卡作业：库内配置仍指向不存在的 v_att_lst_SignCard / att_lst_SignCard 时的修复脚本。

  依据测试库核对结果：
    - dbo.v_att_lst_SignCard 不存在 → 列表 query 会 208
    - dbo.v_att_lst_RegRecord 存在（老菜单 entity）
    - 视图定义 FROM dbo.att_lst_Cardrecord → 保存/删除应用物理表 att_lst_Cardrecord（不是 att_lst_RegRecord）
    - 视图列为 long_name、CardReason 等（非 longdeptname、Remark）

  幂等：可重复执行（REPLACE 对已正确库影响很小；code/table_name 会写死为目标值）。
*/

SET NOCOUNT ON;

DECLARE @list_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000133';
DECLARE @form_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000233';
DECLARE @menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000033';

IF NOT EXISTS (SELECT 1 FROM vben_entitylist_desinger WHERE id = @list_id)
BEGIN
  RAISERROR(N'未找到签卡列表设计器行（id 与 1004 不一致）。请先执行 1004 或改脚本内 @list_id。', 16, 1);
  RETURN;
END

IF OBJECT_ID(N'dbo.v_att_lst_RegRecord', N'V') IS NULL
BEGIN
  RAISERROR(N'当前库不存在视图 dbo.v_att_lst_RegRecord，请勿执行本脚本或改目标视图名。', 16, 1);
  RETURN;
END

IF OBJECT_ID(N'dbo.att_lst_Cardrecord', N'U') IS NULL
  PRINT N'[警告] dbo.att_lst_Cardrecord 表不存在，保存/删除仍可能失败；请核对物理表名。';

UPDATE vben_entitylist_desinger
SET
  code = N'v_att_lst_RegRecord',
  table_name = N'v_att_lst_RegRecord',
  schema_json = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
    schema_json,
    N'v_att_lst_SignCard', N'v_att_lst_RegRecord'),
    N'att_lst_SignCard', N'att_lst_Cardrecord'),
    N'"field":"longdeptname"', N'"field":"long_name"'),
    N'"fieldName":"longdeptname"', N'"fieldName":"long_name"'),
    N'"field":"Remark"', N'"field":"CardReason"'),
    N'"fieldName":"Remark"', N'"fieldName":"CardReason"'),
  updated_at = GETDATE()
WHERE id = @list_id;

UPDATE vben_form_desinger
SET
  list_code = N'v_att_lst_RegRecord',
  schema_json = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
    schema_json,
    N'v_att_lst_SignCard', N'v_att_lst_RegRecord'),
    N'att_lst_SignCard', N'att_lst_Cardrecord'),
    N'att_lst_RegRecord', N'att_lst_Cardrecord'),
    N'"fieldName":"longdeptname"', N'"fieldName":"long_name"'),
    N'"fieldName":"Remark"', N'"fieldName":"CardReason"'),
  updated_at = GETDATE()
WHERE id = @form_id;

UPDATE vben_menus_new
SET meta = JSON_MODIFY(meta, N'$.query.entityname', N'v_att_lst_RegRecord')
WHERE id = @menu_id;

PRINT N'OK: 签卡作业已改为 列表=v_att_lst_RegRecord，保存表=att_lst_Cardrecord，列 long_name/CardReason；请刷新前端。';
