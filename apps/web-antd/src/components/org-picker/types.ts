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

/** 角色选择结果（系统角色） */
export type OrgRoleItem = {
  id: string;
  name: string;
};

/** 部门主管范围选择结果（选择部门范围，运行时按部门取主管） */
export type OrgDeptManagerItem = {
  deptId: string;
  deptName: string;
  parentId: string | null;
  managerEmpIds?: string[];
  managerNames?: string[];
};
