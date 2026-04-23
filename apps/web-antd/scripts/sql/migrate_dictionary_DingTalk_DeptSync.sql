/*
  =============================================================================
  数据字典：钉钉部门同步（编码 DingTalk_DeptSync）
  =============================================================================
  【重要】新系统「数据字典」页面与 DataSave 使用的是：
        vben_t_base_dictionary 、 vben_t_base_dictionary_detail
        后端 DingTalkDeptSync 与此保持一致，读上述 vben 表。

        历史库中可能另有 t_base_dictionary / t_base_dictionary_detail（HR 等），
        本脚本会同时尽量写入/补全 vben（必做）与 t_base（可选镜像，便于旧脚本查询）。

  明细 name（勿改）：enabled, corp_id, corp_secret, dup_weeks

  【推荐 · 方式 A — 与开放平台新文档一致】
    corp_id    → 填应用「凭证与基础信息」中的 Client ID（原 AppKey，如 dingxxxx）
    corp_secret → 填同一应用的 Client Secret（原 AppSecret）
    后端 gettoken 优先走 appkey+appsecret；亦兼容旧文档「企业 CorpId + 应用 AppSecret」。

  父节点（vben）：自动挂到与「性别」相同的 parent_id（一般为「系统字典」）。
  父节点（t_base）：name=系统字典 且 parent_id IS NULL。

  幂等：可重复执行；已有明细不覆盖 value。
  =============================================================================
*/

SET NOCOUNT ON;

/* ---------- vben：与界面一致 ---------- */
DECLARE @vbenParent UNIQUEIDENTIFIER;

SELECT TOP 1 @vbenParent = parent_id
FROM dbo.vben_t_base_dictionary WITH (NOLOCK)
WHERE name = N'性别' AND parent_id IS NOT NULL;

IF @vbenParent IS NULL
  SELECT TOP 1 @vbenParent = id
  FROM dbo.vben_t_base_dictionary WITH (NOLOCK)
  WHERE name = N'系统字典'
    AND (parent_id IS NULL OR parent_id = CAST(N'00000000-0000-0000-0000-000000000000' AS UNIQUEIDENTIFIER));

IF @vbenParent IS NULL
BEGIN
  RAISERROR(N'vben_t_base_dictionary 中未找到「性别」或根级「系统字典」，无法创建钉钉字典分类。', 16, 1);
  RETURN;
END

/* ---------- t_base：可选 ---------- */
DECLARE @parentT UNIQUEIDENTIFIER =
(
  SELECT TOP 1 id
  FROM dbo.t_base_dictionary WITH (NOLOCK)
  WHERE name = N'系统字典' AND parent_id IS NULL
);

DECLARE @did UNIQUEIDENTIFIER;

SELECT @did = id FROM dbo.vben_t_base_dictionary WITH (NOLOCK) WHERE code = N'DingTalk_DeptSync';
IF @did IS NULL
  SELECT @did = id FROM dbo.t_base_dictionary WITH (NOLOCK) WHERE code = N'DingTalk_DeptSync';
IF @did IS NULL
  SET @did = NEWID();

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary WITH (NOLOCK) WHERE code = N'DingTalk_DeptSync')
BEGIN
  INSERT INTO dbo.vben_t_base_dictionary (id, name, code, data_type, description, parent_id, add_time, sort)
  VALUES
  (
    @did,
    N'钉钉部门同步',
    N'DingTalk_DeptSync',
    NULL,
    N'部门管理「同步到钉钉」：enabled / corp_id / corp_secret（后端 DingTalkDeptSync）',
    @vbenParent,
    GETDATE(),
    0
  );
END
ELSE
  SELECT @did = id FROM dbo.vben_t_base_dictionary WITH (NOLOCK) WHERE code = N'DingTalk_DeptSync';

IF @parentT IS NOT NULL
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary WITH (NOLOCK) WHERE code = N'DingTalk_DeptSync')
  BEGIN
    INSERT INTO dbo.t_base_dictionary (id, name, code, data_type, description, parent_id, add_time, sort)
    VALUES
    (
      @did,
      N'钉钉部门同步',
      N'DingTalk_DeptSync',
      NULL,
      N'与 vben 字典 DingTalk_DeptSync 同源（可选镜像）',
      @parentT,
      GETDATE(),
      0
    );
  END
END

/* ---- 明细：vben ---- */
IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @did AND name = N'enabled')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @did, N'enabled', N'1', N'1=启用同步，0=关闭', 1, GETDATE());

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @did AND name = N'corp_id')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @did, N'corp_id', N'', N'方式A推荐：应用 Client ID；兼容填企业 CorpId', 2, GETDATE());

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @did AND name = N'corp_secret')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @did, N'corp_secret', N'', N'方式A：应用 Client Secret（勿用首页 API Token）', 3, GETDATE());

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @did AND name = N'dup_weeks')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @did, N'dup_weeks', N'2', N'可选，兼容说明', 4, GETDATE());

/* ---- 明细：t_base（可选镜像）---- */
IF @parentT IS NOT NULL
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @did AND name = N'enabled')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @did, N'enabled', N'1', N'1=启用同步，0=关闭', 1);

  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @did AND name = N'corp_id')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @did, N'corp_id', N'', N'方式A推荐：应用 Client ID；兼容企业 CorpId', 2);

  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @did AND name = N'corp_secret')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @did, N'corp_secret', N'', N'方式A：Client Secret', 3);

  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @did AND name = N'dup_weeks')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @did, N'dup_weeks', N'2', N'可选，兼容说明', 4);
END

PRINT N'OK: DingTalk_DeptSync 已写入 vben（界面可见）；t_base 已镜像（若存在系统字典父节点）。请按方式 A 填 Client ID + Client Secret。';

/*
  =============================================================================
  填值（改 vben 即可，接口读 vben；勿把密钥提交 Git）
  =============================================================================

UPDATE d
SET d.value = N'在此填写 Client ID（应用凭证页）'
FROM dbo.vben_t_base_dictionary_detail AS d
INNER JOIN dbo.vben_t_base_dictionary AS m ON m.id = d.dictionary_id
WHERE m.code = N'DingTalk_DeptSync' AND d.name = N'corp_id';

UPDATE d
SET d.value = N'在此填写 Client Secret（应用凭证页）'
FROM dbo.vben_t_base_dictionary_detail AS d
INNER JOIN dbo.vben_t_base_dictionary AS m ON m.id = d.dictionary_id
WHERE m.code = N'DingTalk_DeptSync' AND d.name = N'corp_secret';

  =============================================================================
*/
