/**
 * 与 SQL 脚本 `scripts/sql/migrate_menu_hr_employee_onboarding.sql` 中叶子菜单 id 保持一致。
 * 用于 route.meta.query.menuid 与按钮权限查询（vben_v_user_role_menu_actions）。
 */
export const HR_EMPLOYEE_ONBOARDING_LEAF_MENU_ID =
  'A2000001-0001-4001-8001-000000000003';

/** 与 vben_menu_actions.action_key 一致 */
export const HR_ONB_ACTION = {
  entry: 'hr_onb_entry',
  edit: 'hr_onb_edit',
  syncDingTalk: 'hr_onb_sync_dingtalk',
  setDate: 'hr_onb_setdate',
  export: 'hr_onb_export',
  printCard: 'hr_onb_print_card',
  printArchive: 'hr_onb_print_archive',
} as const;
