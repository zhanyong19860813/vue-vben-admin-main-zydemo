/*
  1023：兼容旧版 WorkflowController 建过的同名表（wf_instance / wf_task）
  目标：在不删历史数据前提下，将表补齐到 1020 runtime 所需字段。

  使用方式：
  1) 在 SQL Server 执行本脚本（可重复执行）
  2) 重启 StoneApi
  3) 再访问 /api/workflow-engine/runtime/todo
*/

SET NOCOUNT ON;
GO

/* ---------------------------------------------------------
   A. wf_instance：补列 + 旧状态字符串转 tinyint
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.wf_instance', 'U') IS NOT NULL
BEGIN
  IF COL_LENGTH('dbo.wf_instance', 'instance_no') IS NULL
    ALTER TABLE dbo.wf_instance ADD instance_no NVARCHAR(64) NULL;

  IF COL_LENGTH('dbo.wf_instance', 'process_def_id') IS NULL
    ALTER TABLE dbo.wf_instance ADD process_def_id UNIQUEIDENTIFIER NULL;

  IF COL_LENGTH('dbo.wf_instance', 'process_def_ver_id') IS NULL
    ALTER TABLE dbo.wf_instance ADD process_def_ver_id UNIQUEIDENTIFIER NULL;

  IF COL_LENGTH('dbo.wf_instance', 'title') IS NULL
    ALTER TABLE dbo.wf_instance ADD title NVARCHAR(256) NULL;

  IF COL_LENGTH('dbo.wf_instance', 'starter_user_id') IS NULL
    ALTER TABLE dbo.wf_instance ADD starter_user_id NVARCHAR(64) NULL;

  IF COL_LENGTH('dbo.wf_instance', 'starter_dept_id') IS NULL
    ALTER TABLE dbo.wf_instance ADD starter_dept_id NVARCHAR(64) NULL;

  IF COL_LENGTH('dbo.wf_instance', 'current_node_ids') IS NULL
    ALTER TABLE dbo.wf_instance ADD current_node_ids NVARCHAR(512) NULL;

  IF COL_LENGTH('dbo.wf_instance', 'started_at') IS NULL
    ALTER TABLE dbo.wf_instance ADD started_at DATETIME2(3) NULL;

  IF COL_LENGTH('dbo.wf_instance', 'ended_at') IS NULL
    ALTER TABLE dbo.wf_instance ADD ended_at DATETIME2(3) NULL;
END
GO

IF OBJECT_ID('dbo.wf_instance', 'U') IS NOT NULL
BEGIN
  -- 从旧列回填
  UPDATE dbo.wf_instance
  SET
    instance_no = ISNULL(NULLIF(instance_no, ''), CONCAT('WFI-LEGACY-', CONVERT(NVARCHAR(36), id))),
    title = ISNULL(NULLIF(title, ''), process_name),
    starter_user_id = ISNULL(NULLIF(starter_user_id, ''), initiator),
    current_node_ids = ISNULL(NULLIF(current_node_ids, ''), current_node_id),
    started_at = ISNULL(started_at, TRY_CONVERT(DATETIME2(3), created_at))
  WHERE 1 = 1;

  -- 通过 process_code + definition_version 尽量回填新外键
  UPDATE i
  SET i.process_def_id = d.id
  FROM dbo.wf_instance i
  JOIN dbo.wf_process_def d ON d.process_code = i.process_code
  WHERE i.process_def_id IS NULL;

  UPDATE i
  SET i.process_def_ver_id = v.id
  FROM dbo.wf_instance i
  JOIN dbo.wf_process_def d ON d.id = i.process_def_id
  JOIN dbo.wf_process_def_ver v
    ON v.process_def_id = d.id
   AND v.version_no = TRY_CONVERT(INT, i.definition_version)
  WHERE i.process_def_ver_id IS NULL;
END
GO

IF OBJECT_ID('dbo.wf_instance', 'U') IS NOT NULL
   AND EXISTS (
     SELECT 1
     FROM sys.columns c
     JOIN sys.types t ON c.user_type_id = t.user_type_id
     WHERE c.object_id = OBJECT_ID('dbo.wf_instance')
       AND c.name = 'status'
       AND t.name IN ('nvarchar', 'varchar', 'nchar', 'char')
   )
BEGIN
  IF COL_LENGTH('dbo.wf_instance', 'status_new') IS NULL
    ALTER TABLE dbo.wf_instance ADD status_new TINYINT NULL;

  EXEC sp_executesql N'
    UPDATE dbo.wf_instance
    SET status_new =
      CASE LOWER(LTRIM(RTRIM(CAST(status AS NVARCHAR(64)))))
        WHEN ''running'' THEN 0
        WHEN ''pending'' THEN 0
        WHEN ''todo'' THEN 0
        WHEN ''completed'' THEN 1
        WHEN ''done'' THEN 1
        WHEN ''terminated'' THEN 2
        WHEN ''rejected'' THEN 2
        WHEN ''withdrawn'' THEN 3
        ELSE TRY_CONVERT(TINYINT, status)
      END;';

  EXEC sp_executesql N'
    UPDATE dbo.wf_instance
    SET status_new = ISNULL(status_new, 0);';

  DECLARE @drop_idx_instance_sql NVARCHAR(MAX) = N'';
  SELECT @drop_idx_instance_sql = STRING_AGG(
      N'DROP INDEX ' + QUOTENAME(i.name) + N' ON dbo.wf_instance;',
      CHAR(10)
    )
  FROM sys.indexes i
  JOIN sys.index_columns ic
    ON i.object_id = ic.object_id
   AND i.index_id = ic.index_id
  JOIN sys.columns c
    ON c.object_id = ic.object_id
   AND c.column_id = ic.column_id
  WHERE i.object_id = OBJECT_ID('dbo.wf_instance')
    AND c.name = 'status'
    AND i.is_primary_key = 0
    AND i.is_unique_constraint = 0
    AND i.is_hypothetical = 0;
  IF ISNULL(@drop_idx_instance_sql, N'') <> N''
    EXEC sp_executesql @drop_idx_instance_sql;

  ALTER TABLE dbo.wf_instance DROP COLUMN status;
  EXEC sp_rename 'dbo.wf_instance.status_new', 'status', 'COLUMN';
END
GO

/* ---------------------------------------------------------
   B. wf_task：补列 + assignee/status 兼容
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.wf_task', 'U') IS NOT NULL
BEGIN
  IF COL_LENGTH('dbo.wf_task', 'task_no') IS NULL
    ALTER TABLE dbo.wf_task ADD task_no NVARCHAR(64) NULL;

  IF COL_LENGTH('dbo.wf_task', 'assignee_user_id') IS NULL
    ALTER TABLE dbo.wf_task ADD assignee_user_id NVARCHAR(64) NULL;

  IF COL_LENGTH('dbo.wf_task', 'assignee_name') IS NULL
    ALTER TABLE dbo.wf_task ADD assignee_name NVARCHAR(64) NULL;

  IF COL_LENGTH('dbo.wf_task', 'task_type') IS NULL
    ALTER TABLE dbo.wf_task ADD task_type TINYINT NULL;

  IF COL_LENGTH('dbo.wf_task', 'sign_mode') IS NULL
    ALTER TABLE dbo.wf_task ADD sign_mode NVARCHAR(16) NULL;

  IF COL_LENGTH('dbo.wf_task', 'batch_no') IS NULL
    ALTER TABLE dbo.wf_task ADD batch_no INT NULL;

  IF COL_LENGTH('dbo.wf_task', 'source_task_id') IS NULL
    ALTER TABLE dbo.wf_task ADD source_task_id UNIQUEIDENTIFIER NULL;

  IF COL_LENGTH('dbo.wf_task', 'tenant_id') IS NULL
    ALTER TABLE dbo.wf_task ADD tenant_id UNIQUEIDENTIFIER NULL;

  IF COL_LENGTH('dbo.wf_task', 'received_at') IS NULL
    ALTER TABLE dbo.wf_task ADD received_at DATETIME2(3) NULL;

  IF COL_LENGTH('dbo.wf_task', 'completed_at') IS NULL
    ALTER TABLE dbo.wf_task ADD completed_at DATETIME2(3) NULL;

  IF COL_LENGTH('dbo.wf_task', 'due_at') IS NULL
    ALTER TABLE dbo.wf_task ADD due_at DATETIME2(3) NULL;

  IF COL_LENGTH('dbo.wf_task', 'updated_at') IS NULL
    ALTER TABLE dbo.wf_task ADD updated_at DATETIME2(3) NULL;
END
GO

IF OBJECT_ID('dbo.wf_task', 'U') IS NOT NULL
BEGIN
  UPDATE dbo.wf_task
  SET
    task_no = ISNULL(NULLIF(task_no, ''), CONCAT('WFT-LEGACY-', CONVERT(NVARCHAR(36), id))),
    assignee_user_id = ISNULL(NULLIF(assignee_user_id, ''), assignee),
    assignee_name = ISNULL(NULLIF(assignee_name, ''), assignee),
    task_type = ISNULL(task_type, 1),
    received_at = ISNULL(received_at, TRY_CONVERT(DATETIME2(3), created_at)),
    updated_at = ISNULL(updated_at, TRY_CONVERT(DATETIME2(3), created_at));
END
GO

IF OBJECT_ID('dbo.wf_task', 'U') IS NOT NULL
   AND EXISTS (
     SELECT 1
     FROM sys.columns c
     JOIN sys.types t ON c.user_type_id = t.user_type_id
     WHERE c.object_id = OBJECT_ID('dbo.wf_task')
       AND c.name = 'status'
       AND t.name IN ('nvarchar', 'varchar', 'nchar', 'char')
   )
BEGIN
  IF COL_LENGTH('dbo.wf_task', 'status_new') IS NULL
    ALTER TABLE dbo.wf_task ADD status_new TINYINT NULL;

  EXEC sp_executesql N'
    UPDATE dbo.wf_task
    SET status_new =
      CASE LOWER(LTRIM(RTRIM(CAST(status AS NVARCHAR(64)))))
        WHEN ''pending'' THEN 0
        WHEN ''todo'' THEN 0
        WHEN ''wait'' THEN 0
        WHEN ''approved'' THEN 1
        WHEN ''done'' THEN 1
        WHEN ''rejected'' THEN 2
        WHEN ''transfer'' THEN 3
        WHEN ''cancel'' THEN 4
        WHEN ''timeout'' THEN 5
        ELSE TRY_CONVERT(TINYINT, status)
      END;';

  EXEC sp_executesql N'
    UPDATE dbo.wf_task
    SET status_new = ISNULL(status_new, 0);';

  DECLARE @drop_idx_task_sql NVARCHAR(MAX) = N'';
  SELECT @drop_idx_task_sql = STRING_AGG(
      N'DROP INDEX ' + QUOTENAME(i.name) + N' ON dbo.wf_task;',
      CHAR(10)
    )
  FROM sys.indexes i
  JOIN sys.index_columns ic
    ON i.object_id = ic.object_id
   AND i.index_id = ic.index_id
  JOIN sys.columns c
    ON c.object_id = ic.object_id
   AND c.column_id = ic.column_id
  WHERE i.object_id = OBJECT_ID('dbo.wf_task')
    AND c.name = 'status'
    AND i.is_primary_key = 0
    AND i.is_unique_constraint = 0
    AND i.is_hypothetical = 0;
  IF ISNULL(@drop_idx_task_sql, N'') <> N''
    EXEC sp_executesql @drop_idx_task_sql;

  ALTER TABLE dbo.wf_task DROP COLUMN status;
  EXEC sp_rename 'dbo.wf_task.status_new', 'status', 'COLUMN';
END
GO

/* ---------------------------------------------------------
   C. 索引（不存在才创建）
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.wf_instance', 'U') IS NOT NULL
   AND NOT EXISTS (
     SELECT 1 FROM sys.indexes
     WHERE object_id = OBJECT_ID('dbo.wf_instance')
       AND name = 'IX_wf_instance_starter_status'
   )
BEGIN
  CREATE INDEX IX_wf_instance_starter_status
    ON dbo.wf_instance(starter_user_id, status, created_at DESC);
END
GO

IF OBJECT_ID('dbo.wf_task', 'U') IS NOT NULL
   AND NOT EXISTS (
     SELECT 1 FROM sys.indexes
     WHERE object_id = OBJECT_ID('dbo.wf_task')
       AND name = 'IX_wf_task_assignee_status'
   )
BEGIN
  CREATE INDEX IX_wf_task_assignee_status
    ON dbo.wf_task(assignee_user_id, status, received_at DESC);
END
GO

PRINT '1023 migration done. Please restart StoneApi.';
GO

