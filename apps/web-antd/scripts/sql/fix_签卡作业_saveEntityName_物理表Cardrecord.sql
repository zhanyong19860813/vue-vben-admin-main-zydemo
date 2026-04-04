/*
  签卡作业：列表/表单 schema 误将 saveEntityName/deleteEntityName 配成 att_lst_RegRecord，
  导致审核/取消审核、弹窗保存等走 DataSave 时报「表 att_lst_RegRecord 不存在主键列 FID」。
  物理表应为 dbo.att_lst_Cardrecord（与 v_att_lst_RegRecord 视图定义一致）。

  在业务库执行一次即可；按 id 或 code 定位签卡列表行。
*/

SET NOCOUNT ON;

DECLARE @list_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000133';
DECLARE @list_code NVARCHAR(200) = N'v_att_lst_RegRecord';
DECLARE @form_code NVARCHAR(80) = N'form_att_sign_card';
DECLARE @physical NVARCHAR(200) = N'att_lst_Cardrecord';

DECLARE @target_list_id UNIQUEIDENTIFIER;
SELECT @target_list_id = id FROM vben_entitylist_desinger WHERE id = @list_id;
IF @target_list_id IS NULL
  SELECT TOP 1 @target_list_id = id FROM vben_entitylist_desinger WHERE code = @list_code;

IF @target_list_id IS NULL
BEGIN
  RAISERROR(N'未找到签卡列表设计器行（id/code）。请改 @list_id / @list_code 后重试。', 16, 1);
  RETURN;
END

UPDATE vben_entitylist_desinger
SET schema_json = JSON_MODIFY(
      JSON_MODIFY(
        JSON_MODIFY(schema_json, '$.saveEntityName', @physical),
        '$.deleteEntityName',
        @physical
      ),
      '$.primaryKey',
      'FID'
    ),
    updated_at = GETDATE()
WHERE id = @target_list_id;

UPDATE vben_form_desinger
SET schema_json = JSON_MODIFY(
      JSON_MODIFY(schema_json, '$.saveEntityName', @physical),
      '$.primaryKey',
      'FID'
    ),
    updated_at = GETDATE()
WHERE code = @form_code
   OR list_code = @list_code;

PRINT N'OK: 签卡列表/表单 saveEntityName 已纠正为 ' + @physical + N'（列表 id=' + CAST(@target_list_id AS NVARCHAR(36)) + N'）。';
