# 员工入职登记：菜单、授权、按钮权限（脚本说明）

## 脚本文件

| 文件 | 作用 |
|------|------|
| `migrate_menu_hr_employee_onboarding.sql` | 写入三级菜单、系统管理员菜单授权、`vben_menu_actions` 工具栏按钮、`vben_t_sys_role_menu_actions` 按钮授权 |

在 **SQL Server** 上连接与 StoneApi 相同库后执行该脚本即可（可重复执行，幂等）。

## 涉及表与视图

1. **`vben_menus_new`**  
   - 三级：`人力资源` → `人事管理` → `员工入职登记`  
   - `path` 与前端路由一致：`/hr`、`/hr/personnel`、`/hr/personnel/employee-onboarding`  
   - 父级 `component` 为 `LAYOUT`，叶子为 `hr/employee-onboarding/index`  
   - `meta` 中带 `query.menuid`，叶子固定为 `A2000001-0001-4001-8001-000000000003`（与 `menuMeta.ts` 一致）

2. **`vben_t_sys_role_menus`**  
   - 将上述 **三个** 菜单 id 授权给角色 **`系统管理员`**（`bar_items='*'`, `operate_range_type='ALL'`）  
   - 登录后 `Menu/GetMenuFromDb` 通过视图 **`vben_v_user_role_menus`** 只返回当前用户角色可见菜单

3. **`vben_menu_actions`**  
   - 挂在 **叶子菜单** 上，一条记录对应一个工具栏按钮  
   - **`action_key`** 与前端 `HR_ONB_ACTION` 一致（见 `apps/web-antd/src/views/hr/employee-onboarding/menuMeta.ts`）

4. **`vben_t_sys_role_menu_actions`**  
   - 将每个按钮授权给 **系统管理员**  
   - 页面通过 `DynamicQueryBeta/queryforvben` 查视图 **`vben_v_user_role_menu_actions`**（`userid` + `menu_id`）得到当前用户可见的 `action_key`

## 按钮 action_key 一览

| action_key | 说明 |
|------------|------|
| `hr_onb_entry` | 员工入职 |
| `hr_onb_edit` | 修改 |
| `hr_onb_sync_dingtalk` | 同步钉钉 |
| `hr_onb_setdate` | 调整入职/转正日期 |
| `hr_onb_export` | 导出 |
| `hr_onb_print_card` | 工牌打印 |
| `hr_onb_print_archive` | 员工档案信息打印 |

> 库表 `vben_menu_actions.label` 长度为 50，脚本里部分文案做了缩短；界面完整文案由 Vue 模板控制。

## 给其他角色授权

1. **菜单**：在「角色管理」中给目标角色勾选上述三个菜单，或在 `vben_t_sys_role_menus` 中插入 `role_id` + `menus_id`（与脚本中三个 id 对应）。  
2. **按钮**：在 `vben_t_sys_role_menu_actions` 中插入 `role_id` + `menu_action_id` + `menu_id`（`menu_id` 为叶子 `A2000001-0001-4001-8001-000000000003`），或复用系统里「给角色分配按钮」的维护界面（若有）。

## 与静态路由的关系

仓库中 `apps/web-antd/src/router/routes/modules/hr.ts` 仍注册相同 path，便于无库菜单时的开发访问。  
若 **仅使用库表菜单**，可删除或精简该静态模块，避免侧边栏出现重复「人力资源」树。

## 执行后操作

重新登录（或刷新 token 后重新拉菜单），再打开「员工入职登记」验证工具栏是否按角色显示按钮。
