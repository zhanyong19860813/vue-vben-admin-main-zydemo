/**
 * 组织选择通用弹窗（部门树 / 人员穿梭），供数据权限、流程等复用。
 *
 * @example
 * ```vue
 * <SelectDepartmentModal
 *   v-model:open="deptOpen"
 *   :default-checked-ids="[]"
 *   @confirm="(rows) => console.log(rows)"
 * />
 * <SelectPersonnelModal
 *   v-model:open="userOpen"
 *   :default-selected="[]"
 *   @confirm="(rows) => console.log(rows)"
 * />
 * ```
 */
export { default as SelectDepartmentModal } from './SelectDepartmentModal.vue';
export { default as SelectDeptManagerModal } from './SelectDeptManagerModal.vue';
export { default as SelectPersonnelModal } from './SelectPersonnelModal.vue';
export { default as SelectRoleModal } from './SelectRoleModal.vue';
export type { OrgDeptItem, OrgDeptManagerItem, OrgPersonnelItem, OrgRoleItem } from './types';
