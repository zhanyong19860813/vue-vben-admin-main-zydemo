/*
  修复：加班规则设定保存报错
  错误：表 v_att_lst_overtimeRules 不存在主键列 FID

  原因：
    - 列表 schema 把 saveEntityName 配成了视图 v_att_lst_overtimeRules（无主键定义）
    - QueryTable 弹窗保存时读取的是“列表 schema.saveEntityName”，不是表单设计器里的 saveEntityName

  修复：
    - 保持 tableName = v_att_lst_overtimeRules（用于查询）
    - 改 saveEntityName/deleteEntityName = att_lst_overtimeRules（真实主表，FID 为主键）
*/

SET NOCOUNT ON;

UPDATE vben_entitylist_desinger
SET schema_json = JSON_MODIFY(
                  JSON_MODIFY(schema_json, '$.saveEntityName', 'att_lst_overtimeRules'),
                  '$.deleteEntityName', 'att_lst_overtimeRules'
                ),
    updated_at = GETDATE()
WHERE code = N'v_att_lst_overtimeRules';

PRINT N'OK: v_att_lst_overtimeRules 的 saveEntityName/deleteEntityName 已改为 att_lst_overtimeRules。';

