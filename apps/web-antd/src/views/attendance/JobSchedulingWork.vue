<script setup lang="ts">
/**
 * 排班作业（硬编码页）
 * 老系统：ExtendPage/att/jobScheduling_datagrid.aspx?entity=v_att_lst_JobScheduling
 *
 * 新系统目标（MVP）：
 * 1) 按月+分页查看宽表：Day1_Name ~ Day31_Name
 * 2) 点击「编辑」：弹窗里为该员工选择每天班次（BCID -> code_name）；可选班次 = 当前登录人在 v_att_lst_ShiftsSetting 的权限（与老系统一致），管理员可走班次主数据全量
 * 3) 保存到 att_lst_JobScheduling（primaryKey=FID）
 */
import { computed, h, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue';
import {
  Button,
  Checkbox,
  DatePicker,
  Input,
  Modal,
  Select,
  Space,
  Table,
  Upload,
  message,
} from 'ant-design-vue';
import type { UploadProps } from 'ant-design-vue';
import type { TableColumnsType } from 'ant-design-vue';
import dayjs from 'dayjs';
import { useUserStore } from '@vben/stores';
import { SelectPersonnelModal } from '#/components/org-picker';
import type { OrgPersonnelItem } from '#/components/org-picker';
import {
  clientApplySchedulingByTime,
  loadStatutoryHolidayDateSet,
  queryForVben,
  queryForVbenOptional,
  queryForVbenPaged,
  saveDatasaveMulti,
  whereAnd,
  whereOr,
} from './shiftBcSettingApi';
import {
  commitJobSchedulingImport,
  previewJobSchedulingImport,
  type JobImportPreviewError,
} from './jobSchedulingImportApi';

const userStore = useUserStore();
const operatorName = () => {
  const u: any = userStore.userInfo ?? {};
  return String(u.realName ?? u.name ?? u.username ?? u.userName ?? '').trim() || 'system';
};

const ZERO_UUID = '00000000-0000-0000-0000-000000000000';

/** 调试：控制台过滤 `[排班作业]`；确认无问题后改为 false */
const JOB_SCHED_DEBUG = true;
function jobSchedLog(...args: unknown[]) {
  if (!JOB_SCHED_DEBUG) return;
  // eslint-disable-next-line no-console
  console.log('[排班作业]', ...args);
}

function getDefaultJsMonth() {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, '0');
  return `${y}${m}`;
}

const jsMonthInput = ref<string>(getDefaultJsMonth());
const empNameKeyword = ref<string>('');
const deptKeyword = ref<string>('');

function isValidJsMonth(v: string) {
  return /^\d{6}$/.test(v.trim());
}

function jsMonthToDays(v: string) {
  const s = v.trim();
  if (!isValidJsMonth(s)) return 31;
  const year = Number(s.slice(0, 4));
  const month = Number(s.slice(4, 6)); // 1-12
  if (!Number.isFinite(year) || !Number.isFinite(month)) return 31;
  return new Date(year, month, 0).getDate();
}

/** 与 JS Date.getDay() 一致：0=周日 … 6=周六 */
const CN_WEEKDAY_CHARS = ['日', '一', '二', '三', '四', '五', '六'] as const;

/** 列头：上行完整日期 YYYY-MM-DD，下行星期（法定节假日加 △，对齐老系统） */
function renderJobSchedDayColumnTitle(
  dayNum: number,
  jsMonth: string,
  holidays: Set<string>,
) {
  const m = jsMonth.trim();
  if (!isValidJsMonth(m)) {
    return h('div', { class: 'job-sched-day-th' }, [
      h('div', { class: 'job-sched-day-th-date' }, `${dayNum}号`),
      h('div', { class: 'job-sched-day-th-week' }, ''),
    ]);
  }
  const year = Number(m.slice(0, 4));
  const month = Number(m.slice(4, 6));
  const dim = new Date(year, month, 0).getDate();
  if (dayNum > dim) {
    return h('div', { class: 'job-sched-day-th job-sched-day-th--invalid' }, [
      h('div', { class: 'job-sched-day-th-date' }, '—'),
      h('div', { class: 'job-sched-day-th-week' }, ''),
    ]);
  }
  const dt = dayjs(new Date(year, month - 1, dayNum));
  const ymd = dt.format('YYYY-MM-DD');
  const wch = CN_WEEKDAY_CHARS[dt.day()];
  const hol = holidays.has(ymd);
  return h('div', { class: 'job-sched-day-th' }, [
    h('div', { class: 'job-sched-day-th-date' }, ymd),
    h('div', { class: 'job-sched-day-th-week' }, hol ? `${wch}△` : wch),
  ]);
}

/** 与当前表格数据一致的月份（上次「查询/刷新/翻页/产生排班后刷新」成功写入 YYYYMM）。列头、节假日 △ 只跟它走，不跟输入框实时值。 */
const gridJsMonth = ref<string>('');

/** 当年法定节假日（YYYY-MM-DD），用于表头 △；随 gridJsMonth 年份拉取 */
const statutoryHolidaySet = ref<Set<string>>(new Set());
const headerEpoch = ref(0);
let holidayLoadSerial = 0;

watch(
  () => gridJsMonth.value.trim(),
  async (m) => {
    const serial = ++holidayLoadSerial;
    if (!isValidJsMonth(m)) {
      if (serial === holidayLoadSerial) {
        statutoryHolidaySet.value = new Set();
        headerEpoch.value++;
      }
      return;
    }
    const year = m.slice(0, 4);
    const set = await loadStatutoryHolidayDateSet(year);
    if (serial !== holidayLoadSerial) return;
    statutoryHolidaySet.value = set;
    headerEpoch.value++;
  },
  { immediate: true },
);

const pageSize = ref(15);
const page = ref(1);
const total = ref(0);
const loading = ref(false);

type JobRow = Record<string, any>;
const rows = ref<JobRow[]>([]);

// ---------- 班次选项：与老系统一致，按「当前登录账号」在人员班次权限中的工号过滤 ----------

function normalizeRoleToken(role: unknown): string {
  if (role == null) return '';
  if (typeof role === 'string') return role.trim();
  if (typeof role === 'object') {
    const o = role as Record<string, unknown>;
    if (typeof o.value === 'string') return o.value.trim();
    if (typeof o.name === 'string') return o.name.trim();
    if (typeof o.roleName === 'string') return o.roleName.trim();
  }
  return String(role).trim();
}

function collectLoginRoleStrings(): string[] {
  const u: any = userStore.userInfo ?? {};
  const raw = u.roles ?? userStore.userRoles ?? [];
  if (!Array.isArray(raw)) return [];
  return raw.map(normalizeRoleToken).filter(Boolean);
}

/** 系统管理员等：可使用班次主数据（与班次设定树同源），不限定本人 EMP_ID */
function operatorMayUseAllShifts(): boolean {
  const u: any = userStore.userInfo ?? {};
  if (u.isAdmin === true || u.admin === true || u.superAdmin === true) return true;
  const roles = collectLoginRoleStrings();
  return roles.some(
    (r) =>
      r === '系统管理员' ||
      r.toLowerCase() === 'admin' ||
      r.toLowerCase().includes('administrator') ||
      r.toLowerCase() === 'superadmin',
  );
}

/**
 * 与人员班次权限视图对齐：视图中「工号」=EMP_ID，「登录账号」=username，二者常一致但匹配须兼顾。
 * 注意：User/info 里 employee_id 多为员工表数字主键，与 EMP_ID（如 A8425）不同，不能优先用它去查班次权限。
 */
function collectOperatorIdentityCandidates(): string[] {
  const u: any = userStore.userInfo ?? {};
  const keys = [
    'username',
    'userName',
    'loginAccount',
    'account',
    'EMP_ID',
    'empId',
    'emp_id',
    'employeeCode',
    'empCode',
    'userCode',
    'code',
    '工号',
    'employee_id',
  ];
  const out: string[] = [];
  const seen = new Set<string>();
  for (const k of keys) {
    const s = String(u[k] ?? '').trim();
    if (!s) continue;
    const low = s.toLowerCase();
    if (seen.has(low)) continue;
    seen.add(low);
    out.push(s);
  }
  return out;
}

function resolveOperatorEmpId(): string {
  return collectOperatorIdentityCandidates()[0] ?? '';
}

function isLikelyGuidToken(s: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s.trim());
}

async function fetchPermittedShiftSourceRows(): Promise<any[]> {
  const candidates = collectOperatorIdentityCandidates().filter((id) => id && !isLikelyGuidToken(id));

  for (const id of candidates) {
    try {
      const rows = await queryForVben({
        TableName: 'v_att_lst_ShiftsSetting',
        Page: 1,
        PageSize: 5000,
        SortBy: 'code_name',
        SortOrder: 'asc',
        Where: whereOr([
          { Field: 'EMP_ID', Operator: 'contains', Value: id },
          { Field: 'username', Operator: 'contains', Value: id },
        ]),
      });
      if (rows?.length) return rows;
    } catch {
      /* 换下一候选或交由管理员分支 */
    }
  }

  if (operatorMayUseAllShifts()) {
    const master = await queryForVbenOptional({
      TableName: 'v_t_att_lst_BC_set_code',
      Page: 1,
      PageSize: 5000,
      SortBy: 'code_name',
      SortOrder: 'asc',
    });
    if (master.length) return master;
    try {
      return await queryForVben({
        TableName: 'v_att_lst_ShiftsSetting',
        Page: 1,
        PageSize: 5000,
        SortBy: 'code_name',
        SortOrder: 'asc',
      });
    } catch {
      return [];
    }
  }
  return [];
}

function buildShiftOptionsFromQueryRows(items: any[]): {
  options: Array<{ label: string; value: string }>;
  nameById: Map<string, string>;
} {
  const map = new Map<string, string>();
  for (const r of items ?? []) {
    const bcid = String(r?.BCID ?? r?.bcid ?? r?.FID ?? r?.id ?? '').trim();
    // name 列为员工姓名，不能当作班次名；优先 code_name / BCName
    const label = String(
      r?.code_name ?? r?.Code_name ?? r?.BCName ?? r?.bcName ?? '',
    ).trim();
    if (!bcid) continue;
    const display = label || bcid;
    map.set(bcid, display);
  }
  const nextOptions: Array<{ label: string; value: string }> = [{ value: ZERO_UUID, label: '空' }];
  const nextNameById = new Map<string, string>([[ZERO_UUID, '']]);
  for (const [bcid, label] of map.entries()) {
    nextOptions.push({ value: bcid, label });
    nextNameById.set(bcid, label);
  }
  return { options: nextOptions, nameById: nextNameById };
}

/** 合并该行已有排班（可能不在本人权限表内），避免下拉无法展示/保存历史班次名 */
function mergeRowExistingShiftsIntoOptions(
  row: JobRow | null | undefined,
  options: Array<{ label: string; value: string }>,
  nameById: Map<string, string>,
): { options: Array<{ label: string; value: string }>; nameById: Map<string, string> } {
  if (!row) return { options, nameById };
  const nextOpts = [...options];
  const nextMap = new Map(nameById);
  for (let d = 1; d <= 31; d++) {
    const id = String(row[`Day${d}_ID`] ?? '').trim();
    const nm = String(row[`Day${d}_Name`] ?? '').trim();
    if (!id || id === ZERO_UUID) continue;
    if (nextMap.has(id)) continue;
    const label = nm || id;
    nextMap.set(id, label);
    nextOpts.push({ value: id, label });
  }
  return { options: nextOpts, nameById: nextMap };
}

const generateOpen = ref(false);
const pickerOpen = ref(false);
const generateLoading = ref(false);
const scheduleStartDate = ref<string>('');
const scheduleEndDate = ref<string>('');
const keepWeek6 = ref(false);
const keepWeek7 = ref(false);
const keepHoliday = ref(false);
const selectedPeople = ref<OrgPersonnelItem[]>([]);
const generateShiftId = ref<string>('');
const generateShiftOptions = ref<Array<{ label: string; value: string }>>([]);

function getRowId(record: JobRow): string {
  return String(record?.FID ?? record?.id ?? record?.key ?? '').trim();
}

/**
 * 当前页行号：必须以 record 在 rows 中的位置为准。
 * 部分环境下 customRender 的 index/renderIndex 不可靠（误传会导致选中永远对不上，表现为“拖选没反应”）。
 */
function resolveRowIndex(record: JobRow, index?: number, renderIndex?: number): number {
  const byRef = rows.value.findIndex((r) => r === record);
  if (byRef >= 0) return byRef;
  const id = getRowId(record);
  if (id) {
    const i = rows.value.findIndex((r) => getRowId(r) === id);
    if (i >= 0) return i;
  }
  if (typeof renderIndex === 'number' && !Number.isNaN(renderIndex)) return renderIndex;
  if (typeof index === 'number' && !Number.isNaN(index)) return index;
  return -1;
}

async function loadRows(nextPage = 1) {
  const jsMonth = jsMonthInput.value.trim();
  if (!isValidJsMonth(jsMonth)) {
    message.warning('JS_Month 格式应为 YYYYMM，例如 202507');
    return;
  }
  loading.value = true;
  try {
    const nameKw = empNameKeyword.value.trim();
    const deptKw = deptKeyword.value.trim();
    const whereConds: any[] = [{ Field: 'JS_Month', Operator: 'contains', Value: jsMonth }];
    if (nameKw) {
      whereConds.push({ Field: 'name', Operator: 'contains', Value: nameKw });
    }
    if (deptKw) {
      // 后端视图上“部门/班组”列 dataIndex=long_name，这里用 contains 模糊匹配
      whereConds.push({ Field: 'long_name', Operator: 'contains', Value: deptKw });
    }
    const res = await queryForVbenPaged({
      TableName: 'v_att_lst_JobScheduling',
      Page: nextPage,
      PageSize: pageSize.value,
      SortBy: 'EMP_ID',
      SortOrder: 'asc',
      // JS_Month 是 char(20) 且带空格；用 contains 避免精确匹配失败
      Where: whereAnd(whereConds),
    });
    rows.value = res.items;
    gridJsMonth.value = jsMonth;
    // 翻页/刷新后清空选择矩形，避免选中状态落在旧数据上
    selectionStartRowIndex.value = null;
    selectionEndRowIndex.value = null;
    selectionStartDay.value = null;
    selectionEndDay.value = null;
    selectionVersion.value++;
    total.value = res.total;
    page.value = nextPage;
  } catch (e: any) {
    message.error(e?.message || '加载排班数据失败');
  } finally {
    loading.value = false;
  }
}

function openGenerateModal() {
  const days = jsMonthToDays(jsMonthInput.value);
  const y = jsMonthInput.value.slice(0, 4);
  const m = jsMonthInput.value.slice(4, 6);
  if (y && m) {
    scheduleStartDate.value = `${y}-${m}-01`;
    scheduleEndDate.value = `${y}-${m}-${String(days).padStart(2, '0')}`;
  }
  selectedPeople.value = [];
  if (!generateShiftOptions.value.length) {
    void loadGenerateShiftOptions();
  }
  generateOpen.value = true;
}

function onPickedPeople(items: OrgPersonnelItem[]) {
  const map = new Map<string, OrgPersonnelItem>();
  for (const p of selectedPeople.value) map.set(p.id, p);
  for (const p of items) map.set(p.id, p);
  selectedPeople.value = [...map.values()];
}

function removePeople() {
  selectedPeople.value = [];
}

async function submitGenerate() {
  if (!scheduleStartDate.value || !scheduleEndDate.value) {
    message.warning('请选择排班时间范围');
    return;
  }
  if (!selectedPeople.value.length) {
    message.warning('请先增加人员');
    return;
  }
  if (!generateShiftId.value) {
    message.warning('请选择班次');
    return;
  }
  const shiftOpt = generateShiftOptions.value.find((x) => x.value === generateShiftId.value);
  if (!shiftOpt) {
    message.warning('班次无效，请重新选择');
    return;
  }
  const empIds = selectedPeople.value
    .map((p) => String(p.empId ?? '').trim())
    .filter(Boolean);
  if (!empIds.length) {
    message.warning('选中人员缺少工号，无法产生排班');
    return;
  }
  generateLoading.value = true;
  try {
    const startDate = scheduleStartDate.value.replaceAll('-', '');
    const endDate = scheduleEndDate.value.replaceAll('-', '');
    if (startDate.length !== 8 || endDate.length !== 8) {
      message.warning('排班时间格式无效');
      return;
    }
    const monthFromRange = startDate.slice(0, 6);
    if (monthFromRange !== jsMonthInput.value.trim()) {
      message.warning('产生排班的月份须与上方「查询月份」一致');
      return;
    }

    await clientApplySchedulingByTime({
      bcCode: generateShiftId.value,
      bcName: shiftOpt.label,
      startDate,
      endDate,
      empIds,
      modifier: operatorName(),
      excludeSat: keepWeek6.value,
      excludeSun: keepWeek7.value,
      excludePublicHoliday: keepHoliday.value,
    });
    message.success(`产生排班成功：${selectedPeople.value.length} 人`);
    generateOpen.value = false;
    await loadRows(page.value);
  } catch (e: any) {
    message.error(e?.message || '产生排班失败');
  } finally {
    generateLoading.value = false;
  }
}

// -------------------- 单元格交互：任意拖动选中矩形 + 右键班次菜单 --------------------
const isSelectingCells = ref(false);

// 选择矩形（限定在当前分页可见行内）
const selectionStartRowIndex = ref<number | null>(null);
const selectionEndRowIndex = ref<number | null>(null);
const selectionStartDay = ref<number | null>(null);
const selectionEndDay = ref<number | null>(null);
// ant-table 的 customRender 不一定会因为“外部 ref 变化”而刷新单元格；
// 用这个版本号确保选中态变化时触发表格渲染
const selectionVersion = ref(0);

const contextMenuVisible = ref(false);
const contextMenuX = ref(0);
const contextMenuY = ref(0);
const contextMenuSaving = ref(false);
let onMouseUpHandler: (() => void) | null = null;
let onDocClickHandler: (() => void) | null = null;

// 拖拽用：避免依赖 ant-table 内的 mouseenter/mouseover（快速拖动时经常丢失）
let onDragMoveHandler: ((ev: MouseEvent) => void) | null = null;
let onDragUpHandler: (() => void) | null = null;
let didDragSelection = false; // 用于区分“点击选中单格” vs “拖拽选中矩形”
let suppressNextClick = false; // 拖拽结束后，避免 click(inner) 把矩形缩回单格

function stopDragSelection() {
  isSelectingCells.value = false;
  if (onDragMoveHandler) window.removeEventListener('mousemove', onDragMoveHandler);
  if (onDragUpHandler) window.removeEventListener('mouseup', onDragUpHandler);
}

function getSelectionRect(): { rowStart: number; rowEnd: number; dayStart: number; dayEnd: number } | null {
  if (selectionStartRowIndex.value === null || selectionEndRowIndex.value === null) return null;
  if (selectionStartDay.value === null || selectionEndDay.value === null) return null;
  return {
    rowStart: Math.min(selectionStartRowIndex.value, selectionEndRowIndex.value),
    rowEnd: Math.max(selectionStartRowIndex.value, selectionEndRowIndex.value),
    dayStart: Math.min(selectionStartDay.value, selectionEndDay.value),
    dayEnd: Math.max(selectionStartDay.value, selectionEndDay.value),
  };
}

function isCellSelected(rowIndex: number, day: number) {
  const rect = getSelectionRect();
  if (!rect) return false;
  return rowIndex >= rect.rowStart && rowIndex <= rect.rowEnd && day >= rect.dayStart && day <= rect.dayEnd;
}

function setSelectionToCell(rowIndex: number, day: number) {
  selectionStartRowIndex.value = rowIndex;
  selectionEndRowIndex.value = rowIndex;
  selectionStartDay.value = day;
  selectionEndDay.value = day;
  selectionVersion.value++;
  jobSchedLog('setSelectionToCell', { rowIndex, day, ver: selectionVersion.value, rect: getSelectionRect() });
}

function handleCellMouseDown(e: MouseEvent, rowIndex: number, day: number) {
  if (e.button !== 0) return; // only left
  e.preventDefault();
  e.stopPropagation();

  jobSchedLog('mousedown', { rowIndex, day, target: (e.target as HTMLElement)?.tagName });

  didDragSelection = false;
  stopDragSelection();
  isSelectingCells.value = true;
  suppressNextClick = false;
  setSelectionToCell(rowIndex, day);

  let dragMoveCount = 0;
  // 全局计算落点，保证拖拽过程中任意经过的格子都会触发选中更新
  onDragMoveHandler = (ev: MouseEvent) => {
    if (!isSelectingCells.value) return;
    if (selectionStartRowIndex.value === null || selectionStartDay.value === null) return;

    dragMoveCount++;
    const el = document.elementFromPoint(ev.clientX, ev.clientY) as HTMLElement | null;
    const td = el?.closest?.('td[data-job-day]') as HTMLElement | null;
    if (!td) {
      if (dragMoveCount <= 3 || dragMoveCount % 20 === 0) {
        jobSchedLog('mousemove(no td)', { x: ev.clientX, y: ev.clientY, tag: el?.tagName });
      }
      return;
    }

    const rStr = td.getAttribute('data-row-index');
    const dStr = td.getAttribute('data-job-day');
    const r = rStr ? Number(rStr) : NaN;
    const d = dStr ? Number(dStr) : NaN;
    if (!Number.isFinite(r) || !Number.isFinite(d)) return;
    if (r < 0) return;

    // 一旦拖到了起点之外，就认为是“拖拽”
    if (r !== selectionStartRowIndex.value || d !== selectionStartDay.value) didDragSelection = true;

    if (selectionEndRowIndex.value !== r || selectionEndDay.value !== d) {
      jobSchedLog('mousemove(命中格子)', { r, d, dragMoveCount });
      selectionEndRowIndex.value = r;
      selectionEndDay.value = d;
      selectionVersion.value++;
    }
  };

  onDragUpHandler = () => {
    jobSchedLog('mouseup(结束拖选)', { didDragSelection, rect: getSelectionRect() });
    suppressNextClick = true;
    stopDragSelection();
  };

  window.addEventListener('mousemove', onDragMoveHandler);
  window.addEventListener('mouseup', onDragUpHandler);
}

function closeContextMenu() {
  contextMenuVisible.value = false;
}

async function handleCellContextMenu(e: MouseEvent, record: JobRow, rowIndex: number, day: number) {
  e.preventDefault();
  e.stopPropagation();

  jobSchedLog('rightclick', { rowIndex, day, rect: getSelectionRect() });

  // 右键点的单元格不在选中矩形内，则把矩形重置成该单元格
  if (!isCellSelected(rowIndex, day)) {
    setSelectionToCell(rowIndex, day);
  }

  const empId = String(record?.EMP_ID ?? '').trim();
  if (!empId) {
    message.warning('缺少员工工号 EMP_ID');
    return;
  }

  contextMenuSaving.value = false;
  await loadShiftOptionsForCurrentOperator(undefined, true);
  if (shiftOptions.value.length <= 1) {
    message.warning('当前账号无可用班次权限，无法选择班次');
    return;
  }

  const rawX = e.clientX;
  const rawY = e.clientY;
  const menuW = 260;
  const menuH = 320;
  contextMenuX.value = Math.min(rawX, window.innerWidth - menuW);
  contextMenuY.value = Math.min(rawY, window.innerHeight - menuH);
  contextMenuVisible.value = true;
}

async function applyShiftToSelectedCells(shiftId: string) {
  const rect = getSelectionRect();
  if (!rect) return;

  const shiftName = shiftNameById.value.get(shiftId) ?? '';

  contextMenuSaving.value = true;
  closeContextMenu();

  // 组织待更新数据：对矩形覆盖范围内所有行一次性保存
  const rowStart = Math.max(0, rect.rowStart);
  const rowEnd = Math.min(rows.value.length - 1, rect.rowEnd);
  const dayStart = Math.max(1, rect.dayStart);
  const dayEnd = Math.min(31, rect.dayEnd);

  const payloads: Record<string, any>[] = [];

  for (let i = rowStart; i <= rowEnd; i++) {
    const row = rows.value[i];
    if (!row) continue;
    const payloadFid = row.FID ?? row.id ?? row.key ?? '';
    if (!payloadFid) continue;

    const jsMonth = String(row?.JS_Month ?? '').trim();
    const daysInMonth = jsMonthToDays(jsMonth);
    const realDayEnd = Math.min(dayEnd, daysInMonth);

    const payload: Record<string, any> = {
      FID: payloadFid,
      EMP_ID: row.EMP_ID,
      JS_Month: row.JS_Month,
      modifier: operatorName(),
    };

    for (let d = 1; d <= 31; d++) {
      const target = d >= dayStart && d <= realDayEnd;
      const nextId = target ? shiftId : String(row?.[`Day${d}_ID`] ?? '').trim() || ZERO_UUID;
      const nextName = target ? shiftName : String(row?.[`Day${d}_Name`] ?? '').trim();
      payload[`Day${d}_ID`] = nextId;
      payload[`Day${d}_Name`] = nextName;

      // 乐观更新 UI（当前页显示）
      if (target) {
        row[`Day${d}_ID`] = nextId;
        row[`Day${d}_Name`] = nextName;
      }
    }

    payloads.push(payload);
  }

  if (!payloads.length) {
    contextMenuSaving.value = false;
    message.warning('没有可保存的选中单元格');
    return;
  }

  try {
    await saveDatasaveMulti([
      {
        tableName: 'att_lst_JobScheduling',
        primaryKey: 'FID',
        data: payloads,
        deleteRows: [],
      },
    ]);
    message.success('班次已应用');
    await loadRows(page.value);
  } catch (e: any) {
    message.error(e?.message || '保存失败');
    await loadRows(page.value);
  } finally {
    contextMenuSaving.value = false;
  }
}

function buildDayColumns(): TableColumnsType<JobRow> {
  /** 并入列 key，强制 ant-table 在选中变化时重绘单元格（仅改 customRender 常被内部缓存吃掉） */
  const ver = selectionVersion.value;
  const hdr = headerEpoch.value;
  const jsMonth = gridJsMonth.value;
  const holidays = statutoryHolidaySet.value;

  const cols: TableColumnsType<JobRow> = [
    { title: '工号', dataIndex: 'EMP_ID', key: 'EMP_ID', fixed: 'left', width: 72 },
    {
      title: '姓名',
      key: 'employee',
      dataIndex: 'name',
      fixed: 'left',
      width: 85,
      ellipsis: true,
      customRender: ({ text }) => {
        const nm = String(text ?? '').trim();
        return h('span', { style: 'font-weight:600;' }, nm || '--');
      },
    },
    {
      title: '部门/班组',
      key: 'dept',
      dataIndex: 'long_name',
      fixed: 'left',
      width: 105,
      ellipsis: true,
    },
  ];

  // 宽表：Day1_Name ~ Day31_Name（列头：年月日 + 星期，法定假日 △）
  for (let d = 1; d <= 31; d++) {
    cols.push({
      title: renderJobSchedDayColumnTitle(d, jsMonth, holidays),
      key: `Day${d}_Name__v${ver}__h${hdr}`,
      dataIndex: `Day${d}_Name`,
      width: 120,
      ellipsis: true,
      customHeaderCell: () => ({ class: 'job-sched-th-day' }),
      // data-* / class 放在 td（拖选用 elementFromPoint）；点击事件放在内层 div，避免 vc-table 合并 td 属性时丢事件
      customCell: (record, rowIndex) => {
        const r = typeof rowIndex === 'number' && !Number.isNaN(rowIndex) ? rowIndex : -1;
        const selected = r >= 0 && isCellSelected(r, d);
        return {
          class: ['job-sched-day-cell', selected ? 'day-cell-selected' : ''].filter(Boolean),
          'data-row-index': String(r),
          'data-job-day': String(d),
          style: selected
            ? {
                background: 'rgba(255, 77, 79, 0.35)',
                boxShadow: 'inset 0 0 0 1px rgba(207, 19, 34, 0.45)',
              }
            : undefined,
        };
      },
      customRender: ({ text, record, index, renderIndex }) => {
        const rowIndex =
          typeof index === 'number' && !Number.isNaN(index)
            ? index
            : resolveRowIndex(record, index, renderIndex);
        const s = String(text ?? '').trim();
        const selected = rowIndex >= 0 && isCellSelected(rowIndex, d);
        // 选中态只靠 td 的红色矩形体现：不要把红色涂到中间的“文字/时间块”
        const pillClass = !s ? 'shift-pill shift-pill-empty' : 'shift-pill';

        return h(
          'div',
          {
            class: 'day-cell-inner',
            // 红色只在 td 层；这里不再对内层 div 增加背景，避免“中间文字上面也变红”
            style: undefined,
            onMousedown: (ev: MouseEvent) => {
              if (rowIndex < 0) {
                jobSchedLog('inner mousedown 跳过 rowIndex<0', { index, renderIndex });
                return;
              }
              handleCellMouseDown(ev, rowIndex, d);
            },
            onClick: (ev: MouseEvent) => {
              jobSchedLog('click(inner)', { rowIndex, day: d, didDragSelection });
              if (rowIndex < 0) return;
              if (ev.button !== 0) return;
              if (suppressNextClick) {
                suppressNextClick = false;
                return;
              }
              if (didDragSelection) return;
              ev.preventDefault();
              ev.stopPropagation();
              setSelectionToCell(rowIndex, d);
              isSelectingCells.value = false;
            },
            onContextmenu: (ev: MouseEvent) => {
              if (rowIndex < 0) return;
              void handleCellContextMenu(ev, record, rowIndex, d);
            },
          },
          [h('span', { class: pillClass }, !s ? '--' : s)],
        );
      },
    });
  }

  // 与老系统 grid 对齐：修改人、修改时间、应/上/休（视图字段 modifier / modifyTime / FulldaysValue）
  cols.push(
    {
      title: '修改人',
      key: 'modifier',
      dataIndex: 'modifier',
      width: 96,
      ellipsis: true,
      customRender: ({ text }) => {
        const s = String(text ?? '').trim();
        return s || '--';
      },
    },
    {
      title: '修改时间',
      key: 'modifyTime',
      dataIndex: 'modifyTime',
      width: 168,
      customRender: ({ text }) => {
        if (text == null || text === '') return '--';
        const d = dayjs(text as string | Date);
        return d.isValid() ? d.format('YYYY-MM-DD HH:mm:ss') : String(text);
      },
    },
    {
      title: '应/上/休',
      key: 'FulldaysValue',
      dataIndex: 'FulldaysValue',
      width: 112,
      ellipsis: true,
      customRender: ({ text }) => {
        const s = String(text ?? '').trim();
        return s || '--';
      },
    },
  );

  return cols;
}

const columns = computed(() => {
  // 选中矩形 / 已查询月份或节假日加载后强制重算 columns，让表头与单元格 customRender 重跑
  selectionVersion.value;
  headerEpoch.value;
  gridJsMonth.value;
  return buildDayColumns();
});

// -------------------- 编辑弹窗 --------------------

const editOpen = ref(false);
const editSaving = ref(false);
const editRow = ref<JobRow | null>(null);
/** 编辑弹窗天数与当前表格月份一致（未成功查询过时为空串，按 31 天兜底） */
const editDaysInMonth = computed(() => jsMonthToDays(gridJsMonth.value));

type ShiftOpt = { value: string; label: string };
const shiftOptions = ref<ShiftOpt[]>([]);
const shiftNameById = ref<Map<string, string>>(new Map());

// day -> BCID
const draftDayIds = reactive<Record<number, string>>({});
const uniformShiftId = ref<string>(''); // 用于“一键填充”

function clearDraft() {
  Object.keys(draftDayIds).forEach((k) => delete draftDayIds[Number(k)]);
  uniformShiftId.value = '';
}

/**
 * 右键菜单 / 编辑弹窗：班次列表 = 当前登录人在「人员班次权限」中的班次；编辑时合并该行已有排班 ID 以便展示名称。
 */
async function loadShiftOptionsForCurrentOperator(row?: JobRow | null, quiet?: boolean) {
  const srcRows = await fetchPermittedShiftSourceRows();
  let { options, nameById } = buildShiftOptionsFromQueryRows(srcRows);
  const merged = mergeRowExistingShiftsIntoOptions(row ?? null, options, nameById);
  shiftOptions.value = merged.options as ShiftOpt[];
  shiftNameById.value = merged.nameById;

  if (!quiet && srcRows.length === 0 && merged.options.length <= 1) {
    if (!resolveOperatorEmpId()) {
      message.warning('当前账号未绑定工号，无法加载人员班次权限');
    } else if (!operatorMayUseAllShifts()) {
      message.warning('未查询到您的班次权限，请在「人员班次权限」中配置');
    } else {
      message.warning('未能加载班次主数据，请检查视图白名单或数据权限');
    }
  }
}

/** 产生排班：班次下拉同样限定为当前登录人权限（管理员为全量主数据） */
async function loadGenerateShiftOptions() {
  const srcRows = await fetchPermittedShiftSourceRows();
  const { options } = buildShiftOptionsFromQueryRows(srcRows);
  generateShiftOptions.value = options;
  if (options.length <= 1) {
    message.warning(
      !resolveOperatorEmpId()
        ? '当前账号未绑定工号，无法匹配人员班次权限'
        : operatorMayUseAllShifts()
          ? '未能加载班次主数据，请检查视图白名单或数据权限'
          : '未查询到您的班次权限，无法产生排班',
    );
  }
}

function setDraftFromRow(row: JobRow) {
  clearDraft();
  // 先用 row 原始值初始化草稿
  for (let d = 1; d <= 31; d++) {
    const id = String(row?.[`Day${d}_ID`] ?? '').trim();
    draftDayIds[d] = id ? id : ZERO_UUID;
  }
}

function openEdit(row: JobRow) {
  editRow.value = row;
  setDraftFromRow(row);
  uniformShiftId.value = '';
  void (async () => {
    try {
      await loadShiftOptionsForCurrentOperator(row, false);
    } catch (e: any) {
      message.error(e?.message || '加载班次选项失败');
      return;
    }
    editOpen.value = true;
  })();
}

function applyUniformToDays() {
  const id = uniformShiftId.value || ZERO_UUID;
  const days = editDaysInMonth.value;
  for (let d = 1; d <= days; d++) {
    draftDayIds[d] = id;
  }
}

function buildUpdatePayload(): Record<string, any> {
  const row = editRow.value;
  if (!row) return {};
  const payload: Record<string, any> = {
    FID: row.FID,
    EMP_ID: row.EMP_ID,
    JS_Month: row.JS_Month,
    modifier: operatorName(),
  };
  const days = editDaysInMonth.value;
  for (let d = 1; d <= 31; d++) {
    const id =
      d <= days
        ? (draftDayIds[d] ?? ZERO_UUID)
        : ZERO_UUID; // 月份以外置空
    payload[`Day${d}_ID`] = id;
    payload[`Day${d}_Name`] = shiftNameById.value.get(id) ?? '';
  }
  return payload;
}

async function saveEdit() {
  const row = editRow.value;
  if (!row) return;
  editSaving.value = true;
  try {
    const updateData = buildUpdatePayload();
    if (!updateData.FID) {
      message.warning('缺少要保存的行主键 FID');
      return;
    }
    await saveDatasaveMulti([
      {
        tableName: 'att_lst_JobScheduling',
        primaryKey: 'FID',
        data: [updateData],
        deleteRows: [],
      },
    ]);
    message.success('保存成功');
    editOpen.value = false;
    editRow.value = null;
    await loadRows(1);
  } catch (e: any) {
    message.error(e?.message || '保存失败');
  } finally {
    editSaving.value = false;
  }
}

onMounted(() => {
  void loadRows(1);

  onMouseUpHandler = () => {
    isSelectingCells.value = false;
  };

  onDocClickHandler = () => {
    closeContextMenu();
  };

  if (onMouseUpHandler) window.addEventListener('mouseup', onMouseUpHandler);
  if (onDocClickHandler) window.addEventListener('click', onDocClickHandler);
});

onBeforeUnmount(() => {
  if (onMouseUpHandler) window.removeEventListener('mouseup', onMouseUpHandler);
  if (onDocClickHandler) window.removeEventListener('click', onDocClickHandler);
  stopDragSelection();
});

// -------------------- Excel 导入（老系统 Import_TMP + CheckFunction + Procedure） --------------------

const importOpen = ref(false);
const importFileList = ref<UploadProps['fileList']>([]);
const importErrors = ref<JobImportPreviewError[]>([]);
const importCanCommit = ref(false);
const importPreviewing = ref(false);
const importCommitting = ref(false);
const importRowCount = ref(0);
/** 模板示意图加载失败时显示占位说明（可将老系统 JobScheduling.png 放到 public/.../template-preview.png） */
const importTemplatePreviewOk = ref(true);

const importPublicBase = computed(() => {
  const b = import.meta.env.BASE_URL || '/';
  return b.endsWith('/') ? b : `${b}/`;
});
const jobSchedulingTemplateDownloadUrl = computed(
  () => `${importPublicBase.value}attendance/job-scheduling/JobScheduling.xls`,
);
const jobSchedulingTemplatePreviewUrl = computed(
  () => `${importPublicBase.value}attendance/job-scheduling/template-preview.png`,
);

const importSelectedFileName = computed(() => {
  const raw = importFileList.value?.[0];
  if (!raw) return '';
  return String((raw as any).name ?? '').trim();
});

watch(importOpen, (open) => {
  if (open) importTemplatePreviewOk.value = true;
});

const importErrorColumns = [
  { title: '项目', dataIndex: 'itemName', key: 'itemName', ellipsis: true, width: 120 },
  { title: '明细', dataIndex: 'itemDetail', key: 'itemDetail', ellipsis: true, width: 160 },
  { title: '原因', dataIndex: 'reason', key: 'reason', ellipsis: true },
];

function openImportModal() {
  importFileList.value = [];
  importErrors.value = [];
  importCanCommit.value = false;
  importRowCount.value = 0;
  importOpen.value = true;
}

const importBeforeUpload: UploadProps['beforeUpload'] = () => false;

async function runImportPreview() {
  const raw = importFileList.value?.[0];
  const f = (raw && 'originFileObj' in raw ? raw.originFileObj : undefined) as File | undefined;
  if (!f) {
    message.warning('请选择 Excel 文件（.xls / .xlsx）');
    return;
  }
  const opEmp = resolveOperatorEmpId();
  if (!opEmp) {
    message.warning('当前账号未绑定工号，无法校验班次权限，请先在用户信息中维护工号');
    return;
  }
  importPreviewing.value = true;
  importErrors.value = [];
  importCanCommit.value = false;
  try {
    const data = await previewJobSchedulingImport(f, operatorName(), opEmp);
    importRowCount.value = data.rowCount;
    importCanCommit.value = data.canCommit;
    importErrors.value = data.errors ?? [];
    if (data.canCommit) {
      message.success(`校验通过，共 ${data.rowCount} 行，请点击「确认导入」写入正式表`);
    } else if (importErrors.value.length) {
      message.warning(`校验未通过，共 ${importErrors.value.length} 条问题`);
    } else {
      message.warning('未写入临时表或校验失败，请检查文件内容');
    }
  } catch (e: any) {
    message.error(e?.message || '预览校验失败');
  } finally {
    importPreviewing.value = false;
  }
}

async function runImportCommit() {
  if (!importCanCommit.value) {
    message.warning('请先完成预览且校验通过');
    return;
  }
  importCommitting.value = true;
  try {
    await commitJobSchedulingImport(operatorName());
    message.success('导入成功');
    importOpen.value = false;
    await loadRows(page.value);
  } catch (e: any) {
    message.error(e?.message || '确认导入失败');
  } finally {
    importCommitting.value = false;
  }
}
</script>

<template>
  <div class="job-scheduling-work">
    <div class="toolbar-card">
      <div class="query-toolbar">
        <div class="query-inputs">
          <Input
            class="query-input-grow"
            v-model:value="jsMonthInput"
            placeholder="月份 YYYYMM"
            allowClear
          />
          <Input
            class="query-input-grow"
            v-model:value="empNameKeyword"
            placeholder="姓名"
            allowClear
          />
          <Input
            class="query-input-grow"
            v-model:value="deptKeyword"
            placeholder="部门/班组"
            allowClear
          />
        </div>
        <div class="query-actions">
          <Button class="query-btn" @click="openImportModal">导入</Button>
          <Button class="query-btn" @click="openGenerateModal">产生排班</Button>
          <Button class="query-btn" type="primary" :loading="loading" @click="loadRows(1)">
            查询
          </Button>
          <Button class="query-btn" :loading="loading" @click="loadRows(page)">
            刷新
          </Button>
        </div>
      </div>
    </div>

    <div class="table-card">
      <Table
        :columns="columns"
        :data-source="rows"
        :row-key="'FID'"
        :loading="loading"
        :custom-row="(record: JobRow) => ({ onDblclick: () => openEdit(record) })"
        :pagination="{
          current: page,
          pageSize: pageSize,
          total: total,
          showSizeChanger: false,
          onChange: (p: number) => loadRows(p),
        }"
        :scroll="{ x: 4600, y: 620 }"
      />
    </div>

    <div
      v-if="contextMenuVisible"
      class="shift-context-menu"
      :style="{
        left: `${contextMenuX}px`,
        top: `${contextMenuY}px`,
        pointerEvents: contextMenuSaving ? 'none' : 'auto',
      }"
      @click.stop
    >
      <div class="shift-context-menu-title">选择班次</div>
      <div v-if="contextMenuSaving" class="shift-context-menu-loading">保存中...</div>
      <template v-else>
        <div
          v-for="opt in shiftOptions"
          :key="opt.value"
          class="shift-context-menu-item"
          @click="applyShiftToSelectedCells(opt.value)"
        >
          {{ opt.label || '空' }}
        </div>
      </template>
    </div>

    <Modal
      :open="importOpen"
      title="导入排班"
      width="960px"
      :footer="null"
      destroy-on-close
      @cancel="importOpen = false"
    >
      <div class="import-modal-body">
        <p class="import-hint">
          与老系统一致：表内需含 <b>工号</b>；<b>月份</b>（YYYYMM）或带日期的列头（如 2026-04-01，将自动对应到当月「几号」列）；每日班次填
          <b>D1～D31</b> 或日期列，值为班次名称（与 <code>att_lst_BC_set_code.code_name</code> 一致）。空单元格视为休息。
        </p>
        <div class="import-file-row">
          <span class="import-file-label">请选择Excel：</span>
          <Input
            class="import-file-input"
            readonly
            :value="importSelectedFileName"
            placeholder="未选择文件"
          />
          <Upload
            v-model:file-list="importFileList"
            :max-count="1"
            accept=".xlsx,.xls"
            :before-upload="importBeforeUpload"
            :show-upload-list="false"
          >
            <Button type="primary">选择文件</Button>
          </Upload>
          <a
            class="import-template-download"
            :href="jobSchedulingTemplateDownloadUrl"
            download="JobScheduling.xls"
          >
            点击下载模板
          </a>
        </div>
        <div class="import-template-preview-wrap">
          <img
            v-show="importTemplatePreviewOk"
            class="import-template-preview-img"
            :src="jobSchedulingTemplatePreviewUrl"
            alt="排班导入模板示意图"
            @error="importTemplatePreviewOk = false"
          />
          <div v-show="!importTemplatePreviewOk" class="import-preview-fallback">
            未找到示意图（可选）：将说明图片命名为
            <code>template-preview.png</code>
            放到
            <code>public/attendance/job-scheduling/</code>
            即可在此显示；填写方式见上方说明或已下载的 Excel 模板。
          </div>
        </div>
        <Space style="margin-top: 14px">
          <Button type="primary" :loading="importPreviewing" @click="runImportPreview">
            预览校验
          </Button>
          <Button
            type="primary"
            ghost
            :disabled="!importCanCommit"
            :loading="importCommitting"
            @click="runImportCommit"
          >
            确认导入
          </Button>
        </Space>
        <div v-if="importRowCount > 0 && importCanCommit" class="import-summary">
          已通过校验：<b>{{ importRowCount }}</b> 行（临时表已就绪，确认后写入 <code>att_lst_JobScheduling</code>）
        </div>
        <div v-if="importErrors.length" class="import-errors-wrap">
          <div class="import-errors-title">校验问题（{{ importErrors.length }}）</div>
          <Table
            size="small"
            :columns="importErrorColumns"
            :data-source="importErrors.map((e, i) => ({ key: i, ...e }))"
            :pagination="{ pageSize: 8 }"
            :scroll="{ y: 280 }"
          />
        </div>
      </div>
    </Modal>

    <Modal
      :open="editOpen"
      title="编辑排班（按员工）"
      width="1180px"
      :confirm-loading="editSaving"
      :footer="null"
      @cancel="editOpen = false"
    >
      <template v-if="editRow">
        <div style="display:flex; gap: 16px; flex-wrap: wrap; margin-bottom: 12px;">
          <div><b>员工：</b>{{ String(editRow.name ?? '').trim() || '--' }}</div>
          <div><b>工号：</b>{{ String(editRow.EMP_ID ?? '').trim() || '--' }}</div>
          <div><b>月份：</b>{{ String(editRow.JS_Month ?? '').trim() }}</div>
          <div><b>在月天数：</b>{{ editDaysInMonth }}</div>
        </div>

        <div style="display:flex; gap: 12px; align-items:center; flex-wrap: wrap; margin-bottom: 12px;">
          <Select
            v-model:value="uniformShiftId"
            style="width: 360px;"
            placeholder="选择一个班次，一键填充到本月所有天"
            :options="shiftOptions"
            allowClear
          />
          <Button @click="applyUniformToDays" :disabled="!uniformShiftId">
            应用到全月
          </Button>
        </div>

        <div class="js-grid">
          <div
            v-for="d in 31"
            :key="d"
            class="js-day"
            :style="{ opacity: d <= editDaysInMonth ? 1 : 0.45 }"
          >
            <div class="js-day-label">{{ d }}号</div>
            <Select
              :value="draftDayIds[d]"
              :options="shiftOptions"
              style="width: 100%;"
              :disabled="d > editDaysInMonth"
              @change="(v: string) => (draftDayIds[d] = v || ZERO_UUID)"
            />
          </div>
        </div>

        <div style="display:flex; justify-content:flex-end; gap: 12px; margin-top: 16px;">
          <Button @click="editOpen = false" :disabled="editSaving">取消</Button>
          <Button type="primary" :loading="editSaving" @click="saveEdit" :disabled="editSaving">
            保存
          </Button>
        </div>
      </template>
    </Modal>

    <Modal
      :open="generateOpen"
      title="产生排班"
      width="980px"
      :confirm-loading="generateLoading"
      @ok="submitGenerate"
      @cancel="generateOpen = false"
    >
      <Space wrap size="12" style="margin-bottom: 12px;">
        <span>排班时间</span>
        <DatePicker
          :value="scheduleStartDate ? dayjs(scheduleStartDate) : null"
          @change="(_, s) => (scheduleStartDate = String(s || ''))"
        />
        <span>-</span>
        <DatePicker
          :value="scheduleEndDate ? dayjs(scheduleEndDate) : null"
          @change="(_, s) => (scheduleEndDate = String(s || ''))"
        />
        <Checkbox v-model:checked="keepWeek6">排除周六</Checkbox>
        <Checkbox v-model:checked="keepWeek7">排除周日</Checkbox>
        <Checkbox v-model:checked="keepHoliday">排除法定节假日</Checkbox>
        <span>班次</span>
        <Select
          v-model:value="generateShiftId"
          style="width: 220px;"
          placeholder="请选择班次"
          :options="generateShiftOptions"
          show-search
          :filter-option="(input, option) => String(option?.label ?? '').toLowerCase().includes(input.toLowerCase())"
        />
      </Space>

      <Space size="10" style="margin-bottom: 10px;">
        <Button type="primary" ghost @click="pickerOpen = true">增加人员</Button>
        <Button danger ghost @click="removePeople">删除</Button>
      </Space>

      <Table
        size="small"
        :data-source="selectedPeople"
        :pagination="false"
        row-key="id"
        :columns="[
          { title: '工号', dataIndex: 'empId', key: 'empId', width: 120 },
          { title: '姓名', dataIndex: 'name', key: 'name', width: 120 },
          { title: '部门', dataIndex: 'deptName', key: 'deptName', width: 220, ellipsis: true },
          { title: '岗位', dataIndex: 'dutyName', key: 'dutyName', width: 140, ellipsis: true },
        ]"
        :scroll="{ y: 260 }"
      />
    </Modal>

    <SelectPersonnelModal
      v-model:open="pickerOpen"
      title="选择人员"
      :default-selected="selectedPeople"
      @confirm="onPickedPeople"
    />
  </div>
</template>

<style scoped>
.job-scheduling-work {
  padding: 0 4px 24px;
}

.job-scheduling-work :deep(.ant-table-cell) {
  white-space: nowrap;
}

.table-card :deep(.ant-table-tbody > tr > td) {
  height: 45px;
  min-height: 45px;
  padding-top: 0 !important;
  padding-bottom: 0 !important;
}

.table-card :deep(.ant-table-thead > tr > th) {
  height: 45px;
  min-height: 45px;
  padding-top: 0 !important;
  padding-bottom: 0 !important;
  background: #fafafa;
  text-align: center;
}

.table-card :deep(.ant-table-thead .ant-table-cell) {
  text-align: center;
}

.toolbar-card {
  margin: 12px 0;
  background: #ffffff;
  border: 1px solid rgba(0, 0, 0, 0.06);
  border-radius: 12px;
  padding: 12px 16px;
}

.query-toolbar {
  display: flex;
  align-items: stretch;
  width: 100%;
  gap: 16px;
  flex-wrap: nowrap;
}

.query-inputs {
  display: flex;
  flex: 1 1 0;
  min-width: 0;
  gap: 12px;
}

.query-input-grow {
  flex: 1 1 0;
  min-width: 0;
}

.query-actions {
  display: flex;
  flex: 0 0 auto;
  align-items: center;
  gap: 10px;
}

.query-btn {
  min-width: 72px;
}

@media (max-width: 900px) {
  .query-toolbar {
    flex-wrap: wrap;
  }

  .query-inputs {
    flex: 1 1 100%;
  }
}

.toolbar-hint {
  margin-top: 10px;
  padding: 10px 12px;
  background: rgba(24, 144, 255, 0.06);
  border: 1px solid rgba(24, 144, 255, 0.18);
  border-radius: 10px;
  color: rgba(0, 0, 0, 0.62);
  font-size: 12px;
  line-height: 1.5;
}

.table-card {
  background: #ffffff;
  border: 1px solid rgba(0, 0, 0, 0.06);
  border-radius: 12px;
  overflow: hidden;
}

/* 日期列列头：双行 + 浅渐变（对齐老系统排班表） */
.table-card :deep(.ant-table-thead > tr > th.job-sched-th-day) {
  vertical-align: middle;
  padding: 8px 6px !important;
  background: linear-gradient(180deg, #ebebeb 0%, #f7f7f7 55%, #fafafa 100%);
  text-align: center;
}

.table-card :deep(.job-sched-day-th) {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 2px;
  line-height: 1.2;
  min-height: 36px;
}

.table-card :deep(.job-sched-day-th-date) {
  font-size: 12px;
  font-weight: 600;
  color: rgba(0, 0, 0, 0.88);
  white-space: nowrap;
}

.table-card :deep(.job-sched-day-th-week) {
  font-size: 12px;
  color: rgba(0, 0, 0, 0.55);
  white-space: nowrap;
}

.table-card :deep(.job-sched-day-th--invalid .job-sched-day-th-date) {
  color: rgba(0, 0, 0, 0.22);
  font-weight: 500;
}

/* 左侧信息列仍可整行浅灰 hover；日期列单独处理，避免与「矩形选中」混淆成整行选中 */
.table-card :deep(.ant-table-tbody > tr:hover > td:not(.job-sched-day-cell)) {
  background: rgba(0, 0, 0, 0.02);
}

/* vc-table 会给行内所有单元格加 ant-table-cell-row-hover，日期列压成几乎无底色 */
.table-card :deep(.ant-table-tbody > td.job-sched-day-cell.ant-table-cell-row-hover) {
  background: rgba(0, 0, 0, 0.02) !important;
}

.table-card :deep(.ant-table-tbody > td.job-sched-day-cell) {
  padding: 0 !important;
  vertical-align: middle;
}

.table-card :deep(.ant-table-tbody > td.job-sched-day-cell.day-cell-selected) {
  background: rgba(255, 77, 79, 0.35) !important;
  box-shadow: inset 0 0 0 1px rgba(207, 19, 34, 0.45) !important;
}

.shift-pill {
  display: inline-flex;
  align-items: center;
  max-width: 100%;
  padding: 2px 10px;
  border-radius: 999px;
  background: rgba(24, 144, 255, 0.08);
  border: 1px solid rgba(24, 144, 255, 0.16);
  color: rgba(24, 144, 255, 1);
  font-size: 12px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.shift-pill-empty {
  background: rgba(0, 0, 0, 0.04);
  border-color: rgba(0, 0, 0, 0.08);
  color: rgba(0, 0, 0, 0.28);
}

.shift-pill-selected {
  background: rgba(255, 77, 79, 0.18);
  border-color: rgba(255, 77, 79, 0.45);
  color: #cf1322;
  font-weight: 700;
}

.day-cell-inner {
  width: 100%;
  min-height: 28px;
  height: 100%;
  display: flex;
  align-items: center;
  padding: 0 6px;
  box-sizing: border-box;
  user-select: none;
  cursor: pointer;
}

.shift-context-menu {
  position: fixed;
  z-index: 2500;
  min-width: 220px;
  max-width: 260px;
  background: #ffffff;
  border: 1px solid rgba(0, 0, 0, 0.08);
  border-radius: 12px;
  box-shadow: 0 12px 40px rgba(0, 0, 0, 0.18);
  padding: 8px;
}

.shift-context-menu-title {
  padding: 6px 10px 8px;
  color: rgba(0, 0, 0, 0.65);
  font-weight: 600;
  font-size: 12px;
}

.shift-context-menu-item {
  padding: 10px 10px;
  border-radius: 10px;
  cursor: pointer;
  font-size: 13px;
  color: rgba(0, 0, 0, 0.85);
}

.shift-context-menu-item:hover {
  background: rgba(24, 144, 255, 0.08);
  color: rgba(24, 144, 255, 1);
}

.shift-context-menu-loading {
  padding: 12px 10px;
  font-size: 13px;
  color: rgba(0, 0, 0, 0.6);
}

.js-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 12px 14px;
  max-height: 520px;
  overflow: auto;
  padding-right: 6px;
}

.js-day {
  border: 1px solid rgba(0, 0, 0, 0.06);
  border-radius: 8px;
  padding: 10px 10px 8px;
  background: rgba(0, 0, 0, 0.01);
}

.js-day-label {
  font-size: 12px;
  font-weight: 600;
  color: rgba(0, 0, 0, 0.65);
  margin-bottom: 6px;
}

.import-modal-body {
  padding: 4px 0 8px;
}

.import-file-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px 12px;
  margin-bottom: 12px;
}

.import-file-label {
  flex: 0 0 auto;
  font-size: 14px;
  color: rgba(0, 0, 0, 0.85);
}

.import-file-input {
  flex: 1 1 200px;
  min-width: 160px;
}

.import-template-download {
  flex: 0 0 auto;
  font-size: 14px;
}

.import-template-preview-wrap {
  min-height: 220px;
  max-height: 360px;
  margin-bottom: 12px;
  border: 1px solid rgba(0, 0, 0, 0.12);
  border-radius: 8px;
  background: rgba(0, 0, 0, 0.02);
  overflow: auto;
  display: flex;
  align-items: center;
  justify-content: center;
}

.import-template-preview-img {
  display: block;
  max-width: 100%;
  height: auto;
  vertical-align: top;
}

.import-preview-fallback {
  padding: 20px 16px;
  font-size: 13px;
  line-height: 1.6;
  color: rgba(0, 0, 0, 0.55);
  text-align: center;
}

.import-hint {
  margin: 0 0 14px;
  font-size: 13px;
  line-height: 1.55;
  color: rgba(0, 0, 0, 0.65);
}

.import-summary {
  margin-top: 14px;
  font-size: 13px;
  color: rgba(24, 144, 255, 0.95);
}

.import-errors-wrap {
  margin-top: 16px;
}

.import-errors-title {
  font-size: 13px;
  font-weight: 600;
  margin-bottom: 8px;
  color: rgba(0, 0, 0, 0.75);
}
</style>

