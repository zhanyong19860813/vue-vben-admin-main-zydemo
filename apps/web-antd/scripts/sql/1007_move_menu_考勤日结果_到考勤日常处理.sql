/*
  [1007] 移动菜单：将「考勤日结果」挂到「考勤日常处理」下

  【优先】请直接执行 1008_migrate_full_考勤日结果.sql：固定 GUID + 列表设计器 + 权限，并自动删掉指向
  v_att_lst_DayResult 的旧叶子，无需改脚本。

  本文件仅保留：已有特殊菜单 id、且不想用 1008 全量重插时的「手工移动」兜底。

  自动识别（按顺序，找到即停）：
    0) @leaf_id_override 非空且存在于 vben_menus_new
    1) name = N'考勤日结果'
    2) name LIKE N'%考勤日结果%'
    3) meta 中含 v_att_lst_DayResult（大小写不敏感）
    4) meta 中含 DayResult 且 path 以 /attendance 开头（避免误匹配其它模块）
    5) vben_entitylist_desinger.code = v_att_lst_DayResult，且菜单 meta 中含该 code

  修改内容：
    - parent_id → 考勤日常处理 mid（A1000001-0001-4001-8001-000000000030）
    - path → /attendance/daily/day-result
    - sort → 11（可改 @new_sort）
    - meta：补齐 title / query.menuid / query.entityname / icon

  前置：已存在父菜单「考勤日常处理」（1002）

  幂等：可重复执行。
*/

SET NOCOUNT ON;

/* ========== 自动匹配不到时：把 NULL 改成你的叶子菜单 id ========== */
DECLARE @leaf_id_override UNIQUEIDENTIFIER = NULL;
/* 例：DECLARE @leaf_id_override UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-0000000000XX'; */

DECLARE @mid_daily UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000030';
DECLARE @new_path NVARCHAR(255) = N'/attendance/daily/day-result';
DECLARE @new_sort INT = 11;
DECLARE @entity_code NVARCHAR(200) = N'v_att_lst_DayResult';

IF NOT EXISTS (SELECT 1 FROM dbo.vben_menus_new WHERE id = @mid_daily)
BEGIN
  RAISERROR(N'父菜单不存在：考勤日常处理（请先执行 1002_migrate_full_刷卡资料查询.sql）。', 16, 1);
  RETURN;
END

DECLARE @leaf_id UNIQUEIDENTIFIER;

IF @leaf_id_override IS NOT NULL
BEGIN
  SELECT @leaf_id = id
  FROM dbo.vben_menus_new
  WHERE id = @leaf_id_override;

  IF @leaf_id IS NULL
  BEGIN
    RAISERROR(N'@leaf_id_override 在 vben_menus_new 中不存在，请核对 GUID。', 16, 1);
    RETURN;
  END
END
ELSE
BEGIN
  SELECT @leaf_id = id
  FROM dbo.vben_menus_new
  WHERE name = N'考勤日结果';

  IF @leaf_id IS NULL
    SELECT TOP 1 @leaf_id = id
    FROM dbo.vben_menus_new
    WHERE type = N'menu'
      AND name LIKE N'%考勤日结果%'
    ORDER BY name;

  IF @leaf_id IS NULL
    SELECT TOP 1 @leaf_id = id
    FROM dbo.vben_menus_new
    WHERE meta IS NOT NULL
      AND UPPER(CAST(meta AS NVARCHAR(MAX))) LIKE N'%V_ATT_LST_DAYRESULT%'
    ORDER BY name;

  IF @leaf_id IS NULL
    SELECT TOP 1 @leaf_id = id
    FROM dbo.vben_menus_new
    WHERE meta IS NOT NULL
      AND UPPER(CAST(meta AS NVARCHAR(MAX))) LIKE N'%DAYRESULT%'
      AND path IS NOT NULL
      AND path LIKE N'/attendance%'
    ORDER BY name;

  IF @leaf_id IS NULL
    SELECT TOP 1 @leaf_id = m.id
    FROM dbo.vben_menus_new AS m
    INNER JOIN dbo.vben_entitylist_desinger AS e
      ON e.code = @entity_code
    WHERE m.meta IS NOT NULL
      AND CHARINDEX(e.code, CAST(m.meta AS NVARCHAR(MAX)), 1) > 0
    ORDER BY m.name;
END

IF @leaf_id IS NULL
BEGIN
  PRINT N'';
  PRINT N'========== 未自动匹配到菜单，请从下列候选中选 id，填到脚本 @leaf_id_override 后重跑 ==========';
  SELECT
    id,
    name,
    path,
    parent_id,
    sort,
    LEFT(CAST(meta AS NVARCHAR(MAX)), 280) AS meta_snip
  FROM dbo.vben_menus_new
  WHERE type = N'menu'
    AND (
      name LIKE N'%日结果%'
      OR name LIKE N'%DayResult%'
      OR name LIKE N'%考勤日%'
      OR (meta IS NOT NULL AND UPPER(CAST(meta AS NVARCHAR(MAX))) LIKE N'%DAYRESULT%')
    )
  ORDER BY name;

  PRINT N'';
  PRINT N'若仍没有：执行 SELECT id, code, title FROM vben_entitylist_desinger WHERE code LIKE N''%DayResult%''; 再按 entityname 在菜单 meta 里搜。';

  RAISERROR(N'未找到「考勤日结果」菜单：请查看上一结果集，把正确叶子 id 填入脚本顶部 @leaf_id_override 后重跑。', 16, 1);
  RETURN;
END

DECLARE @old_parent UNIQUEIDENTIFIER;
DECLARE @old_path NVARCHAR(255);
DECLARE @meta_raw NVARCHAR(MAX);

SELECT @old_parent = parent_id, @old_path = path, @meta_raw = CAST(meta AS NVARCHAR(MAX))
FROM dbo.vben_menus_new
WHERE id = @leaf_id;

IF @meta_raw IS NULL OR LTRIM(RTRIM(@meta_raw)) = N''
  SET @meta_raw = N'{}';

SET @meta_raw = JSON_MODIFY(@meta_raw, N'$.title', N'考勤日结果');
SET @meta_raw = JSON_MODIFY(@meta_raw, N'$.query.menuid', CAST(@leaf_id AS NVARCHAR(36)));

IF JSON_VALUE(@meta_raw, N'$.query.entityname') IS NULL
  SET @meta_raw = JSON_MODIFY(@meta_raw, N'$.query.entityname', @entity_code);

IF JSON_VALUE(@meta_raw, N'$.icon') IS NULL
  SET @meta_raw = JSON_MODIFY(@meta_raw, N'$.icon', N'lucide:calendar-check');

UPDATE dbo.vben_menus_new
SET
  parent_id = @mid_daily,
  path = @new_path,
  sort = @new_sort,
  meta = @meta_raw
WHERE id = @leaf_id;

PRINT N'OK: [1007] 考勤日结果 已移动到「考勤日常处理」下。'
  + N' leaf=' + CONVERT(NVARCHAR(36), @leaf_id)
  + N' 原parent=' + ISNULL(CONVERT(NVARCHAR(36), @old_parent), N'NULL')
  + N' 原path=' + ISNULL(@old_path, N'NULL')
  + N' 新path=' + @new_path;
