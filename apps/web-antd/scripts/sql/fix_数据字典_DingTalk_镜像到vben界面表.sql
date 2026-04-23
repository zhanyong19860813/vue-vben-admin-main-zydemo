/*
  问题：数据字典页面读的是 vben_t_base_dictionary / vben_t_base_dictionary_detail，
        若只在 t_base_dictionary 里插了「钉钉部门同步」，界面树不会出现。

  本脚本：把 code=DingTalk_DeptSync 的分类及明细，从 t_base_* 复制到 vben_*（主键 id 与 dictionary_id 保持一致，便于与后端一致）。

  幂等：已存在 vben 同名分类（同 code）则跳过主表；明细按 dictionary_id+name 去重补全。

  执行后：刷新「数据字典」页面即可看到「钉钉部门同步」；后端 DingTalkDeptSync 已改为读 vben 表。
*/

SET NOCOUNT ON;

DECLARE @did UNIQUEIDENTIFIER =
(
  SELECT TOP 1 id
  FROM dbo.t_base_dictionary WITH (NOLOCK)
  WHERE code = N'DingTalk_DeptSync'
);

IF @did IS NULL
BEGIN
  RAISERROR(N'未在 t_base_dictionary 找到 DingTalk_DeptSync。请先执行 migrate_dictionary_DingTalk_DeptSync.sql 或手工插入。', 16, 1);
  RETURN;
END

/* 与「性别」同一父节点 = 界面里「系统字典」下的分类 */
DECLARE @vbenParent UNIQUEIDENTIFIER =
(
  SELECT TOP 1 parent_id
  FROM dbo.vben_t_base_dictionary WITH (NOLOCK)
  WHERE name = N'性别' AND parent_id IS NOT NULL
);

IF @vbenParent IS NULL
  SELECT TOP 1 @vbenParent = id
  FROM dbo.vben_t_base_dictionary WITH (NOLOCK)
  WHERE name = N'系统字典'
    AND (parent_id IS NULL OR parent_id = CAST(N'00000000-0000-0000-0000-000000000000' AS UNIQUEIDENTIFIER));

IF @vbenParent IS NULL
BEGIN
  RAISERROR(N'无法确定 vben 侧父节点：vben_t_base_dictionary 中需存在「性别」或根级「系统字典」。', 16, 1);
  RETURN;
END

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary WITH (NOLOCK) WHERE id = @did)
   AND NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary WITH (NOLOCK) WHERE code = N'DingTalk_DeptSync')
BEGIN
  INSERT INTO dbo.vben_t_base_dictionary (id, name, code, data_type, description, parent_id, add_time, sort)
  SELECT t.id, t.name, t.code, t.data_type, t.description, @vbenParent, ISNULL(t.add_time, GETDATE()), ISNULL(t.sort, 0)
  FROM dbo.t_base_dictionary AS t WITH (NOLOCK)
  WHERE t.id = @did;
END

INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
SELECT NEWID(), d.dictionary_id, d.name, d.value, d.description, CAST(d.sort AS SMALLINT), GETDATE()
FROM dbo.t_base_dictionary_detail AS d WITH (NOLOCK)
WHERE d.dictionary_id = @did
  AND NOT EXISTS (
    SELECT 1
    FROM dbo.vben_t_base_dictionary_detail AS v WITH (NOLOCK)
    WHERE v.dictionary_id = @did AND v.name = d.name
  );

PRINT N'OK: 已将 DingTalk_DeptSync 镜像到 vben 表。请刷新数据字典页面。';
