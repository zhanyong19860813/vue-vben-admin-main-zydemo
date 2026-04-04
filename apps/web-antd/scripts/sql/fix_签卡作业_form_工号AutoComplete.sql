/*
  签卡作业弹窗：工号改为远程 AutoComplete，选中后回填姓名、部门（与 FormFromDesignerModal.attachAutoCompleteRemoteQuery 约定一致）。
  数据源：v_t_base_employee（需在后端 queryforvben 白名单内）。

  幂等：若已是 AutoComplete，REPLACE 不匹配则跳过；可检查 schema_json 是否含 "EMP_ID" 与 AutoComplete。
*/

SET NOCOUNT ON;

DECLARE @form_code NVARCHAR(80) = N'form_att_sign_card';

IF NOT EXISTS (SELECT 1 FROM vben_form_desinger WHERE code = @form_code)
BEGIN
  RAISERROR(N'未找到 vben_form_desinger.code = form_att_sign_card', 16, 1);
  RETURN;
END

DECLARE @old1 NVARCHAR(200) = N'{ "component": "Input", "fieldName": "EMP_ID", "label": "工号" }';
DECLARE @new1 NVARCHAR(MAX) = N'{ "component": "AutoComplete", "fieldName": "EMP_ID", "label": "工号", "componentProps": { "placeholder": "输入工号、姓名或部门搜索", "dataSourceType": "query", "tableName": "v_t_base_employee", "queryFields": "code,name,long_name,longdeptname", "labelField": "name", "valueField": "code", "searchField": "code,name,longdeptname", "pageSize": 15, "dropdownMatchSelectWidth": false, "responseMap": { "name": "name", "long_name": "long_name", "longdeptname": "long_name" }, "displayColumnsText": "code,工号\nname,姓名\nlongdeptname,部门" } }';

UPDATE vben_form_desinger
SET schema_json = REPLACE(CAST(schema_json AS NVARCHAR(MAX)), @old1, @new1),
    updated_at = GETDATE()
WHERE code = @form_code
  AND CHARINDEX(@old1, CAST(schema_json AS NVARCHAR(MAX))) > 0;

IF @@ROWCOUNT = 0
  PRINT N'跳过：未找到与 @old1 完全一致的片段（可能已是 AutoComplete，或 JSON 空格不同）。可重跑 1004 或手工改 vben_form_desinger.schema_json。';
ELSE
  PRINT N'OK: form_att_sign_card 工号已改为 AutoComplete + 选中回填 name、long_name。';
