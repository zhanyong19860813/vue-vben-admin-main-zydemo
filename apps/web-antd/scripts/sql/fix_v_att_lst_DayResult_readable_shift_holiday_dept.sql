/*
  考勤日结果：列表显示「班次 / 节日 / 部门」的可读名称，而不是 UUID。

  我做了什么（脚本内容）：
    1) 视图 dbo.v_att_lst_DayResult：在 SELECT 中增加 hc.HC_Name AS attHolidayName（依赖已有 JOIN att_lst_Holiday / HolidayCategory）。
    2) 列表 vben_entitylist_desinger.code = v_att_lst_DayResult：改 grid 列 field，
       去掉重复的「班次名称」列与「部门」UUID 列（部门仍用 long_name）。

  你现在要做什么：
    1) **列顺序/表头已与老系统对齐时**：优先 **重跑 `1008_migrate_full_考勤日结果.sql`**（幂等），一次更新列表 JSON + 视图。
    2) 若暂时不能重跑 1008：在目标库执行本脚本（ALTER VIEW + 下面 REPLACE），再按需在设计器里对齐列。
    3) 刷新前端或重新打开「考勤日结果」菜单。

  说明：本脚本里对 schema_json 的 REPLACE 仅覆盖「班次/节日/部门」那版旧列；**完整与老 t_set_datagrid 一致**请以 1008 为准。
*/

SET NOCOUNT ON;

/* ---------- 1) 视图：节日名称 ---------- */
IF OBJECT_ID(N'dbo.v_att_lst_DayResult', N'V') IS NULL
BEGIN
  RAISERROR(N'View dbo.v_att_lst_DayResult does not exist.', 16, 1);
  RETURN;
END

DECLARE @vsql NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.v_att_lst_DayResult'));

IF @vsql IS NULL OR LEN(@vsql) = 0
BEGIN
  RAISERROR(N'Could not read view definition for v_att_lst_DayResult.', 16, 1);
  RETURN;
END

IF CHARINDEX(N'attHolidayName', @vsql) > 0
  PRINT N'[fix] View already has attHolidayName — skip ALTER VIEW.';
ELSE IF CHARINDEX(N'dr.attHolidayID', @vsql) = 0
BEGIN
  RAISERROR(N'Unexpected view body: dr.attHolidayID not found.', 16, 1);
  RETURN;
END
ELSE
BEGIN
  SET @vsql = REPLACE(@vsql, N'CREATE VIEW', N'ALTER VIEW');
  SET @vsql = REPLACE(@vsql, N'dr.attHolidayID,', N'dr.attHolidayID, hc.HC_Name AS attHolidayName,');
  EXEC sp_executesql @vsql;
  PRINT N'[fix] ALTER VIEW v_att_lst_DayResult: added attHolidayName.';
END

/* ---------- 2) 列表设计 schema_json ---------- */
DECLARE @code NVARCHAR(200) = N'v_att_lst_DayResult';

IF NOT EXISTS (SELECT 1 FROM dbo.vben_entitylist_desinger WHERE code = @code)
BEGIN
  RAISERROR(N'List not found: %s', 16, 1, @code);
  RETURN;
END

DECLARE @schema NVARCHAR(MAX);

SELECT @schema = schema_json
FROM dbo.vben_entitylist_desinger
WHERE code = @code;

SET @schema = REPLACE(@schema, N'{ "field": "dept_id", "title": "部门ID", "width": 280, "sortable": true },', N'');
SET @schema = REPLACE(@schema, N'{ "field": "dept_id", "title": "部门", "width": 280, "sortable": true },', N'');
SET @schema = REPLACE(@schema, N'{ "field": "ShiftID", "title": "班次ID", "width": 280, "sortable": true },', N'{ "field": "code_name", "title": "班次", "minWidth": 160, "sortable": false },');
SET @schema = REPLACE(@schema, N'{ "field": "ShiftID", "title": "班次", "width": 280, "sortable": true },', N'{ "field": "code_name", "title": "班次", "minWidth": 160, "sortable": false },');
SET @schema = REPLACE(@schema, N'{ "field": "code_name", "title": "班次名称", "minWidth": 160, "sortable": false },', N'');
SET @schema = REPLACE(@schema, N'{ "field": "attHolidayID", "title": "节日ID", "width": 280, "sortable": true },', N'{ "field": "attHolidayName", "title": "节日", "minWidth": 120, "sortable": false },');
SET @schema = REPLACE(@schema, N'{ "field": "attHolidayID", "title": "节日", "width": 280, "sortable": true },', N'{ "field": "attHolidayName", "title": "节日", "minWidth": 120, "sortable": false },');

UPDATE dbo.vben_entitylist_desinger
SET schema_json = @schema,
    updated_at = SYSUTCDATETIME()
WHERE code = @code;

PRINT N'[fix] vben_entitylist_desinger schema_json patched for readable columns.';
