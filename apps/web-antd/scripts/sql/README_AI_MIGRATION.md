# AI Migration Playbook (Old → New System)

**Audience: AI agents only.** Use as a **lookup**: apply sections by reference; **do not** re-explain long-form UX or form-layout details in user chat on every migration.  
Goal: **idempotent** SQL + correct `schema_json`; avoid blank routes, missing toolbar auth, wrong save target, `queryforvben` 400.

## Scope

- **DB targets (new system)**:
  - `vben_entitylist_desinger` (list schema JSON, `schema_json`)
  - `vben_form_desinger` (popup form schema for Add/Edit when using `form_code` on toolbar buttons)
  - `vben_menus_new` (menu tree, routes/components/meta)
  - `vben_t_sys_role_menus` (role-menu authorization)
  - `vben_menu_actions` (toolbar buttons bound to menu — **required** whenever the list toolbar has buttons and `meta.query.menuid` is set)
  - `vben_t_sys_role_menu_actions` (role-button authorization — **required** with `vben_menu_actions` for the same buttons)
- **Front-end runtime**:
  - List pages may use `/EntityList/entityListFromDesigner` (designer-driven `QueryTableSchema`)
  - `QueryTable` must apply `queryTableGridEnhance` so designer fields work (conditionalStyles/hyperlink/aggFunc/footer)
  - **固定表头 + 表体滚动**：在 `schema_json.grid` 里显式写 **`maxHeight`** 或 **`height`**（例：`"maxHeight": "calc(100vh - 260px)"`）传给 VxeGrid；不写则整表随页面滚动。勿依赖已废弃的默认注入（易把表体高度算成极小）。

## Non-negotiable principles

- **No UI clicking**: always provide SQL the user can copy-run.
- **Idempotent**: repeat execution must be safe.
  - Prefer **DELETE then INSERT** by fixed IDs/codes.
  - Order: delete role bindings → delete menu → delete list schema.
- **Role default**: assign to role named **`系统管理员`** by querying `vben_role`.
- **Authorization is mandatory (menu + button)**:
  - menu permission: `vben_t_sys_role_menus`
  - button permission (if buttons exist): `vben_t_sys_role_menu_actions`
  - Do not stop at schema/menu insertion only.
- **Avoid global FE regressions**: prefer **data-level fixes** (schema JSON) over changing shared components/merge order/layout unless necessary.

## Inputs required (collect before generating SQL)

For each menu leaf being migrated:

- **Menu IDs** (fixed GUIDs): `root_id`, (optional) `mid_id`, `leaf_id`
- **Menu labels**: `root_name`, `mid_name`, `leaf_name`
- **Menu paths**: `root_path` (optional), `leaf_path`
- **Component**:
  - For designer list: `component = '/EntityList/entityListFromDesigner'`
  - Alternative stable list: `component = '/EntityList/listFromDb'` (when designer not desired)
- **Route meta.query** for designer lists:
  - `entityname`: designer code/table key (used to fetch from `vben_entitylist_desinger`)
  - `menuid`: leaf menu GUID (used for toolbar/actions binding)
- **List schema**:
  - `vben_entitylist_desinger.code` (should match `meta.query.entityname`)
  - `schema_json` (QueryTableSchema JSON)
- **Authorization**:
  - default: role `系统管理员`
  - optionally additional roles

### Must resolve (do not guess) — prevents repeat failures on **every** future migration

If any of the following are missing, **stop and ask / query the DB** before generating `migrate_full_*.sql`. Guessing from naming patterns causes silent wrong data in `schema_json` and hours of debugging.

| Gap | What goes wrong | How to resolve |
| --- | --- | --- |
| **List query object name** not confirmed | 208 invalid object, blank list, wrong menu binding | Match old `datagrid.aspx?entity=` / `t_sys_function.entity_name`; `SELECT name FROM sys.views` / `sys.tables`; `OBJECT_ID` check in SQL script |
| **Writable table + PK** for `DataSave` / `BatchDelete` not taken from **view definition** | List works (SELECT view) but save / custom toolbar batch update fails with **PK / table metadata** errors | Read `sys.sql_modules.definition` for the list view; identify **`FROM dbo.<base_table>`** (not “strip `v_`”, not “same stem as view name”). Confirm PK via `INFORMATION_SCHEMA` / MCP `describe_table` |
| **Column list** for target view/table not verified | `queryforvben` **400** (`defaultSort.field` missing), wrong labels, empty-looking grids | `describe_table` / column list before writing `grid.columns`, `form.schema`, `defaultSort` |
| **Script uses `REPLACE(template_token, @variable)`** and `@variable` is wrong | **Every** occurrence of the token in JSON (list + form + sometimes comments) becomes wrong → shared broken `saveEntityName` | After choosing `@save_entity`, mentally trace what strings `REPLACE` will touch; add `OBJECT_ID` guard for the **save** table in script; prefer explicit `JSON_MODIFY` for hotfixes |
| **Toolbar custom actions** (e.g. audit) reuse list `saveEntityName` | Same wrong table/PK as modal save; error appears only on that button | Fixing `schema_json.saveEntityName` / `deleteEntityName` fixes **all** write paths; optional FE guard for known modules does **not** replace DB fix |
| **`code` / `table_name` / `meta.query.entityname`** not kept identical | Wrong schema loaded, buttons filtered out, fix scripts “row not found” | Single source of truth: designer `code` = menu `entityname` = `table_name` |

**Note:** `1004` 签卡 migration = **worked example** of this table (especially REPLACE + wrong `@save_entity`), not extra rules.

## 3-level menu (nested layout blank)

- **Cause:** mid + child both `component=LAYOUT` / BasicLayout → nested layouts.
- **Fix (DB):** mid grouping node `component=''` (or NULL per schema); children only.
- **Fix (FE guard):** `packages/effects/access/src/accessible.ts` strips nested layout `component` when ancestor is layout.

## List schema (QueryTableSchema) conventions

### Where schema is stored

- `vben_entitylist_desinger`:
  - `code`: key
  - `schema_json`: JSON string, parsed at runtime

### Key JSON fields used in this project

- `title`, `tableName`, `primaryKey`
- `api.query`, `api.delete`, `api.export`
- `form`:
  - `schema`: array of query fields
  - `collapsed`, `submitOnChange`
  - `wrapperClass` (important for layout)
- `grid`:
  - `columns`: vxe columns
  - `pagerConfig`
  - `sortConfig.defaultSort`
- `toolbar.actions` (optional; otherwise QueryTable may fallback)

### FE patterns (list query form + popup form) — **single source; do not re-document per menu**

| Need | Action |
| --- | --- |
| Query form huge blank area | `schema_json.form.wrapperClass` ≈ field grid, e.g. `grid-cols-1 md:grid-cols-2 lg:grid-cols-2` — **data fix**, not global CSS |
| 工号 / employee remote pick + fill 姓名、部门 | `AutoComplete`, `componentProps.dataSourceType: 'query'`, `tableName: v_t_base_employee` (server whitelist), `labelField`/`valueField`/`searchField`, `displayColumnsText` for multi-column labels, **`dropdownMatchSelectWidth: false`** (else columns collapse), `responseMap` for extra fields |
| Row→form mapping edge case | Empty `longdeptname` must not overwrite non-empty `long_name` — already in `FormFromDesignerModal` |
| Runtime wiring | `FormFromDesignerModal.attachAutoCompleteRemoteQuery`; query table same patterns apply elsewhere |

Reference SQL fragment swap: `fix_签卡作业_form_工号AutoComplete.sql` (reuse shape for other entities).

### Column aggregate (sum/count/avg...) must work

- Designer uses `columns[].aggFunc` to declare aggregate.
- Runtime must:
  - enable `grid.showFooter`
  - provide `grid.footerMethod` to compute footer
- In this repo, `apps/web-antd/src/components/QueryTable/queryTableGridEnhance.ts` is responsible for:
  - conditional styles
  - hyperlink renderer
  - footer/aggregates (via `showFooter` + default `footerMethod` when `aggFunc` present)
- `apps/web-antd/src/components/QueryTable/index.vue` must call:
  - `enhanceQueryTableGrid(props.schema.grid)`

## SQL file naming (AI-added scripts)

When adding new `.sql` files under `scripts/sql/`, prefix with a **numeric id** so they sort together and are easy to find (e.g. `1001_migrate_full_人员班次权限.sql`). Increment the number for each new file (`1002_...`, `1003_...`). Descriptive Chinese/English suffix after the underscore is still recommended.

## Bundled scripts: 考勤日常处理 (attendance daily)

Parent mid menu id: `A1000001-0001-4001-8001-000000000030` (path `/attendance/daily`, grouping node `component=''`).

Run **in this order**:

1. **`1002_migrate_full_刷卡资料查询.sql`** — Creates the mid menu + **刷卡资料查询** (read-only list `v_att_lst_Cardrecord`), path `/attendance/daily/card-record`, component `/EntityList/entityListFromDesigner`.
2. **`1004_migrate_full_签卡作业.sql`** — **签卡作业** (designer list + form CRUD). Follow **Must resolve (do not guess)** above: `@list_code` = list view/entity; `@save_entity` = **base table from view `FROM`**, not a name derived from the view string.  
   - **Verified on test DB**: list `v_att_lst_RegRecord` → save **`att_lst_Cardrecord`**. Wrong `@save_entity` + `REPLACE` → bad `saveEntityName` (see **Case: 签卡**).  
   - Path `/attendance/daily/card-signing-work`; leaf `menuid` = `A1000001-0001-4001-8001-000000000033`.  
   - Early templates used placeholder `v_att_lst_SignCard` — **do not assume that name exists** in every customer DB.
3. **`1003_migrate_menu_排班作业_硬编码页.sql`** — **排班作业** hardcoded page (needs mid from step 1), path `/attendance/daily/job-scheduling-work`, component `/attendance/JobSchedulingWork`.
4. **`1005_migrate_full_加班作业.sql`** — **加班作业** (`v_att_lst_OverTime` → save `att_lst_OverTime`, FID), path `/attendance/daily/overtime-work`, audit/cancel via `overtimeWorkActions.ts`, leaf `menuid` = `A1000001-0001-4001-8001-000000000034`.
5. **`1006_migrate_full_请假作业.sql`** — **请假作业** (`v_att_lst_Holiday` → save `att_lst_Holiday`, FID), path `/attendance/daily/leave-work`, CRUD+export only (no audit in old `t_sys_function_operation`), leaf `menuid` = `A1000001-0001-4001-8001-000000000035`.
6. **`1008_migrate_full_考勤日结果.sql`** — **考勤日结果**（`v_att_lst_DayResult`）：只读列表 + 导出/刷新；`grid.columns` 的**顺序与表头文案**应与老库 **`t_set_datagrid`**（`entity = v_att_lst_DayResult`，`is_visiable = 'Y'`）一致；核对方式：`SELECT sort, name, caption, header, width, is_visiable FROM t_set_datagrid WHERE entity = N'v_att_lst_DayResult' ORDER BY sort, name`。老 URL 中 `totalfields=attDay,attLate,attEarly` → 此三列可设 `aggFunc: "sum"`（当前页表尾汇总）。列表设计器里 `mergeHeaderTitle` 仅合并**相邻**列；**考勤日结果** 与老 EasyUI 一致：**每段一个父表头，下挂 5 列**（计划开始/上班/计划结束/段状态/下班），在 `schema_json` 中写 **Vxe 分组列** `{"title":"第一段","children":[...5]}` 等（`QueryTable` 运行时不会把 `mergeHeaderTitle` 转成 children，见 `queryTableGridEnhance`）。视图须含 **`attHolidayName`**（脚本内 `ALTER VIEW` 补 `hc.HC_Name`）；假别展示用该列而非 `attHolidayID`。`toolbarConfig.custom: true` 可列设置显隐。固定叶子 `…036`、列表 `…236`。前置同 1002（`030`）。
7. **`1007_move_menu_考勤日结果_到考勤日常处理.sql`** — 可选兜底：仅改 `parent_id`/`path`，不建列表；**一般请用 1008**。

- Post-`1004`: refresh menus; if columns differ from template, patch designer rows for current `code` + `form_att_sign_card`.
- Wrong historical SignCard names: `fix_签卡作业_库配置_SignCard改RegRecord与Cardrecord.sql` or re-run `1004` after fixing vars.
- Wrong `saveEntityName` (`att_lst_RegRecord`): `fix_签卡作业_saveEntityName_物理表Cardrecord.sql` or re-run `1004` with `@save_entity=att_lst_Cardrecord`.
- `queryforvben` 400: `defaultSort.field` must exist on list object; `fix_签卡作业_queryforvben_400_defaultSort.sql`; `QueryTable` SimpleWhere stringification in `index.vue` if needed.

## SQL script structure (template)

### Role resolution (default 系统管理员)

```sql
DECLARE @role_name NVARCHAR(50) = N'系统管理员';
DECLARE @role_id UNIQUEIDENTIFIER;

SELECT TOP 1 @role_id = r.id
FROM vben_role r
WHERE r.name = @role_name;

IF @role_id IS NULL
BEGIN
  RAISERROR(N'Role not found: %s', 16, 1, @role_name);
  RETURN;
END
```

### Idempotent delete-then-insert order

1) Delete role bindings for the menu IDs:

```sql
DELETE FROM vben_t_sys_role_menus WHERE menu_id IN (@leaf_id, @mid_id, @root_id);
```

2) Delete menus (leaf → mid → root):

```sql
DELETE FROM vben_menus_new WHERE id IN (@leaf_id, @mid_id, @root_id);
```

3) Delete list schema by `code` (entityname):

```sql
DELETE FROM vben_entitylist_desinger WHERE code = @entityname;
```

4) Insert list schema.
5) Insert menus.
6) Insert menu role bindings (`vben_t_sys_role_menus`).
7) If the list toolbar has **any** buttons (including built-in-looking **新增/编辑/删除/导出/刷新**), insert `vben_menu_actions` and then insert role-button bindings (`vben_t_sys_role_menu_actions`) for role `系统管理员`.
8) If Add/Edit uses `form_code`, insert/update `vben_form_desinger` (see **Gold standard** below). Idempotent deletes should remove form rows (by fixed `id` or `code`) **after** clearing `vben_t_sys_role_menu_actions` / `vben_menu_actions` that reference them, and **before** re-inserting list/menu as your script defines.

### Mandatory auth checklist (do not skip)

For each migrated menu leaf:

- Must insert one row in `vben_t_sys_role_menus` for role `系统管理员`.
- If custom buttons are used:
  - Must insert rows in `vben_menu_actions`.
  - Must insert matching rows in `vben_t_sys_role_menu_actions` for role `系统管理员`.
- If user says “default role”, treat it as:
  - menu auth + button auth both assigned to `系统管理员`.

### Designer leaf menu meta.query contract

The leaf menu must include:

- `component = '/EntityList/entityListFromDesigner'`
- `meta.query.entityname = <code>`
- `meta.query.menuid = <leaf_guid>`

If `entityname` or `menuid` is wrong/missing, runtime may:

- load wrong schema
- fail to load menu buttons (toolbar)

## Known regression zones (do not touch casually)

- `packages/effects/plugins/src/vxe-table/use-vxe-grid.vue`:
  - changing merge order for `formOptions` can cause query form schema to become empty.
  - if wrapperClass must be forced, do it **surgically** without overriding `form.schema`.
- Shared layout components:
  - avoid quick CSS hacks to fix blank space; prefer schema JSON wrapperClass.

## “Migration decision tree” (quick)

- Need a list page with query/table/toolbar driven by DB schema?
  - Use `/EntityList/entityListFromDesigner` + `vben_entitylist_desinger`.
- Page is simple and doesn’t need designer?
  - Consider `/EntityList/listFromDb` (often fewer surprises).
- Legacy page is **tree + multi-tab + custom grids/modals + procs** and a single designer list would be fragile or misleading?
  - Use a **hardcoded Vue page** + menu row only (see **Hardcoded feature pages** below). Do **not** insert `vben_entitylist_desinger` for that leaf unless you also need a designer list variant.
- Menu depth is 3 levels?
  - Mid node must NOT render layout (`component=''`) OR ensure FE nested-layout stripping is in place.

## Hardcoded feature pages (非配置列表 / 不走 `vben_entitylist_desinger`)

Use this when migrating an old ASP.NET/WebForms-style screen that **cannot** be faithfully replaced by one `QueryTable` + `schema_json` (e.g. left tree, right master-detail, multiple tabs, fieldset tables, “选择列表” pickers with union/search/paging, calls to `datasave-multi` and stored procedures in one workflow).

### When to choose hardcoding vs designer

| Prefer **designer list** | Prefer **hardcoded page** |
| --- | --- |
| Single grid (+ optional simple form modal) | Tree + several unrelated sub-areas on one route |
| Toolbar maps cleanly to CRUD / export / one proc | Many bespoke buttons and layouts tied together |
| Columns/query/sort are the main UX | Strong layout parity with legacy (fieldset colors, modal toolbars, etc.) |
| Permissions via `vben_menu_actions` + toolbar keys | In-page actions only; menu leaf is just “open this screen” |

Hardcoding is **more front-end work** but avoids polluting the designer with impossible or unreadable schema.

### Process (SOP) — what to deliver

1. **Trace the old page**  
   - URL / `aspx`, which tables/views/procs, and which operations (load tree, load detail, save rows, batch delete, `EXEC` proc).  
   - Align field names with SQL Server (`sys.columns` or MCP `describe_table`).

2. **Implement the Vue page** (under `apps/web-antd/src/views/...`)  
   - One main `.vue` (or split only if large).  
   - Optional small `*Api.ts` beside it for `queryForVben`, `saveDatasaveMulti`, `batchDelete`, `executeProcedure`, and shared `whereAnd` / `queryForVbenPaged` so the SFC stays readable.

3. **Wire the route**  
   - Either register in `apps/web-antd/src/router/routes/modules/...` **or** rely on **DB-driven menus** if your project loads routes from `vben_menus_new` with `component` paths (match how other hardcoded pages are registered in this repo).

4. **Menu migration SQL** (idempotent script under `scripts/sql/`)  
   - Insert/update **only** `vben_menus_new` (+ `vben_t_sys_role_menus` for `系统管理员`).  
   - Leaf row: `component` = front-end route component path (e.g. `/attendance/ShiftBcSetting`), `path` = unique route path.  
   - **Do not** set `meta.query.entityname` for designer lists on this leaf (no `vben_entitylist_desinger` row).  
   - **Usually skip** `vben_menu_actions` / `vben_t_sys_role_menu_actions` unless buttons must participate in the **global menu-button permission** system; hardcoded pages often handle actions inside the page.

5. **Verify**  
   - Open menu, no blank layout; all API calls return `code=0`; save/delete/proc match legacy behavior.

### Reference case in this repo: 班次设定

- **Page**: `apps/web-antd/src/views/attendance/ShiftBcSetting.vue`  
- **API helpers**: `apps/web-antd/src/views/attendance/shiftBcSettingApi.ts`  
- **Menu script example**: `scripts/sql/migrate_menu_班次设定_硬编码页面.sql`  
- **Data flow (conceptual)**  
  - Tree: `DynamicQueryBeta/queryforvben` on view `v_t_att_lst_BC_set_code` (flat `id` / `parent_id` → build `Tree`).  
  - Detail header + intervals: `queryforvben` on `att_lst_BC_set_code`, `att_lst_time_interval` (`Where` with `pb_code_fid` + `sec_num`).  
  - Save intervals: `DataSave/datasave-multi` → table `att_lst_time_interval`.  
  - Users tab: `queryforvben` on `v_att_lst_ShiftsSetting`; assign users: `Procedure/execute` → `dbo.att_set_BCusers`; remove binding: `DataBatchDelete/BatchDelete`.  
  - Master “新增/修改”: modal → `datasave-multi` on `att_lst_BC_set_code`.  
  - “选择列表” picker: paged `queryforvben` on `t_sys_user`, multi-select + optional **并集** behavior on re-query.

### Backend APIs used by hardcoded pages (StoneApi)

| API | Typical use |
| --- | --- |
| `POST .../DynamicQueryBeta/queryforvben` | Read any whitelisted table/view; body: `TableName`, `Page`, `PageSize`, `SortBy`, `SortOrder`, optional `Where` / `SimpleWhere`. Response `data`: `{ items, total }`. |
| `POST .../DataSave/datasave-multi` | Insert/update rows; `{ tables: [{ tableName, primaryKey, data, deleteRows }] }`. |
| `POST .../DataBatchDelete/BatchDelete` | Delete by PK list. |
| `POST .../Procedure/execute` | Named proc + parameters (whitelist/security on server). |

### Critical front-end pitfall: `queryforvben` **400 Bad Request**

- StoneApi model `Condition` uses **`Value` as `string`**.  
- If the JSON body sends **numbers** (e.g. `sec_num: 1`, `status: 0`), **System.Text.Json may fail to deserialize** the whole request → **HTTP 400** before SQL runs.  
- **Fix**: always send string values in `Where.Conditions[]`, e.g. helper `whereAnd()` that does `String(value)` for every condition (see `shiftBcSettingApi.ts`).

### Paging and totals

- Default `queryForVben` wrapper may only return `items`. For modals like “选择列表”, use a helper that returns **`{ items, total }`** from the same endpoint (`QueryResult` from server) so the table can show “每页 N 条，共 T 条”.

### Complex `Where` clauses

- `WhereNode` supports `Logic` + `Conditions` + nested `Groups` (e.g. `(username LIKE … OR name LIKE …)`).  
- Field names must pass server validation (letters, digits, underscore).  
- Supported operators include `eq`, `contains`, `startswith`, `endswith` (see server `DynamicQueryBuilder`).

### SQL menu row hints (hardcoded leaf)

- `component`: must match how the app resolves routes (e.g. `/attendance/ShiftBcSetting`).  
- `path`: unique, stable URL segment.  
- `meta`: title, icon, `hideInMenu` as needed; **omit** `entityname` unless this route still opens `entityListFromDesigner`.  
- Parent menu: same 3-level rules as designer (mid node not double-`LAYOUT`).

### UX parity (hardcoded / picker pages)

- If user asks legacy look: fieldset + green headers, modal title 选择列表, toolbar order, `preserveSelectedRowKeys` — implement in Vue; **not** in `schema_json`.

### Verification checklist (hardcoded page)

- [ ] Menu opens correct component (no nested layout blank).  
- [ ] All dynamic queries return data; **no 400** on `queryforvben` (watch Network response body for server `ex.Message` if any).  
- [ ] Saves use correct table/PK; proc names and parameter names match DBA definition.  
- [ ] `BatchDelete` keys match server expectation (e.g. GUID uppercase if required).  
- [ ] New menu authorized for **系统管理员** (`vben_t_sys_role_menus`).

## Verification checklist (post-run)

- Menu appears in sidebar and navigates correctly.
- Switching tabs/routes after visiting the page does **not** blank other pages.
- Query conditions render (form schema not empty).
- Aggregate footer appears if `aggFunc` set.
- Toolbar buttons load when `meta.query.menuid` is set and menu has actions.

## Case notes (real incidents in this repo)

### Case: 签卡 `1004` — index only

Illustrates **Must resolve** gaps: wrong list entity (208), view vs **FROM** base table + PK, unverified columns/`defaultSort` (400), **`REPLACE(..., @save_entity)`** poisoning `saveEntityName`, `code`/`entityname` drift. **Form/employee UI:** see **FE patterns** table — not repeated here.

| File | Use |
| --- | --- |
| `1004_migrate_full_签卡作业.sql` | Full migrate |
| `fix_签卡作业_库配置_SignCard改RegRecord与Cardrecord.sql` | Legacy SignCard → RegRecord + Cardrecord |
| `fix_签卡作业_saveEntityName_物理表Cardrecord.sql` | Wrong save table after bad `@save_entity` |
| `fix_签卡作业_queryforvben_400_defaultSort.sql` | `defaultSort.field` |
| `fix_签卡作业_form_工号AutoComplete.sql` | Employee AutoComplete JSON swap (see **FE patterns**) |

`vben_menus_new` may lack `updated_at` — omit from UPDATE in fix scripts.

---

### Case: Tree list menu migration (treedatagrid → designer list)

Example: `最大连续排班天数设定` (old `treedatagrid.aspx`, entity `v_att_lst_ShiftsRules`)

- **Old data shape**: flat rows with `parent_id` + sort field (`sort`)
- **New schema must include**:
  - `grid.treeConfig.transform = true`
  - `grid.treeConfig.rowField = 'id'`
  - `grid.treeConfig.parentField = 'parent_id'`
  - one column should have `"treeNode": true` (usually the name column)
- **Menu placement**:
  - 3-level menu under `/attendance` is OK only if mid node is a grouping node (`component=''`)

### Case: “Page opens but no data; refresh shows 500 Internal Server Error”

Observed when migrating `v_att_lst_ShiftsRules`:

- **Root cause**: `schema_json.api.query` saved as **relative** `/api/...` while the environment expected a **full URL**
  (existing working configs stored `http://127.0.0.1:5155/api/...`).
- **Fix strategy (preferred)**:
  - When generating migration SQL, **reuse API URLs** from a known-good existing list config (e.g. `mig_att_holiday_category`)
    via `JSON_VALUE(schema_json,'$.api.query')`, then inject into the new schema JSON.
- **Fix strategy (hotfix)**:
  - `JSON_MODIFY(schema_json,'$.api.query', <good_url>)` for the affected `code`.

### Case: Menu actions vs. list toolbar actions (and role permissions)

Important distinction in this project:

- **List page buttons shown in UI** come from `vben_entitylist_desinger.schema_json.toolbar.actions`.
- **Menu-level button definitions** are stored in `vben_menu_actions` and role permissions in `vben_t_sys_role_menu_actions`.
- Migration that needs “新增/编辑/删除” must often write **both**:
  - `vben_entitylist_desinger.schema_json.toolbar.actions` (so UI shows buttons)
  - `vben_menu_actions` + `vben_t_sys_role_menu_actions` (so the menu-button system and role permissions are consistent)
- Practical rule:
  - if button is business-critical, always add both schema toolbar and menu/button permission tables.
  - default role binding is always `系统管理员` unless user explicitly asks otherwise.

### Case: “No checkbox column” even though schema contains it

Observed in `加班规则设定 (v_att_lst_overtimeRules)`:

- **Root cause**: checkbox column was appended to the end of `grid.columns`.
  In some vxe configurations, a late checkbox column may not render as expected.
- **Fix**: ensure checkbox column is at the **front** of `grid.columns`.
  - Prefer: rebuild `$.grid.columns` so it starts with `{"type":"checkbox","width":50}` and removes duplicates.

### Case: QueryTable `openModal` — cancel no-op + footer outside modal

Observed on **数据权限配置** (`DataPowerPermissionEditor` inside `Modal.confirm`):

- **Root cause A**: child used `emit('onCancel')` while `openModal` passed `onCancel: () => destroy()` on the vnode → Vue listens for event **`cancel`**, not **`onCancel`**.
- **Root cause B**: merged **`style: { height: '500px' }`** on the SFC root forced overflow; footer looked detached from the modal body.
- **Fix**: emit **`cancel`/`success`**; remove default inner height; use modal **`bodyStyle` max-height + overflow**; strip **`width`** from child spread only.  
  Full write-up: **QueryTable dynamic modal pitfalls** section above.

### Case: “Edit button missing” after SQL updates

- **Schema was updated** (toolbar actions exist in DB) but UI may still not show it due to:
  - keep-alive / cached route instance
  - preview/list schema not reloaded
- **Fix**:
  - confirm DB `schema_json.toolbar.actions` has the button keys
  - hard refresh page / reload app if necessary
  - if it still doesn’t show, ensure the menu route’s `meta.query.entityname` matches `vben_entitylist_desinger.code`

### Recommended “full CRUD via form designer” pattern

For a list that needs Add/Edit:

- Create form schema:
  - insert into `vben_form_desinger` with `code=<form_code>`, `list_code=<list_code>`
- Add two toolbar actions into the list schema:
  - Add: `{ action:'add', form_code:<form_code> }`
  - Edit: `{ action:'edit', form_code:<form_code>, requiresSelection:true }`
- Ensure `grid.columns` contains checkbox column at index 0.
- **Do not treat menu/button tables as optional** when `meta.query.menuid` is set:
  - `vben_menu_actions` rows with `form_code` and `requires_selection` where applicable
  - `vben_t_sys_role_menu_actions` rows for role `系统管理员` for **every** toolbar `key` you want visible

### Gold standard: one-shot `migrate_full` with Add/Edit (+ delete/export/reload)

**Reference script in this repo:** `migrate_full_法定假日设定.sql` — use it as the template whenever migrating a **read/write designer list** (not a read-only or proc-only toolbar).

**Why this is mandatory wiring (runtime):**

- `apps/web-antd/src/views/EntityList/entityListFromDesigner.vue` loads `toolbar.actions` from `vben_entitylist_desinger`, then **filters** them against `vben_v_user_role_menu_actions` using `meta.query.menuid` + user id.
- If `vben_menu_actions` / `vben_t_sys_role_menu_actions` are missing or `action_key` does not match the button **`key`**, the user’s allowed set is empty or incomplete → **buttons disappear** and `filterApiByAllowed` may clear `api.delete` / `api.export`.
- **新增/编辑** are handled by `QueryTable` via `form_code` → `openFormFromDesignerModal()` reading **`vben_form_desinger`**. List `form.schema` is for **query conditions**, not a substitute for the popup form row.

**Checklist — copy for every comparable `migrate_full_*.sql`:**

1. **`vben_form_desinger`** (fixed `id` + `code`, e.g. `form_<entity_short_name>`):
   - `list_code` = `vben_entitylist_desinger.code` (same as `meta.query.entityname`).
   - `schema_json` includes **`saveEntityName`** (writable base table), **`primaryKey`**, and **`schema`** (popup fields). Align with “Save target priority” section below (form wins over list for save target).
2. **`vben_entitylist_desinger.schema_json`**:
   - `toolbar.actions` at minimum:
     - `{ "key":"add", "action":"add", "form_code":"<form_code>", "type":"primary", "label":"新增" }`
     - `{ "key":"edit", "action":"edit", "form_code":"<form_code>", "requiresSelection":true, "label":"编辑" }`
   - For full CRUD/UX, also add **`deleteSelected`**, **`export`**, **`reload`** (same `key` / `action` names as in `QueryTable` / types).
   - `grid.columns`: **`{"type":"checkbox"}` first**, then `seq`, then data columns (edit/delete need row selection).
3. **`vben_menu_actions`**: **one row per toolbar button**. Critical: **`action_key` = toolbar JSON `key`** (e.g. `add`, `edit`, `deleteSelected`, `export`, `reload`). Set `form_code` and `requires_selection` on rows that open forms (`add` → `requires_selection=0`, `edit` → `1`).
4. **`vben_t_sys_role_menu_actions`**: grant each `menu_action_id` to **`系统管理员`** (unless the user asks for a different role).
5. **Idempotent delete order** (adjust to your fixed GUIDs):  
   `vben_t_sys_role_menu_actions` (this menu’s button ids) → `vben_menu_actions` (same) → `vben_form_desinger` (by `id`/`code`) → `vben_t_sys_role_menus` / `vben_menus_new` / `vben_entitylist_desinger` as needed → re-INSERT in reverse dependency order (form + list + menu + role menus + menu actions + role menu actions).

**Permission / alias note:** toolbar key for delete should be **`deleteSelected`** (alias **`delete`** is accepted in FE). Export key **`export`** (alias **`expol`**). See `ACTION_KEY_ALIASES` in `entityListFromDesigner.vue`.

## Latest runtime change (must know)

### Save target priority for FormFromDesigner modal

Status: **changed** in current codebase.

When clicking list toolbar Add/Edit (button has `form_code`), the save target is now resolved in this order:

1) `vben_form_desinger.schema_json.saveEntityName` / `primaryKey` (form config, highest priority)
2) fallback to list schema (`vben_entitylist_desinger.schema_json.saveEntityName` / `primaryKey`)
3) fallback to list `tableName` / `'id'`

Code location:

- `apps/web-antd/src/components/QueryTable/index.vue`
- function `openFormFromDesignerModal()`

### Practical rule

- Form `schema_json`: `saveEntityName` + `primaryKey` = real writable table (highest priority for modal save).
- List `tableName` = query object (view OK); list `saveEntityName` = fallback only.
- View list + different base table: resolve `saveEntityName` from view **`FROM`**, never by stripping `v_`; wrong `@save_entity` in `REPLACE` poisons list+form → **Must resolve** + **Case: 签卡** index.

## QueryTable dynamic modal pitfalls (`actionModule` → `openModal`)

When a toolbar handler returns `{ type: 'openModal', component: '...', props: {...} }`, `apps/web-antd/src/components/QueryTable/index.vue` mounts the target SFC inside **`Modal.confirm`** (`footer: null`, content = render function). The following bugs have **already happened** in this repo; avoid repeating them.

### 1) Vue 3 `h()` listeners vs `emit()` names (Cancel does nothing)

- In a **render function**, `h(Child, { onCancel: fn })` registers a listener for the component event named **`cancel`** (Vue maps `on` + `Cancel` → `cancel`).
- It does **not** listen to an event literally named `onCancel`.
- Therefore `emit('onCancel')` from the child **never** reaches `onCancel: fn` in the parent vnode → the outer `Modal.confirm` is not destroyed → **“取消” appears dead**.

**Convention in this repo (match existing modals):**

- Emit **`success`** and **`cancel`** (same as `FormFromDesignerModal`, `FormTabsTableContent`, demo `AddModal`).
- Parent `openModal` keeps `onSuccess` / `onCancel` on the vnode (these correctly map to `success` / `cancel`).

**Wrong (do not use for QueryTable-hosted modals):** `emit('onSuccess')`, `emit('onCancel')` unless the parent uses the rare `onOnSuccess` / `onOnCancel` vnode props.

### 2) Forced `height` on the inner component root (footer “falls out” of the white modal)

- The toolbar dispatcher used to merge **`style: { height: props.height || '500px' }`** into **all** `openModal` payloads. That object is spread onto the **async SFC root**, not onto `Modal.confirm`.
- Tall content (e.g. two grids + toolbar + footer buttons) **overflows** a 500px-tall root: the Ant Design modal body clips or scrolls oddly, and the **footer actions look like they sit on the mask** below the white panel.

**Fix pattern:**

- Do **not** apply a default fixed height to the inner component for every modal.
- Prefer **`bodyStyle: { maxHeight: '85vh', overflow: 'auto' }`** on `Modal.confirm` so scrolling happens in the **modal body**, while the inner page can grow naturally.
- If a specific legacy modal still needs a fixed height, pass an explicit `height` in that action’s `props` only, and document it (avoid global defaults).

### 3) Split “frame” props vs SFC props

- **`width`** is consumed by `Modal.confirm` and should **not** be spread onto the child (strip `width` before `h(AsyncComp, { ... })`) so it is not applied as a stray root attribute.
- **`title`** is still passed to the modal frame **and** often required by older modals as a **real prop** (e.g. `dynamic-modals/company/AddModal.vue` declares `title: string`). Do **not** strip `title` from child props unless every target component is audited.

### Quick verification

- [ ] Inner modal buttons **Cancel** / **Save** close or complete and call `modalInstance.destroy()`.
- [ ] Footer stays **visually inside** the modal white area when content is tall (scroll inside body, not a clipped inner root).

### Code locations (this repo)

- `openModal`: `apps/web-antd/src/components/QueryTable/index.vue`
- Example toolbar → modal: `apps/web-antd/src/views/EntityList/dataPowerPermissionActions.ts` → `attendance/DataPowerPermissionEditor.vue`

## SOP: trace old-system button chain (must follow)

Use this when user says: “old menu has a button (e.g. 重算), migrate to new system”.

### Step A. Find old menu and entity first

Query `t_sys_function` by menu name:

```sql
SELECT TOP 20 id,name,parent_id,sort,entity_name,url,page,path
FROM t_sys_function
WHERE name LIKE N'%关键词%'
ORDER BY sort;
```

Output to capture:
- `function_id` (old menu id)
- `entity_name`
- `url` (datagrid/treedatagrid/query params hint)

### Step B. Find old button definitions

Query `t_sys_function_operation` by `function_id`:

```sql
SELECT id,name,caption,action,custom_defing_script,sort,function_id
FROM t_sys_function_operation
WHERE function_id = '<function_id>'
ORDER BY sort;
```

Interpretation:
- `caption`: button label (e.g. 重算)
- `action`: usually JS entry (e.g. `fnUpdate()`, `fnEdit()`)
- `custom_defing_script`: custom script body (if present)

### Step C. Resolve actual backend behavior (stored procedure, etc.)

Because old `action=fnXxx()` often points to page JS not stored in DB:

1) Search DB modules for likely procedure names:
```sql
SELECT TOP 100 SCHEMA_NAME(p.schema_id) AS schema_name, p.name
FROM sys.procedures p
WHERE p.name LIKE '%Vacation%' OR p.name LIKE '%关键词%'
ORDER BY p.name;
```

2) If still unclear, search `sys.sql_modules` references:
```sql
SELECT OBJECT_NAME(m.object_id) AS object_name, o.type_desc
FROM sys.sql_modules m
JOIN sys.objects o ON o.object_id = m.object_id
WHERE m.definition LIKE '%candidate_proc_or_entity%';
```

3) Validate selected procedure definition:
- Use `sqlserver_get_procedure_definition` (or SSMS)
- confirm parameters and transactional side effects

### Step D. Decide new-system implementation path

#### D1. One-off endpoint (not recommended for many buttons)
- write dedicated controller API for that specific procedure

#### D2. Generic procedure-execution endpoint (recommended)
- add one backend API (e.g. `/api/Procedure/execute`)
- whitelist allowed proc prefixes/schema
- pass dynamic parameters
- return `code=0` format consistent with existing frontend request client

### Step E. Wire frontend button in designer list

Preferred pattern:
- list schema sets:
  - `actionModule = '/src/views/EntityList/stored-procedure.ts'`
  - `toolbar.actions[]` with:
    - `action = 'executeProcedure'`
    - `procedureName`
    - optional flags (`requiresSelection`, `selectionField`, `selectionParam`, `askYear`, `yearParam`, `staticParams`, `confirm`)

### Step F. Verify full chain

Checklist:
- button visible in list toolbar
- click button opens confirm / parameter prompt as expected
- API returns success (`code=0`)
- procedure effect reflected after grid reload
- no tab/layout regressions introduced

## Example mapping (already verified)

Old menu: `员工年假管理`

- `t_sys_function.id`: `15A044A9-6E52-4793-9AEE-ACE39DA0D7F0`
- button from `t_sys_function_operation`:
  - `caption='重算'`
  - `action='fnUpdate()'`
- resolved procedure: `dbo.att_pro_Vacation(@emp_id, @year)`

New mapping:
- API: `POST /api/Procedure/execute`
- FE: `src/views/EntityList/stored-procedure.ts`
- toolbar: `executeProcedure`, `procedureName='dbo.att_pro_Vacation'`, `requiresSelection=false`, `selectionParam='emp_id'` (empty when no rows), `askYear=true`, `yearParam='year'`

## Minimal input template (AI parses; user may reply in Chinese)

```text
MIGRATION_REQUEST
menu_name:
parent_menu:
page_type: designer | listFromDb | unknown
tree: yes | no | unknown
popup_crud: yes | no | unknown
special_buttons:
role: 系统管理员
constraints:  # e.g. fixed GUIDs, idempotent delete+insert, no FE changes
list_entity_or_view:   # REQUIRED or DB lookup — never guess
save_table_and_pk:     # REQUIRED if list is view — from VIEW definition FROM + describe_table
```

### What AI should output (expected deliverables)

- Preconditions: **Must resolve** satisfied; menu title alone → **no inferred** `saveEntityName`/PK.
- `migrate_full_*.sql`: list + menu + `vben_t_sys_role_menus` + if any toolbar keys → `vben_menu_actions` + `vben_t_sys_role_menu_actions`, idempotent.
- Popup CRUD: same script must include `vben_form_desinger` + toolbar + menu_actions + role_menu_actions (template **`migrate_full_法定假日设定.sql`**, **Gold standard**).
- Special buttons: SQL for actions + FE `actionModule` if needed (prefer generic `stored-procedure.ts` / shared patterns) + backend only if no generic API.
- Regressions: minimal **`fix_*.sql`**.
- User chat: point to **FE patterns** / **Must resolve** / **Case** index — **do not** re-expand those blocks each time.

### Example (filled)

```text
MIGRATION_REQUEST
menu_name: 员工年假管理
parent_menu: 考勤基础资料
page_type: designer
tree: no
popup_crud: no
special_buttons: 重算 stored proc
role: 系统管理员
constraints: idempotent delete+insert
list_entity_or_view: (from t_sys_function / DB)
save_table_and_pk: N/A if proc-only list
```


