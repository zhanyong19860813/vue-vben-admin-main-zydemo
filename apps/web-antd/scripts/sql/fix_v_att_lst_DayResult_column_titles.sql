/*
  修复：考勤日结果（v_att_lst_DayResult）列表表头文案

  将 grid 列标题由「*ID」改为名称类标题（field 不变）：
    班次ID → 班次
    节日ID → 节日
    部门ID → 部门

  适用：已执行过 1008 的旧库；新库直接跑更新后的 1008 即可。

  若表头已改但格子里仍是 UUID：列表列仍绑定 ShiftID/attHolidayID/dept_id。
  请改执行 fix_v_att_lst_DayResult_readable_shift_holiday_dept.sql（视图 + 列 field 一并改）。
*/

SET NOCOUNT ON;

DECLARE @code NVARCHAR(200) = N'v_att_lst_DayResult';

IF NOT EXISTS (SELECT 1 FROM dbo.vben_entitylist_desinger WHERE code = @code)
BEGIN
  RAISERROR(N'List not found: %s', 16, 1, @code);
  RETURN;
END

UPDATE dbo.vben_entitylist_desinger
SET schema_json = REPLACE(
  REPLACE(
    REPLACE(
      schema_json,
      N'"title": "班次ID"',
      N'"title": "班次"'
    ),
    N'"title": "节日ID"',
    N'"title": "节日"'
  ),
  N'"title": "部门ID"',
  N'"title": "部门"'
),
    updated_at = SYSUTCDATETIME()
WHERE code = @code;

PRINT N'[fix] v_att_lst_DayResult column titles updated (if old titles were present).';
