/**
 * 流程表单运行时：根据 schema 上 componentProps.workflowBuiltin 从登录用户填充默认值
 */
import type { VbenFormSchema } from '#/adapter/form';

import type { WorkflowBuiltinKind } from './form-designer.types';

function pad2(n: number): string {
  return String(n).padStart(2, '0');
}

/** 本地可读时间（YYYY-MM-DD HH:mm:ss），用作「时间戳」字段默认值 */
export function formatLocalDateTimeNow(): string {
  const d = new Date();
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

function yyMMdd(d: Date): string {
  return `${String(d.getFullYear()).slice(-2)}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}`;
}

/**
 * 从 userInfo 中取第一个非空值（兼容多种后端字段名）
 */
function pickUserField(u: Record<string, any>, keys: string[]): string {
  for (const k of keys) {
    const v = u[k];
    if (v !== undefined && v !== null && String(v).trim() !== '') return String(v).trim();
  }
  return '';
}

/** 是否为 GUID/UUID（避免把 userId、误写入库的 id 当成工号） */
function isLikelyGuidString(s: string): boolean {
  const t = s.trim();
  if (!t) return false;
  const unbrace = t.startsWith('{') && t.endsWith('}') ? t.slice(1, -1) : t;
  return /^[\da-f]{8}-[\da-f]{4}-[1-5][\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/i.test(unbrace);
}

/** 是否像登录账号/工号（OIDC 的 unique_name、JWT name 常为 A8425 这类，不能当「姓名」） */
export function looksLikeEmployeeOrLoginId(s: string): boolean {
  const t = s.trim();
  if (!t) return false;
  if (/[\u4e00-\u9fff]/.test(t)) return false;
  /** A8425、00123、X12345 等 */
  if (/^[A-Za-z]?\d{3,}$/.test(t)) return true;
  if (/^\d{4,}$/.test(t)) return true;
  if (/^[A-Za-z]{1,2}\d{4,}$/.test(t)) return true;
  return false;
}

/** 仅用于「姓名」内置字段：排除明显是工号/账号的 name 字段；无真实姓名时退回登录账号以免整表空白 */
function pickDisplayNameForBuiltin(u: Record<string, any>): string {
  const keys = [
    'realName',
    'name',
    'nickname',
    'displayName',
    'nickName',
    'RealName',
    'Name',
    'given_name',
    'family_name',
  ];
  for (const k of keys) {
    const v = u[k];
    if (v === undefined || v === null) continue;
    const s = String(v).trim();
    if (!s) continue;
    if (looksLikeEmployeeOrLoginId(s)) continue;
    return s;
  }
  return pickUserField(u, ['username', 'Username']);
}

/**
 * 工号：优先业务编码字段；跳过 GUID；绝不使用 userId/id 作为主数据 id
 */
function pickEmployeeNoField(u: Record<string, any>): string {
  const skipKeys = new Set(['userId', 'id', 'user_id', 'Id', 'UserId']);
  /** 先尝试明确「工号类」字段（非 GUID）；OIDC unique_name/preferred_username 常为登录工号 */
  const preferredOrder = [
    'employeeCode',
    'emp_code',
    'code',
    'userCode',
    'employeeNo',
    'workNo',
    'jobNo',
    'empNo',
    '工号',
    'Code',
    'EmployeeNo',
    'unique_name',
    'preferred_username',
    'username',
    'Username',
    'employee_id',
    'employeeId',
  ];
  for (const k of preferredOrder) {
    if (skipKeys.has(k)) continue;
    const v = u[k];
    if (v === undefined || v === null) continue;
    const s = String(v).trim();
    if (!s || isLikelyGuidString(s)) continue;
    return s;
  }
  return '';
}

export interface BuildWorkflowBuiltinValuesOptions {
  userInfo: Record<string, any> | null | undefined;
  /** 流程编号前缀，仅 flowNo 使用 */
  workflowNoPrefix?: string;
  /** 当前流程显示名称，flowTitle 内置项与按 label 注入「流程标题」使用 */
  processTitle?: string;
}

/** 设计器/草稿 JSON 常把「当前登录人…」当作默认值写入，合并时应视为未填并允许内置值覆盖 */
export function looksLikeWorkflowBuiltinPlaceholder(s: string): boolean {
  const t = String(s ?? '').trim();
  if (!t) return false;
  return /^当前登录人/.test(t);
}

function shouldFillBuiltinSlot(cur: any): boolean {
  if (cur === undefined || cur === null) return true;
  const s = String(cur).trim();
  if (s === '') return true;
  return looksLikeWorkflowBuiltinPlaceholder(s);
}

/**
 * `{ ...builtins, ...jsonDraft }` 后，草稿里的占位文案会覆盖真实内置值；按 schema 上 workflowBuiltin 恢复。
 */
export function restoreBuiltinValuesAfterJsonMerge(
  builtins: Record<string, any>,
  merged: Record<string, any>,
  schema: VbenFormSchema[],
): Record<string, any> {
  const out = { ...merged };
  for (const item of schema) {
    const fn = String((item as any).fieldName ?? '').trim();
    if (!fn) continue;
    const kind = (item as any).componentProps?.workflowBuiltin as WorkflowBuiltinKind | undefined;
    if (!kind) continue;
    if (!shouldFillBuiltinSlot(out[fn])) continue;
    const b = builtins[fn];
    if (b !== undefined && b !== null && String(b).trim() !== '') {
      out[fn] = b;
    } else {
      out[fn] = b ?? '';
    }
  }
  return out;
}

/**
 * 仅处理带 workflowBuiltin 的字段；用于新增表单打开时 setValues
 */
export function buildWorkflowBuiltinValuesFromUser(
  schema: VbenFormSchema[],
  options: BuildWorkflowBuiltinValuesOptions,
): Record<string, any> {
  const u = options.userInfo ?? {};
  const prefix = (options.workflowNoPrefix ?? 'WF').trim() || 'WF';
  const now = new Date();
  const ymd = yyMMdd(now);
  const ts = formatLocalDateTimeNow();
  /** 无后端流水时占位（四位随机），保存时可由服务端覆盖为真实流水 */
  const seq = String(Math.floor(1000 + Math.random() * 9000));
  const draftFlowNo = `${prefix}${ymd}${seq}`;

  const out: Record<string, any> = {};

  for (const item of schema) {
    const cp = (item as any).componentProps ?? {};
    const kind = cp.workflowBuiltin as WorkflowBuiltinKind | undefined;
    const fieldName = item.fieldName as string | undefined;
    if (!kind || !fieldName) continue;

    switch (kind) {
      case 'flowNo':
        out[fieldName] = draftFlowNo;
        break;
      case 'flowTitle':
        out[fieldName] = String(options.processTitle ?? '').trim();
        break;
      case 'userName':
        /** 姓名：勿用 unique_name/preferred_username/username（多为登录账号）；排除像工号的 name */
        out[fieldName] = pickDisplayNameForBuiltin(u);
        break;
      case 'employeeNo':
        out[fieldName] = pickEmployeeNoField(u);
        break;
      case 'dept':
        out[fieldName] = pickUserField(u, [
          'deptName',
          'deptLongName',
          'departmentName',
          'department_name',
          'DeptName',
          'organizationName',
          'organization_name',
          'orgName',
          'org_name',
          'dept',
          'department',
          'dept_name',
          'longDeptName',
          'long_name',
          '部门',
        ]);
        break;
      case 'position':
        out[fieldName] = pickUserField(u, [
          'positionName',
          'dutyName',
          'postName',
          'position',
          'post',
          'title',
          'jobTitle',
          'JobTitle',
          'DutyName',
          '岗位',
        ]);
        break;
      case 'timestamp':
        out[fieldName] = ts;
        break;
      default:
        break;
    }
  }

  return out;
}

/**
 * 主表字段若未带 workflowBuiltin（历史数据/复制表单），按中文 label 补一遍内置值，避免只显示 placeholder。
 */
export function supplementBuiltinValuesByFieldLabel(
  schema: VbenFormSchema[],
  values: Record<string, any>,
  userInfo: Record<string, any>,
  options: BuildWorkflowBuiltinValuesOptions,
): Record<string, any> {
  const u = userInfo ?? {};
  const out = { ...values };
  for (const item of schema) {
    const fn = String((item as any).fieldName ?? '').trim();
    if (!fn) continue;
    const cur = out[fn];
    if (!shouldFillBuiltinSlot(cur)) continue;
    const cp = (item as any).componentProps ?? {};
    if (cp.workflowBuiltin) continue;
    const label = String((item as any).label ?? '').trim();
    if (label === '姓名') {
      out[fn] = pickDisplayNameForBuiltin(u);
    } else if (label === '工号') {
      out[fn] = pickEmployeeNoField(u);
    } else if (label === '部门') {
      out[fn] = pickUserField(u, [
        'deptName',
        'deptLongName',
        'departmentName',
        'department_name',
        'DeptName',
        'organizationName',
        'organization_name',
        'orgName',
        'org_name',
        'dept',
        'department',
        'dept_name',
        'longDeptName',
        'long_name',
        '部门',
      ]);
    } else if (label === '岗位') {
      out[fn] = pickUserField(u, [
        'positionName',
        'dutyName',
        'postName',
        'position',
        'post',
        'title',
        'jobTitle',
        'JobTitle',
        'DutyName',
        '岗位',
      ]);
    } else if (label === '流程编号') {
      const prefix = (options.workflowNoPrefix ?? 'WF').trim() || 'WF';
      const now = new Date();
      const ymd = yyMMdd(now);
      const seq = String(Math.floor(1000 + Math.random() * 9000));
      out[fn] = `${prefix}${ymd}${seq}`;
    } else if (label === '时间戳') {
      out[fn] = formatLocalDateTimeNow();
    } else if (label === '流程标题') {
      out[fn] = String(options.processTitle ?? '').trim();
    }
  }
  return out;
}

/** 将当前流程名称写入 label 为「流程标题」的字段（未配置 workflowBuiltin 时的兼容） */
export function applyProcessTitleBySchemaLabel(
  schema: VbenFormSchema[],
  values: Record<string, any>,
  processTitle: string,
): Record<string, any> {
  const t = String(processTitle ?? '').trim();
  if (!t) return values;
  const out = { ...values };
  for (const item of schema) {
    const label = String((item as any).label ?? '').trim();
    const fn = String((item as any).fieldName ?? '').trim();
    if (!fn) continue;
    if (label === '流程标题' && (out[fn] === undefined || out[fn] === null || String(out[fn]).trim() === '')) {
      out[fn] = t;
    }
  }
  return out;
}
