/*
  员工年假管理：增加“重算”按钮（Procedure/execute → dbo.att_pro_Vacation，仅年份、全员）
*/
SET NOCOUNT ON;

DECLARE @code NVARCHAR(200) = N'v_att_lst_VacationDay';

DECLARE @actions NVARCHAR(MAX) = N'[
  {
    "key": "recalculate",
    "label": "重算",
    "type": "primary",
    "action": "executeProcedure",
    "procedureName": "dbo.att_pro_Vacation",
    "askYear": true,
    "yearParam": "year",
    "requiresSelection": false,
    "selectionParam": "emp_id",
    "confirm": "将重算所选年度的全员年假数据，是否继续？"
  }
]';

UPDATE vben_entitylist_desinger
SET schema_json = JSON_MODIFY(
                    JSON_MODIFY(schema_json, '$.actionModule', '/src/views/EntityList/stored-procedure.ts'),
                    '$.toolbar.actions',
                    JSON_QUERY(@actions)
                  ),
    updated_at = GETDATE()
WHERE code = @code;

PRINT N'OK: 已为员工年假管理增加重算按钮(action=recalculate)。';

