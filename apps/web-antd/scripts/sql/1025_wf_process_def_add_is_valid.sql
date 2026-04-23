/*
  wf_process_def：增加「是否有效」业务开关列 is_valid（与 status 草稿/发布/停用 独立）。
  可重复执行。
*/
IF OBJECT_ID('dbo.wf_process_def', 'U') IS NOT NULL
  AND COL_LENGTH('dbo.wf_process_def', 'is_valid') IS NULL
BEGIN
  ALTER TABLE dbo.wf_process_def
    ADD is_valid BIT NOT NULL CONSTRAINT DF_wf_process_def_is_valid DEFAULT (1);
END
GO
