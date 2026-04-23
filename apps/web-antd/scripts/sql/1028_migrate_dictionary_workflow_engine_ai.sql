/*
  =============================================================================
  数据字典：WorkflowEngine AI 配置（通义 / DeepSeek）
  =============================================================================
  目标：
    1) 在 vben_t_base_dictionary 下创建两个配置分类：
       - WorkflowEngine_Ai_Qwen
       - WorkflowEngine_Ai_DeepSeek
    2) 写入明细项（幂等，不覆盖已有 value）：
       enabled / base_url / api_key / model / timeout_seconds / system_prompt
    3) 可选镜像到 t_base_dictionary（若旧表存在“系统字典”父节点）

  用途：
    你可以在前端【数据字典】页面直接维护上述值。
    后端目前默认仍从 appsettings.json 读取；如需改为“优先读字典”可再补一版代码。
  =============================================================================
*/

SET NOCOUNT ON;

/* ---------- vben：定位父节点（与“性别”同级） ---------- */
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
  RAISERROR(N'vben_t_base_dictionary 中未找到「性别」或根级「系统字典」，无法创建 WorkflowEngine AI 字典。', 16, 1);
  RETURN;
END

/* ---------- t_base：可选镜像 ---------- */
DECLARE @parentT UNIQUEIDENTIFIER =
(
  SELECT TOP 1 id
  FROM dbo.t_base_dictionary WITH (NOLOCK)
  WHERE name = N'系统字典' AND parent_id IS NULL
);

DECLARE @didQwen UNIQUEIDENTIFIER;
DECLARE @didDeep UNIQUEIDENTIFIER;

/* ---------- 先复用已有 id（如果任一表存在） ---------- */
SELECT @didQwen = id FROM dbo.vben_t_base_dictionary WITH (NOLOCK) WHERE code = N'WorkflowEngine_Ai_Qwen';
IF @didQwen IS NULL
  SELECT @didQwen = id FROM dbo.t_base_dictionary WITH (NOLOCK) WHERE code = N'WorkflowEngine_Ai_Qwen';
IF @didQwen IS NULL SET @didQwen = NEWID();

SELECT @didDeep = id FROM dbo.vben_t_base_dictionary WITH (NOLOCK) WHERE code = N'WorkflowEngine_Ai_DeepSeek';
IF @didDeep IS NULL
  SELECT @didDeep = id FROM dbo.t_base_dictionary WITH (NOLOCK) WHERE code = N'WorkflowEngine_Ai_DeepSeek';
IF @didDeep IS NULL SET @didDeep = NEWID();

/* ---------- 创建 vben 主字典 ---------- */
IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary WITH (NOLOCK) WHERE code = N'WorkflowEngine_Ai_Qwen')
BEGIN
  INSERT INTO dbo.vben_t_base_dictionary (id, name, code, data_type, description, parent_id, add_time, sort)
  VALUES
  (
    @didQwen,
    N'流程引擎AI-通义配置',
    N'WorkflowEngine_Ai_Qwen',
    NULL,
    N'WorkflowEngine AI 提供方配置（阿里通义 OpenAI 兼容）',
    @vbenParent,
    GETDATE(),
    110
  );
END
ELSE
  SELECT @didQwen = id FROM dbo.vben_t_base_dictionary WITH (NOLOCK) WHERE code = N'WorkflowEngine_Ai_Qwen';

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary WITH (NOLOCK) WHERE code = N'WorkflowEngine_Ai_DeepSeek')
BEGIN
  INSERT INTO dbo.vben_t_base_dictionary (id, name, code, data_type, description, parent_id, add_time, sort)
  VALUES
  (
    @didDeep,
    N'流程引擎AI-DeepSeek配置',
    N'WorkflowEngine_Ai_DeepSeek',
    NULL,
    N'WorkflowEngine AI 提供方配置（DeepSeek OpenAI 兼容）',
    @vbenParent,
    GETDATE(),
    111
  );
END
ELSE
  SELECT @didDeep = id FROM dbo.vben_t_base_dictionary WITH (NOLOCK) WHERE code = N'WorkflowEngine_Ai_DeepSeek';

/* ---------- 创建 t_base 主字典（可选镜像） ---------- */
IF @parentT IS NOT NULL
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary WITH (NOLOCK) WHERE code = N'WorkflowEngine_Ai_Qwen')
  BEGIN
    INSERT INTO dbo.t_base_dictionary (id, name, code, data_type, description, parent_id, add_time, sort)
    VALUES
    (
      @didQwen,
      N'流程引擎AI-通义配置',
      N'WorkflowEngine_Ai_Qwen',
      NULL,
      N'与 vben 字典同源（可选镜像）',
      @parentT,
      GETDATE(),
      110
    );
  END

  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary WITH (NOLOCK) WHERE code = N'WorkflowEngine_Ai_DeepSeek')
  BEGIN
    INSERT INTO dbo.t_base_dictionary (id, name, code, data_type, description, parent_id, add_time, sort)
    VALUES
    (
      @didDeep,
      N'流程引擎AI-DeepSeek配置',
      N'WorkflowEngine_Ai_DeepSeek',
      NULL,
      N'与 vben 字典同源（可选镜像）',
      @parentT,
      GETDATE(),
      111
    );
  END
END

/* ---------- 明细模板：vben / t_base（通义） ---------- */
IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didQwen AND name = N'enabled')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @didQwen, N'enabled', N'1', N'1=启用，0=关闭', 1, GETDATE());

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didQwen AND name = N'base_url')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @didQwen, N'base_url', N'https://dashscope.aliyuncs.com/compatible-mode/v1', N'通义 OpenAI 兼容根地址', 2, GETDATE());

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didQwen AND name = N'api_key')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @didQwen, N'api_key', N'', N'通义 API Key（勿提交 Git）', 3, GETDATE());

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didQwen AND name = N'model')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @didQwen, N'model', N'qwen-plus', N'默认模型：qwen-plus（可改 qwen-turbo/qwen-max）', 4, GETDATE());

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didQwen AND name = N'timeout_seconds')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @didQwen, N'timeout_seconds', N'45', N'请求超时秒数', 5, GETDATE());

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didQwen AND name = N'system_prompt')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @didQwen, N'system_prompt', N'', N'系统提示词（可留空）', 6, GETDATE());

IF @parentT IS NOT NULL
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didQwen AND name = N'enabled')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @didQwen, N'enabled', N'1', N'1=启用，0=关闭', 1);

  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didQwen AND name = N'base_url')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @didQwen, N'base_url', N'https://dashscope.aliyuncs.com/compatible-mode/v1', N'通义 OpenAI 兼容根地址', 2);

  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didQwen AND name = N'api_key')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @didQwen, N'api_key', N'', N'通义 API Key（勿提交 Git）', 3);

  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didQwen AND name = N'model')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @didQwen, N'model', N'qwen-plus', N'默认模型', 4);

  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didQwen AND name = N'timeout_seconds')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @didQwen, N'timeout_seconds', N'45', N'请求超时秒数', 5);

  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didQwen AND name = N'system_prompt')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @didQwen, N'system_prompt', N'', N'系统提示词（可留空）', 6);
END

/* ---------- 明细模板：vben / t_base（DeepSeek） ---------- */
IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didDeep AND name = N'enabled')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @didDeep, N'enabled', N'1', N'1=启用，0=关闭', 1, GETDATE());

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didDeep AND name = N'base_url')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @didDeep, N'base_url', N'https://api.deepseek.com/v1', N'DeepSeek OpenAI 兼容根地址', 2, GETDATE());

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didDeep AND name = N'api_key')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @didDeep, N'api_key', N'', N'DeepSeek API Key（勿提交 Git）', 3, GETDATE());

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didDeep AND name = N'model')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @didDeep, N'model', N'deepseek-chat', N'默认模型：deepseek-chat（可改 deepseek-reasoner）', 4, GETDATE());

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didDeep AND name = N'timeout_seconds')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @didDeep, N'timeout_seconds', N'45', N'请求超时秒数', 5, GETDATE());

IF NOT EXISTS (SELECT 1 FROM dbo.vben_t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didDeep AND name = N'system_prompt')
  INSERT INTO dbo.vben_t_base_dictionary_detail (id, dictionary_id, name, value, description, sort, add_time)
  VALUES (NEWID(), @didDeep, N'system_prompt', N'', N'系统提示词（可留空）', 6, GETDATE());

IF @parentT IS NOT NULL
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didDeep AND name = N'enabled')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @didDeep, N'enabled', N'1', N'1=启用，0=关闭', 1);

  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didDeep AND name = N'base_url')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @didDeep, N'base_url', N'https://api.deepseek.com/v1', N'DeepSeek OpenAI 兼容根地址', 2);

  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didDeep AND name = N'api_key')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @didDeep, N'api_key', N'', N'DeepSeek API Key（勿提交 Git）', 3);

  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didDeep AND name = N'model')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @didDeep, N'model', N'deepseek-chat', N'默认模型', 4);

  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didDeep AND name = N'timeout_seconds')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @didDeep, N'timeout_seconds', N'45', N'请求超时秒数', 5);

  IF NOT EXISTS (SELECT 1 FROM dbo.t_base_dictionary_detail WITH (NOLOCK) WHERE dictionary_id = @didDeep AND name = N'system_prompt')
    INSERT INTO dbo.t_base_dictionary_detail (id, dictionary_id, name, value, description, sort)
    VALUES (NEWID(), @didDeep, N'system_prompt', N'', N'系统提示词（可留空）', 6);
END

PRINT N'OK: WorkflowEngine_Ai_Qwen / WorkflowEngine_Ai_DeepSeek 已写入数据字典。请在字典明细里补 api_key。';

/*
  执行后你可在页面看到两个分类：
    - 流程引擎AI-通义配置
    - 流程引擎AI-DeepSeek配置
*/
