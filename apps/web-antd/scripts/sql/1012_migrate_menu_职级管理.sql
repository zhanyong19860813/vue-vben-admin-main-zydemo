/*
  幂等迁移：在【部门岗位管理】下新增【职级管理】菜单
  要求：
  1) 列表设计器驱动（vben_entitylist_desinger）
  2) 表单设计器驱动（vben_form_desinger）
  3) API 使用完整 URL（按需求固定）
  4) 列宽按 t_set_datagrid(entity='v_t_base_rank')
*/

DECLARE @role_name NVARCHAR(50) = N'系统管理员';
DECLARE @role_id UNIQUEIDENTIFIER;
SELECT TOP 1 @role_id = id FROM dbo.vben_role WHERE name = @role_name;
IF @role_id IS NULL
BEGIN
  RAISERROR(N'Role not found: %s', 16, 1, @role_name);
  RETURN;
END

DECLARE @parent_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000120'; -- 部门岗位管理
DECLARE @rank_menu_id UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000122';   -- 职级管理

/* 1) 菜单 */
IF NOT EXISTS (SELECT 1 FROM dbo.vben_menus_new WHERE id = @rank_menu_id)
BEGIN
  INSERT INTO dbo.vben_menus_new
    (id, name, path, component, meta, parent_id, status, type, sort)
  VALUES
    (
      @rank_menu_id,
      N'职级管理',
      N'/dept-post/rank',
      N'EntityList/entityListFromDesigner',
      N'{"icon":"mdi:format-list-numbered","title":"职级管理","query":{"entityname":"hr_base_rank_list","menuid":"A1000001-0001-4001-8001-000000000122"}}',
      @parent_menu_id,
      1,
      N'menu',
      122
    );
END
ELSE
BEGIN
  UPDATE dbo.vben_menus_new
  SET name = N'职级管理',
      path = N'/dept-post/rank',
      component = N'EntityList/entityListFromDesigner',
      meta = N'{"icon":"mdi:format-list-numbered","title":"职级管理","query":{"entityname":"hr_base_rank_list","menuid":"A1000001-0001-4001-8001-000000000122"}}',
      parent_id = @parent_menu_id,
      status = 1,
      type = N'menu',
      sort = ISNULL(sort, 122)
  WHERE id = @rank_menu_id;
END

/* 2) 菜单授权 */
DELETE FROM dbo.vben_t_sys_role_menus
WHERE role_id = @role_id AND menus_id = @rank_menu_id;

INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id)
VALUES (NEWID(), @role_id, @rank_menu_id);

/* 3) 按钮授权 */
DECLARE @action_keys TABLE(action_key NVARCHAR(50), label NVARCHAR(50), sort INT, requires_selection BIT, button_type NVARCHAR(20), form_code NVARCHAR(100));
INSERT INTO @action_keys(action_key, label, sort, requires_selection, button_type, form_code) VALUES
  (N'add',            N'新增', 10, 0, N'primary', N'hr_base_rank_add'),
  (N'edit',           N'修改', 20, 1, N'default', N'hr_base_rank_edit'),
  (N'deleteSelected', N'删除', 30, 1, N'danger',  NULL),
  (N'reload',         N'刷新', 40, 0, N'default', NULL);

DELETE rma
FROM dbo.vben_t_sys_role_menu_actions rma
JOIN dbo.vben_menu_actions ma ON ma.id = rma.menu_action_id
WHERE ma.menu_id = @rank_menu_id
  AND ma.action_key IN (SELECT action_key FROM @action_keys);

DELETE FROM dbo.vben_menu_actions
WHERE menu_id = @rank_menu_id
  AND action_key IN (SELECT action_key FROM @action_keys);

INSERT INTO dbo.vben_menu_actions
  (id, menu_id, action_key, label, button_type, action, confirm_text, sort, status, form_code, requires_selection)
SELECT
  NEWID(),
  @rank_menu_id,
  k.action_key,
  k.label,
  k.button_type,
  k.action_key,
  CASE WHEN k.action_key = N'deleteSelected' THEN N'已选择记录,确认删除?' ELSE NULL END,
  k.sort,
  1,
  k.form_code,
  k.requires_selection
FROM @action_keys k;

INSERT INTO dbo.vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status)
SELECT NEWID(), @role_id, ma.id, @rank_menu_id, 1
FROM dbo.vben_menu_actions ma
WHERE ma.menu_id = @rank_menu_id
  AND ma.action_key IN (SELECT action_key FROM @action_keys);

/* 4) 列表设计器配置 */
DECLARE @list_id UNIQUEIDENTIFIER;
SELECT TOP 1 @list_id = id
FROM dbo.vben_entitylist_desinger
WHERE code = N'hr_base_rank_list'
ORDER BY updated_at DESC;

DECLARE @list_schema NVARCHAR(MAX) = N'{
  "title":"职级管理",
  "tableName":"v_t_base_rank",
  "primaryKey":"id",
  "deleteEntityName":"t_base_rank",
  "saveEntityName":"t_base_rank",
  "toolbar":{
    "actions":[
      {"key":"add","label":"新增","type":"primary","action":"add","form_code":"hr_base_rank_add"},
      {"key":"edit","label":"修改","action":"edit","requiresSelection":true,"form_code":"hr_base_rank_edit"},
      {"key":"deleteSelected","label":"删除","action":"deleteSelected","requiresSelection":true},
      {"key":"reload","label":"刷新","type":"primary","action":"reload"}
    ]
  },
  "form":{
    "collapsed":false,
    "showCollapseButton":true,
    "schema":[
      {"component":"Input","fieldName":"name","label":"职级名称","componentProps":{"allowClear":true}}
    ]
  },
  "grid":{
    "columns":[
      {"type":"checkbox","width":50},
      {"type":"seq","width":50},
      {"field":"id","title":"id","width":50,"sortable":true,"visible":false},
      {"field":"name","title":"职级名称","width":255,"sortable":true},
      {"field":"operator","title":"操作人","width":50,"sortable":true},
      {"field":"operationTime","title":"操作时间","width":50,"sortable":true}
    ],
    "pagerConfig":{"enabled":true,"pageSize":20},
    "sortConfig":{"remote":true,"defaultSort":{"field":"id","order":"asc"}}
  },
  "api":{
    "query":"http://127.0.0.1:5155/api/DynamicQueryBeta/queryforvben",
    "delete":"http://127.0.0.1:5155/api/DataBatchDelete/BatchDelete",
    "export":"http://127.0.0.1:5155/api/DynamicQueryBeta/ExportExcel"
  }
}';

IF @list_id IS NULL
BEGIN
  INSERT INTO dbo.vben_entitylist_desinger (id, code, title, table_name, schema_json, created_at, updated_at)
  VALUES (NEWID(), N'hr_base_rank_list', N'职级管理', N'v_t_base_rank', @list_schema, GETDATE(), GETDATE());
END
ELSE
BEGIN
  UPDATE dbo.vben_entitylist_desinger
  SET title = N'职级管理',
      table_name = N'v_t_base_rank',
      schema_json = @list_schema,
      updated_at = GETDATE()
  WHERE id = @list_id;
END

/* 5) 表单设计器：新增 */
DECLARE @form_add_id UNIQUEIDENTIFIER;
SELECT TOP 1 @form_add_id = id
FROM dbo.vben_form_desinger
WHERE code = N'hr_base_rank_add'
ORDER BY updated_at DESC;

DECLARE @form_add_schema NVARCHAR(MAX) = N'{
  "layout":{"cols":1,"labelWidth":110,"labelAlign":"right"},
  "schema":[
    {"component":"Input","fieldName":"id","label":"id","dependencies":{"if":false}},
    {"component":"Input","fieldName":"name","label":"职级名称","required":true,"componentProps":{"allowClear":true}},
    {"component":"Input","fieldName":"operator","label":"操作人","componentProps":{"disabled":true}},
    {"component":"Input","fieldName":"operationTime","label":"操作时间","componentProps":{"disabled":true}},
    {"component":"Input","fieldName":"state","label":"state","dependencies":{"if":false}}
  ]
}';

IF @form_add_id IS NULL
BEGIN
  INSERT INTO dbo.vben_form_desinger (id, code, title, schema_json, created_at, updated_at)
  VALUES (NEWID(), N'hr_base_rank_add', N'职级新增', @form_add_schema, GETDATE(), GETDATE());
END
ELSE
BEGIN
  UPDATE dbo.vben_form_desinger
  SET title = N'职级新增',
      schema_json = @form_add_schema,
      updated_at = GETDATE()
  WHERE id = @form_add_id;
END

/* 6) 表单设计器：修改 */
DECLARE @form_edit_id UNIQUEIDENTIFIER;
SELECT TOP 1 @form_edit_id = id
FROM dbo.vben_form_desinger
WHERE code = N'hr_base_rank_edit'
ORDER BY updated_at DESC;

DECLARE @form_edit_schema NVARCHAR(MAX) = N'{
  "layout":{"cols":1,"labelWidth":110,"labelAlign":"right"},
  "schema":[
    {"component":"Input","fieldName":"id","label":"id","dependencies":{"if":false}},
    {"component":"Input","fieldName":"name","label":"职级名称","required":true,"componentProps":{"allowClear":true}},
    {"component":"Input","fieldName":"operator","label":"操作人","componentProps":{"disabled":true}},
    {"component":"Input","fieldName":"operationTime","label":"操作时间","componentProps":{"disabled":true}},
    {"component":"Input","fieldName":"state","label":"state","dependencies":{"if":false}}
  ]
}';

IF @form_edit_id IS NULL
BEGIN
  INSERT INTO dbo.vben_form_desinger (id, code, title, schema_json, created_at, updated_at)
  VALUES (NEWID(), N'hr_base_rank_edit', N'职级修改', @form_edit_schema, GETDATE(), GETDATE());
END
ELSE
BEGIN
  UPDATE dbo.vben_form_desinger
  SET title = N'职级修改',
      schema_json = @form_edit_schema,
      updated_at = GETDATE()
  WHERE id = @form_edit_id;
END

PRINT N'OK: 职级管理菜单 + 列表设计器 + 表单设计器 已迁移。';

