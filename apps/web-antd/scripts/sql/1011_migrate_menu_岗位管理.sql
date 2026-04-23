/*
  幂等迁移：在【部门岗位管理】下新增【岗位管理】菜单，并写入按钮权限（系统管理员）。
  目标页面：/hr/base-duty/index（硬编码页）
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
DECLARE @leaf_menu_id   UNIQUEIDENTIFIER = 'A1000001-0001-4001-8001-000000000121'; -- 岗位管理

IF NOT EXISTS (SELECT 1 FROM dbo.vben_menus_new WHERE id = @leaf_menu_id)
BEGIN
  INSERT INTO dbo.vben_menus_new
    (id, name, path, component, meta, parent_id, status, type, sort)
  VALUES
    (
      @leaf_menu_id,
      N'岗位管理',
      N'/dept-post/duty',
      N'EntityList/entityListFromDesigner',
      N'{"icon":"mdi:badge-account-horizontal","title":"岗位管理","query":{"entityname":"hr_base_duty_list","menuid":"A1000001-0001-4001-8001-000000000121"}}',
      @parent_menu_id,
      1,
      N'menu',
      121
    );
END
ELSE
BEGIN
  UPDATE dbo.vben_menus_new
  SET name = N'岗位管理',
      path = N'/dept-post/duty',
      component = N'EntityList/entityListFromDesigner',
      meta = N'{"icon":"mdi:badge-account-horizontal","title":"岗位管理","query":{"entityname":"hr_base_duty_list","menuid":"A1000001-0001-4001-8001-000000000121"}}',
      parent_id = @parent_menu_id,
      status = 1,
      type = N'menu',
      sort = ISNULL(sort, 121)
  WHERE id = @leaf_menu_id;
END

/* 菜单授权 */
DELETE FROM dbo.vben_t_sys_role_menus
WHERE role_id = @role_id AND menus_id = @leaf_menu_id;

INSERT INTO dbo.vben_t_sys_role_menus (id, role_id, menus_id)
VALUES (NEWID(), @role_id, @leaf_menu_id);

/* 菜单按钮：幂等重建 */
DECLARE @action_keys TABLE(action_key NVARCHAR(50), label NVARCHAR(50), sort INT, requires_selection BIT, button_type NVARCHAR(20));
INSERT INTO @action_keys(action_key, label, sort, requires_selection, button_type) VALUES
  (N'add',            N'新增',   10, 0, N'primary'),
  (N'edit',           N'修改',   20, 1, N'default'),
  (N'deleteSelected', N'删除',   30, 1, N'danger'),
  (N'reload',         N'刷新',   40, 0, N'default');

DELETE rma
FROM dbo.vben_t_sys_role_menu_actions rma
JOIN dbo.vben_menu_actions ma ON ma.id = rma.menu_action_id
WHERE ma.menu_id = @leaf_menu_id
  AND ma.action_key IN (SELECT action_key FROM @action_keys);

DELETE FROM dbo.vben_menu_actions
WHERE menu_id = @leaf_menu_id
  AND action_key IN (SELECT action_key FROM @action_keys);

INSERT INTO dbo.vben_menu_actions
  (id, menu_id, action_key, label, button_type, action, confirm_text, sort, status, form_code, requires_selection)
SELECT
  NEWID(),
  @leaf_menu_id,
  k.action_key,
  k.label,
  k.button_type,
  k.action_key,
  CASE WHEN k.action_key = N'deleteSelected' THEN N'确认删除选中岗位吗？' ELSE NULL END,
  k.sort,
  1,
  NULL,
  k.requires_selection
FROM @action_keys k;

INSERT INTO dbo.vben_t_sys_role_menu_actions (id, role_id, menu_action_id, menu_id, status)
SELECT NEWID(), @role_id, ma.id, @leaf_menu_id, 1
FROM dbo.vben_menu_actions ma
WHERE ma.menu_id = @leaf_menu_id
  AND ma.action_key IN (SELECT action_key FROM @action_keys);

/* 列表设计器配置：hr_base_duty_list */
DECLARE @schema_id UNIQUEIDENTIFIER;
SELECT TOP 1 @schema_id = id
FROM dbo.vben_entitylist_desinger
WHERE code = N'hr_base_duty_list'
ORDER BY updated_at DESC;

DECLARE @schema_json NVARCHAR(MAX) = N'{
  "title":"岗位管理",
  "tableName":"v_t_base_duty_group",
  "primaryKey":"id",
  "deleteEntityName":"t_base_duty",
  "saveEntityName":"t_base_duty",
  "actionModule":"/src/views/EntityList/baseDutyActions.ts",
  "toolbar":{
    "actions":[
      {"key":"add","label":"新增","type":"primary","action":"add","form_code":"hr_base_duty_add"},
      {"key":"edit","label":"修改","action":"edit","requiresSelection":true,"form_code":"hr_base_duty_edit"},
      {"key":"deleteSelected","label":"删除","action":"deleteWithGuard","requiresSelection":true},
      {"key":"reload","label":"刷新","type":"primary","action":"reload"}
    ]
  },
  "form":{
    "collapsed":false,
    "showCollapseButton":true,
    "schema":[
      {"component":"Input","fieldName":"name","label":"名称","componentProps":{"allowClear":true}},
      {"component":"Input","fieldName":"groupname","label":"分组","componentProps":{"allowClear":true}},
      {"component":"Input","fieldName":"level_no_eq","label":"职级","componentProps":{"allowClear":true}}
    ]
  },
  "grid":{
    "columns":[
      {"type":"checkbox","width":50},
      {"type":"seq","width":50},
      {"field":"id","title":"id","width":50,"sortable":true,"visible":false},
      {"field":"SJID","title":"岗位编码","width":50,"sortable":true},
      {"field":"name","title":"名称","width":150,"sortable":true},
      {"field":"code","title":"编码","width":50,"sortable":true,"visible":false},
      {"field":"groupname","title":"分组","width":50,"sortable":true},
      {"field":"level_no","title":"职级","width":50,"sortable":true},
      {"field":"is_manager","title":"是否预设管理职","width":50,"sortable":true},
      {"field":"description","title":"描述","width":100}
    ],
    "pagerConfig":{"enabled":true,"pageSize":20},
    "sortConfig":{"remote":true,"defaultSort":{"field":"id","order":"asc"}}
  },
  "api":{
    "query":"/api/DynamicQueryBeta/queryforvben",
    "delete":"/api/DataBatchDelete/BatchDelete",
    "export":"/api/DynamicQueryBeta/ExportExcel"
  }
}';

IF @schema_id IS NULL
BEGIN
  INSERT INTO dbo.vben_entitylist_desinger (id, code, title, table_name, schema_json, created_at, updated_at)
  VALUES (NEWID(), N'hr_base_duty_list', N'岗位管理', N'v_t_base_duty_group', @schema_json, GETDATE(), GETDATE());
END
ELSE
BEGIN
  UPDATE dbo.vben_entitylist_desinger
  SET title = N'岗位管理',
      table_name = N'v_t_base_duty_group',
      schema_json = @schema_json,
      updated_at = GETDATE()
  WHERE id = @schema_id;
END

/* 表单设计器配置：岗位新增 */
DECLARE @duty_add_id UNIQUEIDENTIFIER;
SELECT TOP 1 @duty_add_id = id
FROM dbo.vben_form_desinger
WHERE code = N'hr_base_duty_add'
ORDER BY updated_at DESC;

DECLARE @duty_add_schema NVARCHAR(MAX) = N'{
  "layout":{"cols":1,"labelWidth":110,"labelAlign":"right"},
  "schema":[
    {"component":"Input","fieldName":"id","label":"id","dependencies":{"if":false}},
    {"component":"Input","fieldName":"code","label":"编码","dependencies":{"if":false}},
    {"component":"Input","fieldName":"name","label":"职务名称","required":true,"componentProps":{"allowClear":true}},
    {"component":"Input","fieldName":"SJID","label":"职务编码","required":true,"componentProps":{"allowClear":true}},
    {"component":"Input","fieldName":"level_no","label":"职级","componentProps":{"allowClear":true}},
    {"component":"RadioGroup","fieldName":"is_manager","label":"预设为管理职务","defaultValue":"0","componentProps":{"options":[{"label":"是","value":"1"},{"label":"否","value":"0"}]}},
    {"component":"Input","fieldName":"group_id","label":"分组ID","componentProps":{"allowClear":true}},
    {"component":"Textarea","fieldName":"description","label":"说明","componentProps":{"rows":4}}
  ]
}';

IF @duty_add_id IS NULL
BEGIN
  INSERT INTO dbo.vben_form_desinger (id, code, title, schema_json, created_at, updated_at)
  VALUES (NEWID(), N'hr_base_duty_add', N'岗位新增', @duty_add_schema, GETDATE(), GETDATE());
END
ELSE
BEGIN
  UPDATE dbo.vben_form_desinger
  SET title = N'岗位新增',
      schema_json = @duty_add_schema,
      updated_at = GETDATE()
  WHERE id = @duty_add_id;
END

/* 表单设计器配置：岗位修改 */
DECLARE @duty_edit_id UNIQUEIDENTIFIER;
SELECT TOP 1 @duty_edit_id = id
FROM dbo.vben_form_desinger
WHERE code = N'hr_base_duty_edit'
ORDER BY updated_at DESC;

DECLARE @duty_edit_schema NVARCHAR(MAX) = N'{
  "layout":{"cols":1,"labelWidth":110,"labelAlign":"right"},
  "schema":[
    {"component":"Input","fieldName":"id","label":"id","dependencies":{"if":false}},
    {"component":"Input","fieldName":"code","label":"编码","dependencies":{"if":false}},
    {"component":"Input","fieldName":"name","label":"职务名称","required":true,"componentProps":{"allowClear":true}},
    {"component":"Input","fieldName":"SJID","label":"职务编码","componentProps":{"disabled":true}},
    {"component":"Input","fieldName":"level_no","label":"职级","componentProps":{"allowClear":true}},
    {"component":"RadioGroup","fieldName":"is_manager","label":"预设为管理职务","defaultValue":"0","componentProps":{"options":[{"label":"是","value":"1"},{"label":"否","value":"0"}]}},
    {"component":"Input","fieldName":"group_id","label":"分组ID","componentProps":{"allowClear":true}},
    {"component":"Textarea","fieldName":"description","label":"说明","componentProps":{"rows":4}}
  ]
}';

IF @duty_edit_id IS NULL
BEGIN
  INSERT INTO dbo.vben_form_desinger (id, code, title, schema_json, created_at, updated_at)
  VALUES (NEWID(), N'hr_base_duty_edit', N'岗位修改', @duty_edit_schema, GETDATE(), GETDATE());
END
ELSE
BEGIN
  UPDATE dbo.vben_form_desinger
  SET title = N'岗位修改',
      schema_json = @duty_edit_schema,
      updated_at = GETDATE()
  WHERE id = @duty_edit_id;
END

PRINT N'OK: 岗位管理菜单与按钮权限迁移完成。';

