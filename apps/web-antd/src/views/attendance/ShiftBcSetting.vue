<script setup lang="ts">
/**
 * 班次设定（硬编码页）
 * 对齐老系统：ExtendPage/att/tree_AttlstBCsetcode_detail.aspx
 * - 左树：v_t_att_lst_BC_set_code
 * - 右：班次时段 att_lst_time_interval（sec_num 1~4）保存；设定用户 + att_set_BCusers
 */
import { computed, h, ref, watch } from 'vue';
import {
  Button,
  Card,
  Checkbox,
  Descriptions,
  DescriptionsItem,
  Empty,
  Input,
  message,
  Modal,
  Select,
  Space,
  Spin,
  Table,
  Tabs,
  TimePicker,
  Tree,
} from 'ant-design-vue';
import type { DataNode } from 'ant-design-vue/es/tree';
import type { Key } from 'ant-design-vue/es/_util/type';
import dayjs, { type Dayjs } from 'dayjs';
import { Page } from '@vben/common-ui';
import { useUserStore } from '@vben/stores';

import {
  batchDelete,
  executeProcedure,
  queryForVben,
  queryForVbenPaged,
  saveDatasaveMulti,
  whereAnd,
} from './shiftBcSettingApi';

const userStore = useUserStore();

function operatorName(): string {
  const u: any = userStore.userInfo ?? {};
  return String(u.realName ?? u.name ?? u.username ?? u.userName ?? '').trim() || 'system';
}

const TAG_OPTIONS = [
  { label: '前一天', value: -1 },
  { label: '当天', value: 0 },
  { label: '次日', value: 1 },
];

type SegmentModel = {
  FID: string;
  valid_begin_time_tag: number;
  valid_begin_time: Dayjs | undefined;
  begin_time_tag: number;
  begin_time: Dayjs | undefined;
  begin_time_slot_card: boolean;
  end_time_tag: number;
  end_time: Dayjs | undefined;
  end_time_slot_card: boolean;
  valid_end_time_tag: number;
  valid_end_time: Dayjs | undefined;
  centre_time_tag: number;
  centre_time: Dayjs | undefined;
  half_time: string;
  time_length: string;
  remark: string;
  /** 展示用（老系统表格末列） */
  op: string;
  modifyTime: string;
};

function emptySegment(): SegmentModel {
  const noon = dayjs('1900-01-01 12:00:00');
  return {
    FID: '',
    valid_begin_time_tag: 0,
    valid_begin_time: undefined,
    begin_time_tag: 0,
    begin_time: undefined,
    begin_time_slot_card: true,
    end_time_tag: 0,
    end_time: undefined,
    end_time_slot_card: true,
    valid_end_time_tag: 0,
    valid_end_time: undefined,
    centre_time_tag: 0,
    centre_time: noon,
    half_time: '',
    time_length: '',
    remark: '',
    op: '',
    modifyTime: '',
  };
}

function pick(row: any, ...keys: string[]) {
  if (!row) return undefined;
  for (const k of keys) {
    if (row[k] !== undefined && row[k] !== null) return row[k];
  }
  return undefined;
}

function parseTime(v: any): Dayjs | undefined {
  if (v === null || v === undefined || v === '') return undefined;
  const d = dayjs(v);
  return d.isValid() ? d : undefined;
}

function toBitBool(v: any): boolean {
  if (v === true || v === 1) return true;
  if (v === false || v === 0) return false;
  const s = String(v).toLowerCase();
  return s === 'true' || s === '1';
}

function rowToSegment(row: any): SegmentModel {
  return {
    FID: String(pick(row, 'FID', 'fid') ?? ''),
    valid_begin_time_tag: Number(pick(row, 'valid_begin_time_tag') ?? 0),
    valid_begin_time: parseTime(pick(row, 'valid_begin_time')),
    begin_time_tag: Number(pick(row, 'begin_time_tag') ?? 0),
    begin_time: parseTime(pick(row, 'begin_time')),
    begin_time_slot_card: toBitBool(pick(row, 'begin_time_slot_card')),
    end_time_tag: Number(pick(row, 'end_time_tag') ?? 0),
    end_time: parseTime(pick(row, 'end_time')),
    end_time_slot_card: toBitBool(pick(row, 'end_time_slot_card')),
    valid_end_time_tag: Number(pick(row, 'valid_end_time_tag') ?? 0),
    valid_end_time: parseTime(pick(row, 'valid_end_time')),
    centre_time_tag: Number(pick(row, 'centre_time_tag') ?? 0),
    centre_time: parseTime(pick(row, 'centre_time')) ?? dayjs('1900-01-01 12:00:00'),
    half_time: pick(row, 'half_time') == null ? '' : String(pick(row, 'half_time')),
    time_length: pick(row, 'time_length') == null ? '' : String(pick(row, 'time_length')),
    remark: pick(row, 'remark') == null ? '' : String(pick(row, 'remark')),
    op: pick(row, 'op', 'Op') == null ? '' : String(pick(row, 'op', 'Op')),
    modifyTime:
      pick(row, 'modifyTime', 'ModifyTime', 'modify_time') == null
        ? ''
        : String(pick(row, 'modifyTime', 'ModifyTime', 'modify_time')),
  };
}

function timeToDb(d: Dayjs | null | undefined): string | null {
  if (!d || !d.isValid()) return null;
  const h = d.hour();
  const m = d.minute();
  const s = d.second();
  return `1900-01-01 ${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

type FlatBc = { id: string; parent_id: string | null; name: string };

function listToTreeData(nodes: FlatBc[]): DataNode[] {
  const map = new Map<string, DataNode & { rawParent?: string | null }>();
  for (const n of nodes) {
    map.set(n.id, {
      key: n.id,
      title: n.name,
      children: [],
      rawParent: n.parent_id,
    });
  }
  const roots: DataNode[] = [];
  for (const n of nodes) {
    const node = map.get(n.id)!;
    const pid = n.parent_id;
    if (pid && map.has(pid)) {
      (map.get(pid)!.children as DataNode[]).push(node);
    } else {
      roots.push(node);
    }
  }
  return roots;
}

function filterFlat(nodes: FlatBc[], kw: string): FlatBc[] {
  const k = kw.trim().toLowerCase();
  if (!k) return nodes;
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const keep = new Set<string>();
  for (const n of nodes) {
    if (String(n.name ?? '').toLowerCase().includes(k)) {
      let cur: FlatBc | undefined = n;
      while (cur) {
        keep.add(cur.id);
        const parentId: string | null = cur.parent_id;
        cur = parentId ? byId.get(parentId) : undefined;
      }
    }
  }
  return nodes.filter((n) => keep.has(n.id));
}

const flatBcList = ref<FlatBc[]>([]);
const treeFilter = ref('');
const treeLoading = ref(false);
const selectedBcId = ref<string | null>(null);
const selectedKeys = ref<Key[]>([]);

const treeData = computed(() => listToTreeData(filterFlat(flatBcList.value, treeFilter.value)));

const detailLoading = ref(false);
const bcHeader = ref<Record<string, any>>({});
const segments = ref<SegmentModel[]>([
  emptySegment(),
  emptySegment(),
  emptySegment(),
  emptySegment(),
]);

const saving = ref(false);
const activeTab = ref('shift');

const userRows = ref<any[]>([]);
const userLoading = ref(false);
const userSelectedKeys = ref<Key[]>([]);

const userPickOpen = ref(false);
const userPickLoading = ref(false);
const userPickRows = ref<any[]>([]);
const userPickSelected = ref<Key[]>([]);
const USER_PICK_PAGE_SIZE = 500;
const userPickPage = ref(1);
const userPickTotal = ref(0);
/** 搜索框输入；点「查询」后写入 userPickKeyword 再请求 */
const userPickSearchDraft = ref('');
const userPickKeyword = ref('');
/** 勾选时：再次「查询」不清空已选用户（与老系统「并集」一致） */
const userPickUnion = ref(false);

/** 与老系统「新增/修改」弹窗一致：主表 att_lst_BC_set_code */
const SK_ATTRIBUTE_OPTIONS = [
  { label: '两次刷卡', value: 0 },
  { label: '四次刷卡', value: 1 },
];

type BcMasterForm = {
  code_name: string;
  parent_id: string | undefined;
  late_allow_minutes: string;
  early_allow_minutes: string;
  absenteeism_start_minutes: string;
  overtime_start_minutes: string;
  total_hours: string;
  sk_attribute: number;
  other_attribute: string;
  share_bc: boolean;
};

const bcFormOpen = ref(false);
const bcFormMode = ref<'add' | 'edit'>('add');
const bcFormSaving = ref(false);
const bcFormFid = ref('');

const bcForm = ref<BcMasterForm>({
  code_name: '',
  parent_id: undefined,
  late_allow_minutes: '',
  early_allow_minutes: '',
  absenteeism_start_minutes: '',
  overtime_start_minutes: '',
  total_hours: '',
  sk_attribute: 0,
  other_attribute: '',
  share_bc: false,
});

const bcFormModifierLabel = computed(() => {
  if (bcFormMode.value === 'add') return operatorName();
  const u = pick(bcHeader.value, 'add_user', 'Add_user');
  return u != null && String(u).trim() !== '' ? String(u) : operatorName();
});

const parentSelectOptions = computed(() => {
  const self = bcFormMode.value === 'edit' ? bcFormFid.value : '';
  return flatBcList.value
    .filter((n) => !self || n.id !== self)
    .map((n) => ({ label: n.name, value: n.id }));
});

function parseIntField(s: string): number | null {
  const t = s.trim();
  if (!t) return null;
  const n = Number.parseInt(t, 10);
  return Number.isFinite(n) ? n : null;
}

function parseDecimalField(s: string): number | null {
  const t = s.trim();
  if (!t) return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}

function resetBcFormForAdd() {
  bcForm.value = {
    code_name: '',
    parent_id: selectedBcId.value ?? undefined,
    late_allow_minutes: '',
    early_allow_minutes: '',
    absenteeism_start_minutes: '',
    overtime_start_minutes: '',
    total_hours: '',
    sk_attribute: 0,
    other_attribute: '',
    share_bc: false,
  };
}

function fillBcFormFromHeader(h: Record<string, any>) {
  bcForm.value = {
    code_name: String(pick(h, 'code_name', 'Code_name') ?? '').trim(),
    parent_id:
      pick(h, 'parent_id', 'Parent_id') == null || pick(h, 'parent_id', 'Parent_id') === ''
        ? undefined
        : String(pick(h, 'parent_id', 'Parent_id')),
    late_allow_minutes:
      pick(h, 'late_allow_minutes', 'Late_allow_minutes') == null
        ? ''
        : String(pick(h, 'late_allow_minutes', 'Late_allow_minutes')),
    early_allow_minutes:
      pick(h, 'early_allow_minutes', 'Early_allow_minutes') == null
        ? ''
        : String(pick(h, 'early_allow_minutes', 'Early_allow_minutes')),
    absenteeism_start_minutes:
      pick(h, 'absenteeism_start_minutes', 'Absenteeism_start_minutes') == null
        ? ''
        : String(pick(h, 'absenteeism_start_minutes', 'Absenteeism_start_minutes')),
    overtime_start_minutes:
      pick(h, 'overtime_start_minutes', 'Overtime_start_minutes') == null
        ? ''
        : String(pick(h, 'overtime_start_minutes', 'Overtime_start_minutes')),
    total_hours:
      pick(h, 'total_hours', 'Total_hours') == null ? '' : String(pick(h, 'total_hours', 'Total_hours')),
    sk_attribute: (() => {
      const sk = Number(pick(h, 'sk_attribute', 'Sk_attribute') ?? 0);
      return Number.isFinite(sk) ? sk : 0;
    })(),
    other_attribute: String(pick(h, 'other_attribute', 'Other_attribute') ?? '').slice(0, 10),
    share_bc: toBitBool(pick(h, 'share_bc', 'Share_bc')),
  };
}

function buildBcMasterRow(fid: string, mode: 'add' | 'edit'): Record<string, any> {
  const f = bcForm.value;
  const op = operatorName();
  const now = dayjs().format('YYYY-MM-DD HH:mm:ss');
  const row: Record<string, any> = {
    FID: fid,
    code_name: f.code_name.trim(),
    parent_id: f.parent_id ?? null,
    late_allow_minutes: parseIntField(f.late_allow_minutes),
    early_allow_minutes: parseIntField(f.early_allow_minutes),
    absenteeism_start_minutes: parseIntField(f.absenteeism_start_minutes),
    overtime_start_minutes: parseIntField(f.overtime_start_minutes),
    total_hours: parseDecimalField(f.total_hours),
    sk_attribute: f.sk_attribute,
    other_attribute: f.other_attribute.trim().slice(0, 10) || null,
    share_bc: f.share_bc ? 1 : 0,
  };
  if (mode === 'add') {
    row.add_time = now;
    row.add_user = op;
    return row;
  }
  row.add_time = pick(bcHeader.value, 'add_time', 'Add_time') ?? now;
  row.add_user = pick(bcHeader.value, 'add_user', 'Add_user') ?? op;
  row.remark1 = pick(bcHeader.value, 'remark1', 'Remark1') ?? null;
  row.remark2 = pick(bcHeader.value, 'remark2', 'Remark2') ?? null;
  row.remark3 = pick(bcHeader.value, 'remark3', 'Remark3') ?? null;
  row.import_sign = pick(bcHeader.value, 'import_sign', 'Import_sign') ?? null;
  return row;
}

function openBcAdd() {
  bcFormMode.value = 'add';
  bcFormFid.value = '';
  resetBcFormForAdd();
  bcFormOpen.value = true;
}

function openBcEdit() {
  if (!selectedBcId.value) {
    message.warning('请先在左侧选择班次');
    return;
  }
  bcFormMode.value = 'edit';
  bcFormFid.value = selectedBcId.value;
  fillBcFormFromHeader(bcHeader.value);
  bcFormOpen.value = true;
}

async function submitBcForm() {
  const f = bcForm.value;
  if (!f.code_name.trim()) {
    message.warning('请填写班次名称');
    return Promise.reject();
  }
  if (typeof f.sk_attribute !== 'number' || !Number.isFinite(f.sk_attribute)) {
    message.warning('请选择刷卡属性');
    return Promise.reject();
  }
  const fid = bcFormMode.value === 'add' ? crypto.randomUUID() : bcFormFid.value;
  if (!fid) {
    message.warning('缺少班次标识');
    return Promise.reject();
  }
  bcFormSaving.value = true;
  try {
    await saveDatasaveMulti([
      {
        tableName: 'att_lst_BC_set_code',
        primaryKey: 'FID',
        data: [buildBcMasterRow(fid, bcFormMode.value)],
        deleteRows: [],
      },
    ]);
    message.success(bcFormMode.value === 'add' ? '新增成功' : '保存成功');
    bcFormOpen.value = false;
    await loadTree();
    selectedKeys.value = [fid];
    selectedBcId.value = fid;
  } catch (e: any) {
    message.error(e?.message || '保存失败');
    return Promise.reject(e);
  } finally {
    bcFormSaving.value = false;
  }
}

function onToolbarSave() {
  void onSaveIntervals();
}

function onDeleteBc() {
  const id = selectedBcId.value;
  if (!id) {
    message.warning('请先在左侧选择班次');
    return;
  }
  Modal.confirm({
    title: '确认删除',
    content: '确定删除该班次？若存在子节点或关联数据可能导致删除失败。',
    async onOk() {
      await batchDelete([
        {
          tablename: 'att_lst_BC_set_code',
          key: 'FID',
          Keys: [String(id).toUpperCase()],
        },
      ]);
      message.success('已删除');
      selectedBcId.value = null;
      selectedKeys.value = [];
      bcHeader.value = {};
      segments.value = [emptySegment(), emptySegment(), emptySegment(), emptySegment()];
      userRows.value = [];
      await loadTree();
    },
  });
}

async function loadTree() {
  treeLoading.value = true;
  try {
    const items = await queryForVben({
      TableName: 'v_t_att_lst_BC_set_code',
      Page: 1,
      PageSize: 5000,
      SortBy: 'name',
      SortOrder: 'asc',
      SimpleWhere: {},
    });
    flatBcList.value = (items ?? []).map((r: any) => ({
      id: String(pick(r, 'id', 'ID') ?? ''),
      parent_id: pick(r, 'parent_id', 'parent_ID') == null ? null : String(pick(r, 'parent_id', 'parent_ID')),
      name: String(pick(r, 'name', 'NAME') ?? ''),
    }));
  } catch (e: any) {
    message.error(e?.message || '加载班次树失败');
  } finally {
    treeLoading.value = false;
  }
}

async function loadBcDetail(fid: string) {
  detailLoading.value = true;
  try {
    const rows = await queryForVben({
      TableName: 'att_lst_BC_set_code',
      Page: 1,
      PageSize: 1,
      SortBy: 'FID',
      SortOrder: 'asc',
      Where: whereAnd([{ Field: 'FID', Operator: 'eq', Value: fid }]),
    });
    bcHeader.value = rows[0] ?? {};

    for (let sec = 1; sec <= 4; sec++) {
      const ir = await queryForVben({
        TableName: 'att_lst_time_interval',
        Page: 1,
        PageSize: 1,
        SortBy: 'sec_num',
        SortOrder: 'asc',
        Where: whereAnd([
          { Field: 'pb_code_fid', Operator: 'eq', Value: fid },
          { Field: 'sec_num', Operator: 'eq', Value: sec },
        ]),
      });
      segments.value[sec - 1] = ir[0] ? rowToSegment(ir[0]) : emptySegment();
    }

    await loadUserGrid(fid);
  } catch (e: any) {
    message.error(e?.message || '加载班次明细失败');
  } finally {
    detailLoading.value = false;
  }
}

async function loadUserGrid(bcId: string) {
  userLoading.value = true;
  userSelectedKeys.value = [];
  try {
    userRows.value = await queryForVben({
      TableName: 'v_att_lst_ShiftsSetting',
      Page: 1,
      PageSize: 500,
      SortBy: 'username',
      SortOrder: 'asc',
      Where: whereAnd([{ Field: 'BCID', Operator: 'eq', Value: bcId }]),
    });
  } catch (e: any) {
    message.error(e?.message || '加载绑定用户失败');
    userRows.value = [];
  } finally {
    userLoading.value = false;
  }
}

watch(selectedBcId, (id) => {
  if (id) void loadBcDetail(id);
  else {
    bcHeader.value = {};
    segments.value = [emptySegment(), emptySegment(), emptySegment(), emptySegment()];
    userRows.value = [];
  }
});

function onTreeSelect(keys: Key[]) {
  selectedKeys.value = keys;
  const id = keys.length ? String(keys[0]) : null;
  selectedBcId.value = id;
}

function clearSegment(i: number) {
  segments.value[i] = emptySegment();
}

/** 老系统末列：修改人 / 时间 */
function segmentMetaText(seg: SegmentModel): string {
  const o = seg.op?.trim() ?? '';
  const raw = seg.modifyTime?.trim() ?? '';
  if (!o && !raw) return '';
  let timePart = raw;
  if (raw && dayjs(raw).isValid()) {
    timePart = dayjs(raw).format('YYYY-MM-DD HH:mm');
  }
  return [o, timePart].filter(Boolean).join(' ');
}

function buildIntervalRow(
  codeName: string,
  pbCodeFid: string,
  secNum: number,
  s: SegmentModel,
  op: string,
): Record<string, any> {
  const fid = s.FID?.trim() || crypto.randomUUID();
  const vb = s.valid_begin_time?.isValid() ? s.valid_begin_time : s.begin_time;
  const ve = s.valid_end_time?.isValid() ? s.valid_end_time : s.end_time;
  const half = s.half_time === '' ? null : Number(s.half_time);
  const tlen = s.time_length === '' ? null : Number(s.time_length);
  return {
    FID: fid,
    pb_code_fid: pbCodeFid,
    name: codeName,
    valid_begin_time_tag: s.valid_begin_time_tag,
    valid_begin_time: timeToDb(vb),
    begin_time_tag: s.begin_time_tag,
    begin_time: timeToDb(s.begin_time),
    begin_time_slot_card: s.begin_time_slot_card ? 1 : 0,
    end_time_tag: s.end_time_tag,
    end_time: timeToDb(s.end_time),
    end_time_slot_card: s.end_time_slot_card ? 1 : 0,
    valid_end_time_tag: s.valid_end_time_tag,
    valid_end_time: timeToDb(ve),
    centre_time_tag: s.centre_time_tag,
    centre_time: timeToDb(s.centre_time),
    half_time: Number.isFinite(half as number) ? half : null,
    time_length: Number.isFinite(tlen as number) ? tlen : null,
    remark: s.remark || null,
    sec_num: secNum,
    op,
    modifyTime: dayjs().format('YYYY-MM-DD HH:mm:ss'),
  };
}

async function onSaveIntervals() {
  const id = selectedBcId.value;
  if (!id) {
    message.warning('请先在左侧选择班次');
    return;
  }
  const codeName = String(pick(bcHeader.value, 'code_name', 'Code_name') ?? '');
  if (!codeName) {
    message.warning('班次名称缺失，无法保存时段');
    return;
  }
  const op = operatorName();
  const rows: Record<string, any>[] = [];
  for (let i = 0; i < 4; i++) {
    const secNum = i + 1;
    const s = segments.value[i]!;
    if (secNum === 1) {
      if (!s.begin_time?.isValid()) {
        message.warning('上班时段1 开始时间不能为空');
        return;
      }
    } else if (!s.begin_time?.isValid()) {
      continue;
    }
    rows.push(buildIntervalRow(codeName, id, secNum, s, op));
  }
  if (!rows.length) {
    message.warning('没有可保存的时段数据');
    return;
  }
  saving.value = true;
  try {
    await saveDatasaveMulti([
      {
        tableName: 'att_lst_time_interval',
        primaryKey: 'FID',
        data: rows,
        deleteRows: [],
      },
    ]);
    message.success('保存成功');
    await loadBcDetail(id);
  } catch (e: any) {
    message.error(e?.message || '保存失败');
  } finally {
    saving.value = false;
  }
}

async function onRemoveUser() {
  const id = selectedBcId.value;
  if (!id) {
    message.warning('请先选择班次');
    return;
  }
  if (!userSelectedKeys.value.length) {
    message.warning('请选中一条记录');
    return;
  }
  const row = userRows.value.find((r) => String(pick(r, 'FID', 'fid')) === String(userSelectedKeys.value[0]));
  const fid = pick(row, 'FID', 'fid');
  if (!fid) return;
  Modal.confirm({
    title: '确认删除',
    content: '确定移除该用户的班次绑定？',
    async onOk() {
      await batchDelete([
        {
          tablename: 'att_lst_ShiftsSetting',
          key: 'FID',
          Keys: [String(fid).toUpperCase()],
        },
      ]);
      message.success('已删除');
      await loadUserGrid(id);
    },
  });
}

function formatUserPickDate(v: any): string {
  if (v == null || v === '') return '';
  const d = dayjs(v);
  return d.isValid() ? d.format('YYYY-MM-DD') : '';
}

function userTypeLabel(v: any): string {
  const n = Number(v);
  if (n === 1) return '内部用户';
  if (Number.isFinite(n)) return `类型${n}`;
  return '—';
}

/** 是否停用：status 非 0 视为停用（与库内约定一致） */
function isUserRowDisabled(record: any): boolean {
  const s = pick(record, 'status', 'Status');
  return s != null && String(s) !== '0';
}

async function openUserPicker() {
  const id = selectedBcId.value;
  if (!id) {
    message.warning('请先选择班次');
    return;
  }
  userPickOpen.value = true;
  userPickUnion.value = false;
  userPickSearchDraft.value = '';
  userPickKeyword.value = '';
  userPickPage.value = 1;
  userPickSelected.value = [];
  await fetchUserPick();
}

function closeUserPickModal() {
  userPickOpen.value = false;
}

function onUserPickQuery() {
  userPickKeyword.value = userPickSearchDraft.value.trim();
  userPickPage.value = 1;
  if (!userPickUnion.value) userPickSelected.value = [];
  void fetchUserPick();
}

async function fetchUserPick() {
  userPickLoading.value = true;
  try {
    const body: Record<string, any> = {
      TableName: 't_sys_user',
      Page: userPickPage.value,
      PageSize: USER_PICK_PAGE_SIZE,
      SortBy: 'username',
      SortOrder: 'asc',
    };
    const kw = userPickKeyword.value.trim();
    if (kw) {
      body.Where = {
        Logic: 'OR',
        Conditions: [
          { Field: 'username', Operator: 'contains', Value: kw },
          { Field: 'name', Operator: 'contains', Value: kw },
        ],
        Groups: [],
      };
    }
    const { items, total } = await queryForVbenPaged(body);
    userPickRows.value = items;
    userPickTotal.value = total;
  } catch (e: any) {
    message.error(e?.message || '加载用户列表失败');
    userPickRows.value = [];
    userPickTotal.value = 0;
  } finally {
    userPickLoading.value = false;
  }
}

function onUserPickTableChange(pag: { current?: number }) {
  if (pag?.current == null || pag.current === userPickPage.value) return;
  userPickPage.value = pag.current;
  void fetchUserPick();
}

function onUserRowSelectChange(keys: Key[]) {
  userSelectedKeys.value = keys;
}

function onUserPickSelectChange(keys: Key[]) {
  userPickSelected.value = keys;
}

async function confirmUserPick() {
  const id = selectedBcId.value;
  if (!id) return;
  if (!userPickSelected.value.length) {
    message.warning('请选择用户');
    return;
  }
  const users = userPickSelected.value.map((k) => `@${String(k)}`).join('');
  try {
    await executeProcedure('dbo.att_set_BCusers', {
      BCID: id,
      users,
      openrationname: operatorName().slice(0, 50),
    });
    message.success('设置成功');
    closeUserPickModal();
    await loadUserGrid(id);
  } catch (e: any) {
    message.error(e?.message || '执行失败');
  }
}

const userColumns = [
  { title: '工号', dataIndex: 'username', key: 'username', width: 120 },
  { title: '姓名', dataIndex: 'name', key: 'name', width: 140 },
  { title: '操作人', dataIndex: 'OpenrationName', key: 'OpenrationName', width: 120 },
  {
    title: '操作时间',
    dataIndex: 'OpenrationTime',
    key: 'OpenrationTime',
    width: 180,
    customRender: ({ text }: any) => (text ? dayjs(text).format('YYYY-MM-DD HH:mm') : ''),
  },
];

const userPickColumns = [
  { title: '用户名', dataIndex: 'username', key: 'username', width: 120, ellipsis: true },
  { title: '所属员工', dataIndex: 'name', key: 'name', width: 120, ellipsis: true },
  {
    title: '生效日期',
    key: 'effect_date',
    width: 112,
    customRender: ({ record }: { record: any }) => formatUserPickDate(pick(record, 'effect_date', 'Effect_date')),
  },
  {
    title: '失效日期',
    key: 'expire_date',
    width: 112,
    customRender: ({ record }: { record: any }) => formatUserPickDate(pick(record, 'expire_date', 'Expire_date')),
  },
  {
    title: '用户类型',
    key: 'user_type',
    width: 100,
    ellipsis: true,
    customRender: ({ record }: { record: any }) => userTypeLabel(pick(record, 'user_type', 'User_type')),
  },
  {
    title: '是否停用',
    key: 'status',
    width: 88,
    align: 'center' as const,
    customRender: ({ record }: { record: any }) =>
      h(Checkbox, { checked: isUserRowDisabled(record), disabled: true }),
  },
];

const userPickPagination = computed(() => ({
  current: userPickPage.value,
  pageSize: USER_PICK_PAGE_SIZE,
  total: userPickTotal.value,
  showSizeChanger: false,
  showQuickJumper: true,
  showTotal: (t: number) => `每页 ${USER_PICK_PAGE_SIZE} 条，共 ${t} 条`,
}));

const parentName = computed(() => {
  const pid = pick(bcHeader.value, 'parent_id', 'Parent_id');
  if (!pid) return '';
  const p = flatBcList.value.find((x) => x.id === String(pid));
  return p?.name ?? String(pid);
});

void loadTree();
</script>

<template>
  <Page
    content-class="flex flex-col"
    description="硬编码页面：树 + 时段 + 绑定用户（对齐老系统 tree_AttlstBCsetcode_detail.aspx）"
    title="班次设定"
  >
    <div class="flex min-h-[calc(100vh-10rem)] gap-3">
      <Card class="w-[300px] shrink-0" size="small" title="班次结构">
        <Space direction="vertical" class="w-full" :size="8">
          <Space wrap class="w-full">
            <Button type="primary" @click="openBcAdd">新增</Button>
            <Button :disabled="!selectedBcId" @click="openBcEdit">修改</Button>
            <Button danger :disabled="!selectedBcId" @click="onDeleteBc">删除</Button>
            <Button :disabled="!selectedBcId" @click="onToolbarSave">保存</Button>
          </Space>
          <Input v-model:value="treeFilter" allow-clear placeholder="筛选名称" />
          <Spin :spinning="treeLoading">
            <div class="max-h-[calc(100vh-14rem)] overflow-auto">
              <Tree
                v-if="treeData.length"
                :tree-data="treeData"
                :selected-keys="selectedKeys"
                block-node
                show-line
                @select="onTreeSelect"
              />
              <Empty v-else description="暂无数据" />
            </div>
          </Spin>
        </Space>
      </Card>

      <Card class="min-w-0 flex-1" size="small">
        <template v-if="!selectedBcId">
          <Empty description="请在左侧选择班次" />
        </template>
        <Spin v-else :spinning="detailLoading">
          <Tabs v-model:active-key="activeTab">
            <Tabs.TabPane key="shift" tab="班次设定">
              <Space class="mb-3" wrap>
                <Button :loading="saving" type="primary" @click="onSaveIntervals">保存时段</Button>
                <Button @click="clearSegment(0)">清空时段1</Button>
                <Button @click="clearSegment(1)">清空时段2</Button>
                <Button @click="clearSegment(2)">清空时段3</Button>
                <Button @click="clearSegment(3)">清空时段4</Button>
              </Space>

              <Descriptions bordered class="mb-4" :column="2" size="small" title="班次信息（只读）">
                <DescriptionsItem label="班次名称">
                  {{ pick(bcHeader, 'code_name', 'Code_name') }}
                </DescriptionsItem>
                <DescriptionsItem label="父级">
                  {{ parentName || '—' }}
                </DescriptionsItem>
                <DescriptionsItem label="总小时">
                  {{ pick(bcHeader, 'total_hours', 'Total_hours') ?? '—' }}
                </DescriptionsItem>
                <DescriptionsItem label="刷卡属性">
                  {{ pick(bcHeader, 'sk_attribute', 'Sk_attribute') ?? '—' }}
                </DescriptionsItem>
                <DescriptionsItem label="迟到允许(分)">
                  {{ pick(bcHeader, 'late_allow_minutes', 'Late_allow_minutes') ?? '—' }}
                </DescriptionsItem>
                <DescriptionsItem label="早退允许(分)">
                  {{ pick(bcHeader, 'early_allow_minutes', 'Early_allow_minutes') ?? '—' }}
                </DescriptionsItem>
                <DescriptionsItem label="旷工起始(分)">
                  {{ pick(bcHeader, 'absenteeism_start_minutes', 'Absenteeism_start_minutes') ?? '—' }}
                </DescriptionsItem>
                <DescriptionsItem label="加班起始(分)">
                  {{ pick(bcHeader, 'overtime_start_minutes', 'Overtime_start_minutes') ?? '—' }}
                </DescriptionsItem>
                <DescriptionsItem label="共享班次">
                  {{ toBitBool(pick(bcHeader, 'share_bc', 'Share_bc')) ? '是' : '否' }}
                </DescriptionsItem>
                <DescriptionsItem label="其他属性">
                  {{ pick(bcHeader, 'other_attribute', 'Other_attribute') || '—' }}
                </DescriptionsItem>
              </Descriptions>

              <div class="shift-period-list overflow-x-auto">
                <fieldset v-for="idx in 4" :key="idx" class="shift-period-fieldset">
                  <legend class="shift-period-legend">上班时段{{ idx }}</legend>
                  <table class="shift-period-table" cellspacing="0" cellpadding="0">
                    <thead>
                      <tr>
                        <th>有效开始时间</th>
                        <th>开始时间</th>
                        <th class="shift-period-th-narrow">刷卡</th>
                        <th>结束时间</th>
                        <th class="shift-period-th-narrow">刷卡</th>
                        <th>有效结束时间</th>
                        <th>中间时间</th>
                        <th>休息时间</th>
                        <th>此段时长</th>
                        <th>备注</th>
                        <th>修改人/时间</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr>
                        <td>
                          <div class="shift-period-stack">
                            <Select
                              v-model:value="segments[idx - 1]!.valid_begin_time_tag"
                              class="shift-period-select"
                              :options="TAG_OPTIONS"
                            />
                            <TimePicker
                              v-model:value="segments[idx - 1]!.valid_begin_time"
                              class="shift-period-time"
                              format="HH:mm"
                            />
                          </div>
                        </td>
                        <td>
                          <div class="shift-period-stack">
                            <Select
                              v-model:value="segments[idx - 1]!.begin_time_tag"
                              class="shift-period-select"
                              :options="TAG_OPTIONS"
                            />
                            <TimePicker
                              v-model:value="segments[idx - 1]!.begin_time"
                              class="shift-period-time"
                              format="HH:mm"
                            />
                          </div>
                        </td>
                        <td class="shift-period-td-center">
                          <Checkbox v-model:checked="segments[idx - 1]!.begin_time_slot_card" />
                        </td>
                        <td>
                          <div class="shift-period-stack">
                            <Select
                              v-model:value="segments[idx - 1]!.end_time_tag"
                              class="shift-period-select"
                              :options="TAG_OPTIONS"
                            />
                            <TimePicker
                              v-model:value="segments[idx - 1]!.end_time"
                              class="shift-period-time"
                              format="HH:mm"
                            />
                          </div>
                        </td>
                        <td class="shift-period-td-center">
                          <Checkbox v-model:checked="segments[idx - 1]!.end_time_slot_card" />
                        </td>
                        <td>
                          <div class="shift-period-stack">
                            <Select
                              v-model:value="segments[idx - 1]!.valid_end_time_tag"
                              class="shift-period-select"
                              :options="TAG_OPTIONS"
                            />
                            <TimePicker
                              v-model:value="segments[idx - 1]!.valid_end_time"
                              class="shift-period-time"
                              format="HH:mm"
                            />
                          </div>
                        </td>
                        <td>
                          <div class="shift-period-stack">
                            <Select
                              v-model:value="segments[idx - 1]!.centre_time_tag"
                              class="shift-period-select"
                              :options="TAG_OPTIONS"
                            />
                            <TimePicker
                              v-model:value="segments[idx - 1]!.centre_time"
                              class="shift-period-time"
                              format="HH:mm"
                            />
                          </div>
                        </td>
                        <td>
                          <Input v-model:value="segments[idx - 1]!.half_time" class="shift-period-input" />
                        </td>
                        <td>
                          <Input v-model:value="segments[idx - 1]!.time_length" class="shift-period-input" />
                        </td>
                        <td>
                          <Input v-model:value="segments[idx - 1]!.remark" class="shift-period-input" />
                        </td>
                        <td class="shift-period-td-meta text-muted-foreground">
                          {{ segmentMetaText(segments[idx - 1]!) || '—' }}
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </fieldset>
              </div>
            </Tabs.TabPane>

            <Tabs.TabPane key="users" tab="设定用户">
              <Space class="mb-2">
                <Button type="primary" @click="openUserPicker">设置用户</Button>
                <Button danger @click="onRemoveUser">移除用户</Button>
              </Space>
              <Table
                :columns="userColumns"
                :data-source="userRows"
                :loading="userLoading"
                :pagination="false"
                :row-key="(r: any) => String(pick(r, 'FID', 'fid'))"
                size="small"
                :row-selection="{
                  type: 'radio',
                  selectedRowKeys: userSelectedKeys,
                  onChange: onUserRowSelectChange,
                }"
              />
            </Tabs.TabPane>
          </Tabs>
        </Spin>
      </Card>
    </div>

    <Modal
      v-model:open="bcFormOpen"
      :cancel-text="'取消'"
      :confirm-loading="bcFormSaving"
      :ok-text="'保存'"
      :title="bcFormMode === 'add' ? '新增' : '修改'"
      width="560px"
      @ok="submitBcForm"
    >
      <table class="bc-master-form" cellspacing="0" cellpadding="0">
        <tbody>
          <tr>
            <th class="bc-master-th bc-master-th-required">班次名称</th>
            <td>
              <Input v-model:value="bcForm.code_name" allow-clear placeholder="必填" />
            </td>
          </tr>
          <tr>
            <th class="bc-master-th">父级菜单</th>
            <td>
              <Select
                v-model:value="bcForm.parent_id"
                allow-clear
                class="w-full"
                :options="parentSelectOptions"
                placeholder="根节点"
                show-search
                option-filter-prop="label"
              />
            </td>
          </tr>
          <tr>
            <th class="bc-master-th">迟到允许值(分)</th>
            <td>
              <Input v-model:value="bcForm.late_allow_minutes" allow-clear placeholder="可空" />
            </td>
          </tr>
          <tr>
            <th class="bc-master-th">早退允许值(分)</th>
            <td>
              <Input v-model:value="bcForm.early_allow_minutes" allow-clear placeholder="可空" />
            </td>
          </tr>
          <tr>
            <th class="bc-master-th">旷工起始值(分)</th>
            <td>
              <Input v-model:value="bcForm.absenteeism_start_minutes" allow-clear placeholder="可空" />
            </td>
          </tr>
          <tr>
            <th class="bc-master-th">加班起始值(分)</th>
            <td>
              <Input v-model:value="bcForm.overtime_start_minutes" allow-clear placeholder="可空" />
            </td>
          </tr>
          <tr>
            <th class="bc-master-th">总小时</th>
            <td>
              <Input v-model:value="bcForm.total_hours" allow-clear placeholder="可空" />
            </td>
          </tr>
          <tr>
            <th class="bc-master-th bc-master-th-required">刷卡属性</th>
            <td>
              <Select
                v-model:value="bcForm.sk_attribute"
                class="w-full"
                :options="SK_ATTRIBUTE_OPTIONS"
                placeholder="必选"
              />
            </td>
          </tr>
          <tr>
            <th class="bc-master-th">其他属性</th>
            <td>
              <Input v-model:value="bcForm.other_attribute" :maxlength="10" allow-clear show-count />
            </td>
          </tr>
          <tr>
            <th class="bc-master-th">共享班次</th>
            <td>
              <Checkbox v-model:checked="bcForm.share_bc" />
            </td>
          </tr>
          <tr>
            <th class="bc-master-th">修改人</th>
            <td>
              <Input :value="bcFormModifierLabel" disabled />
            </td>
          </tr>
        </tbody>
      </table>
    </Modal>

    <Modal
      v-model:open="userPickOpen"
      destroy-on-close
      title="选择列表"
      width="960px"
      :footer="null"
      @cancel="closeUserPickModal"
    >
      <Space class="user-pick-toolbar mb-3" wrap>
        <Button
          class="user-pick-btn-ok"
          type="primary"
          @click="confirmUserPick"
        >
          ✓ 确定
        </Button>
        <Button class="user-pick-btn-cancel" danger @click="closeUserPickModal">
          ✕ 取消
        </Button>
        <Checkbox v-model:checked="userPickUnion">并集</Checkbox>
        <Input
          v-model:value="userPickSearchDraft"
          allow-clear
          class="min-w-[200px]"
          placeholder="用户名 / 姓名"
          @press-enter="onUserPickQuery"
        />
        <Button type="primary" @click="onUserPickQuery">查询</Button>
      </Space>
      <Spin :spinning="userPickLoading">
        <Table
          :columns="userPickColumns"
          :data-source="userPickRows"
          :pagination="userPickPagination"
          :row-key="(r: any) => String(pick(r, 'id', 'ID'))"
          size="small"
          :scroll="{ x: 860, y: 360 }"
          :row-selection="{
            type: 'checkbox',
            selectedRowKeys: userPickSelected,
            onChange: onUserPickSelectChange,
            preserveSelectedRowKeys: true,
          }"
          @change="(pag) => onUserPickTableChange(pag)"
        />
      </Spin>
    </Modal>
  </Page>
</template>

<style scoped>
/* 对齐老系统：fieldset + 表头浅绿 + 时间列上下叠放 */
.shift-period-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.shift-period-fieldset {
  margin: 0;
  padding: 8px 10px 10px;
  border: 1px solid #aaa;
  border-radius: 2px;
  min-width: 0;
}

.shift-period-legend {
  padding: 0 6px;
  font-size: 13px;
  font-weight: 600;
}

.shift-period-table {
  width: 100%;
  table-layout: fixed;
  border-collapse: collapse;
  font-size: 12px;
}

.shift-period-table thead th {
  background: #d9edc9;
  border: 1px solid #b8c9a8;
  padding: 6px 4px;
  text-align: center;
  font-weight: 600;
  vertical-align: middle;
  line-height: 1.3;
}

.shift-period-th-narrow {
  width: 48px;
}

.shift-period-table tbody td {
  border: 1px solid #d9d9d9;
  padding: 6px 4px;
  vertical-align: middle;
}

.shift-period-td-center {
  text-align: center;
}

.shift-period-td-meta {
  font-size: 11px;
  line-height: 1.4;
  word-break: break-all;
  text-align: left;
}

.shift-period-stack {
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 6px;
  width: 100%;
  max-width: 7.5rem;
  margin: 0 auto;
}

.shift-period-select :deep(.ant-select) {
  width: 100%;
}

.shift-period-time :deep(.ant-picker) {
  width: 100%;
}

.shift-period-input {
  width: 100%;
  min-width: 0;
}

/* 老系统新增弹窗：标签行浅绿，必填项略强调 */
.bc-master-form {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}

.bc-master-form th,
.bc-master-form td {
  border: 1px solid #b8c9a8;
  padding: 8px 10px;
  vertical-align: middle;
}

.bc-master-th {
  width: 168px;
  background: #d9edc9;
  font-weight: 600;
  text-align: right;
}

.bc-master-th-required {
  background: #e8f4d9;
}

/* 选择列表：接近老系统确定绿 / 取消红 */
.user-pick-btn-ok {
  background: #52c41a !important;
  border-color: #389e0d !important;
}

.user-pick-btn-ok:hover {
  background: #73d13d !important;
  border-color: #52c41a !important;
}

.user-pick-toolbar {
  align-items: center;
}
</style>
