/** 部门树节点（确定时返回） */
export type OrgDeptItem = {
  id: string;
  name: string;
  parentId: string | null;
};

/** 人员选择结果（与 v_t_base_employee.id 对齐，便于存库） */
export type OrgPersonnelItem = {
  id: string;
  empId: string;
  name: string;
  deptName?: string;
  dutyName?: string;
};
