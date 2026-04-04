/*
  =============================================================================
  一键迁移模板（复制为新文件名后全文替换占位符再执行）
  占位符：
    __CODE__              列表设计器 code，与菜单 meta.query.entityname 一致
    __TITLE__             列表标题 / 菜单标题
    __TABLE_NAME__        DynamicQuery 表名或视图名
    __PRIMARY_KEY__       主键列名
    __PATH_ROOT__         一级 path，如 /migrated/module
    __PATH_MID__          二级 path
    __PATH_LEAF__         叶子 path（须全局唯一）
    __SORT_ROOT__         一级 sort
    __SORT_MID__          二级 sort
    __SORT_LEAF__         叶子 sort
    __NAME_ROOT__         一级中文名
    __NAME_MID__          二级中文名
    __SCHEMA_JSON_BODY__  从 { 后 "title" 起至 api 前为止的 JSON 片段（见下方说明）
  角色授权（与 migrate_full_假别设定.sql 一致，默认「系统管理员」）：
    DECLARE @role_id UNIQUEIDENTIFIER;
    SELECT @role_id = id FROM dbo.vben_role WHERE name = N'系统管理员';
    IF @role_id IS NULL BEGIN RAISERROR(N'未找到角色「系统管理员」', 16, 1); RETURN; END
  GUID（勿重复，整库唯一）：
    @id_list / @id_root / @id_mid / @id_leaf 四个 UNIQUEIDENTIFIER
  叶子菜单：
    component = N'/EntityList/entityListFromDesigner'
    meta 必须含 "query":{"entityname":"__CODE__","menuid":"<@id_leaf 字符串>"}
  schema_json 中 api.query 用变量 @api_query 拼接，与 migrate_full_假别设定.sql 相同。
  __SCHEMA_JSON_BODY__ 示例（不含最外层花括号，且不要含 api 节点）：
    "title":"__TITLE__","tableName":"__TABLE_NAME__","primaryKey":"__PRIMARY_KEY__",...
  =============================================================================
*/
