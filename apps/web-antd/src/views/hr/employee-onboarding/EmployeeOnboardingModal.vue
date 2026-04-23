<script lang="ts" setup>
import type { Rule } from 'ant-design-vue/es/form';
import {
  Alert,
  AutoComplete,
  Button,
  Card,
  Col,
  Collapse,
  CollapsePanel,
  DatePicker,
  Form,
  FormItem,
  Input,
  InputNumber,
  message,
  Modal,
  Radio,
  RadioGroup,
  Row,
  Select,
  Space,
  Spin,
  Tabs,
  TreeSelect,
} from 'ant-design-vue';
import dayjs from 'dayjs';
import { computed, reactive, ref, watch } from 'vue';
import { useUserStore } from '@vben/stores';

import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

import {
  createEmployeeOnboarding,
  getEmployeeOnboardingDetail,
  updateEmployeeOnboarding,
  uploadEmployeeOnboardingPhotos,
  type CreateOnboardingPayload,
} from './employeeOnboardingApi';

const open = defineModel<boolean>('open', { default: false });

const props = defineProps<{
  /** 员工主键 Guid，有值时弹窗为编辑并拉取详情 */
  editEmployeeId?: string | null;
}>();

const editId = computed(() => {
  const id = props.editEmployeeId;
  if (id == null) return null;
  const s = String(id).trim();
  return s.length ? s : null;
});

const modalTitle = computed(() =>
  editId.value ? '编辑员工' : '人员入职',
);

const emit = defineEmits<{ saved: [] }>();

const QUERY_URL = backendApi('DynamicQueryBeta/queryforvben');

interface WhereCondition {
  Field: string;
  Operator: string;
  Value: string;
}
interface WhereNode {
  Logic: string;
  Conditions: WhereCondition[];
  Groups?: WhereNode[];
}

function whereEq(field: string, value: string): WhereNode {
  return {
    Logic: 'AND',
    Conditions: [{ Field: field, Operator: 'eq', Value: value }],
    Groups: [],
  };
}

async function queryItems(
  table: string,
  where: WhereNode,
  pageSize = 500,
  sortBy = 'sort',
  sortOrder: 'asc' | 'desc' = 'asc',
): Promise<Record<string, unknown>[]> {
  const res = await requestClient.post<{ items: Record<string, unknown>[] }>(
    QUERY_URL,
    {
      TableName: table,
      Page: 1,
      PageSize: pageSize,
      SortBy: sortBy,
      SortOrder: sortOrder,
      Where: where,
    },
  );
  return res?.items ?? [];
}

/** 与 Create.cshtml 一致：v_data_base_dictionary_detail，按 sort 排序，剔除停用项 */
async function loadDictDetail(
  code: string,
  opts?: { sortOrder?: 'asc' | 'desc'; pageSize?: number },
) {
  const sortOrder = opts?.sortOrder ?? 'asc';
  const pageSize = opts?.pageSize ?? 2000;
  return queryItems(
    'v_data_base_dictionary_detail',
    whereEq('code', code),
    pageSize,
    'sort',
    sortOrder,
  );
}

function isDictRowActive(row: Record<string, unknown>) {
  const s = row.is_stop;
  if (s == null || s === '') return true;
  const t = String(s).trim().toLowerCase();
  return t !== '1' && t !== 'y' && t !== 'yes' && t !== 'true' && t !== '是';
}

interface DeptRow {
  id: string;
  name: string;
  parent_id: string | null;
}

function flatToTreeSelect(rows: DeptRow[]) {
  type Node = { title: string; value: string; children?: Node[] };
  const map = new Map<string, Node>();
  const tree: Node[] = [];
  for (const r of rows) {
    map.set(r.id, { title: r.name, value: r.id, children: [] });
  }
  for (const r of rows) {
    const node = map.get(r.id)!;
    const pid = r.parent_id;
    if (pid && map.has(pid)) {
      const p = map.get(pid)!;
      if (!p.children) p.children = [];
      p.children.push(node);
    } else {
      tree.push(node);
    }
  }
  return tree;
}

const userStore = useUserStore();
const loading = ref(false);
const saving = ref(false);
/** 编辑模式下展示只读工号（详情接口 code） */
const employeeCodeDisplay = ref('');

const deptRows = ref<DeptRow[]>([]);
const deptTree = computed(() => flatToTreeSelect(deptRows.value));
const regionRows = ref<DeptRow[]>([]);
const regionTree = computed(() => flatToTreeSelect(regionRows.value));

const companyOptions = ref<{ label: string; value: string }[]>([]);
const nationOptions = ref<{ label: string; value: string }[]>([]);
const idCardTypeOptions = ref<{ label: string; value: string }[]>([]);
const empTypeOptions = ref<{ label: string; value: string }[]>([]);
const gradeLevelOptions = ref<{ label: string; value: string }[]>([]);
const healthCertOptions = ref<{ label: string; value: string }[]>([]);
const recruitingChannelOptions = ref<{ label: string; value: string }[]>([]);
const educationOptions = ref<{ label: string; value: string }[]>([]);
const politicalOptions = ref<{ label: string; value: string }[]>([]);
const contractTypeOptions = ref<{ label: string; value: string }[]>([]);
const trainTypeOptions = ref<{ label: string; value: string }[]>([]);
const depositBankOptions = ref<{ label: string; value: string }[]>([]);
const networkRecruitingOptions = ref<{ label: string; value: string }[]>([]);
const dispatchCompanyOptions = ref<{ label: string; value: string }[]>([]);
const dispatchSettlementOptions = ref<{ label: string; value: string }[]>([]);
const specialEquipmentOptions = ref<{ label: string; value: string }[]>([]);

const dutyOptions = ref<{ label: string; value: string }[]>([]);
const rankOptions = ref<{ label: string; value: string }[]>([]);

/** 老系统 Create.cshtml 婚姻下拉固定三项 */
const maritalOptions = [
  { value: '未婚', label: '未婚' },
  { value: '已婚', label: '已婚' },
  { value: '离异', label: '离异' },
];

const collapseKeys = [
  'id',
  'job',
  'health',
  'hr',
  'contract',
  'train',
  'dispatch',
];

function mapDictRows(rows: any[]) {
  return rows
    .filter((r) => isDictRowActive(r as Record<string, unknown>))
    .map((r) => ({
      value: String(r.name ?? '').trim(),
      label: String(r.name ?? '').trim(),
    }))
    .filter((o) => o.label.length > 0);
}

const formState = reactive({
  name: '',
  gender: '男',
  brithDate: undefined as string | undefined,
  nation: undefined as string | undefined,
  nativePlace: '',
  addr: '',
  idCardType: '身份证',
  idCardNo: '',
  idCardLicence: '',
  idCardStartDate: undefined as string | undefined,
  idCardEndDate: undefined as string | undefined,
  nowAddr: '',
  isPartyMember: 0,
  isVeteran: 0,
  ishandicapped: 0,
  isMartyr: 0,
  isSingleParent: 0,
  isMilitary: 0,
  isLowIncomeAid: 0,
  mobileNo: '',
  phoneNo: '',
  compId: undefined as string | undefined,
  deptId: undefined as string | undefined,
  dutyId: undefined as string | undefined,
  rankId: undefined as string | undefined,
  type: '合同工',
  gradeLevel: 'L',
  fristJoinDate: dayjs().format('YYYY-MM-DD'),
  empNormalDate: dayjs().add(3, 'month').format('YYYY-MM-DD'),
  specialequipment: undefined as string | undefined,
  specialequipmentDate: undefined as string | undefined,
  specialequipmentPlace: '',
  entryInformation: '',
  recruitingChannel: undefined as string | undefined,
  school: '',
  specialty: '',
  empEducation: undefined as string | undefined,
  politicalStatus: undefined as string | undefined,
  maritalStatus: undefined as string | undefined,
  empTimeCard: '',
  bcId: '',
  depositBank: undefined as string | undefined,
  bankBranch: '',
  bankAttribution: '',
  regionCode: undefined as string | undefined,
  contact: '',
  contactTel: '',
  contactAddr: '',
  networkRecruiting: undefined as string | undefined,
  reference: '',
  remake: '',
  contractType: undefined as string | undefined,
  contractStartDate: undefined as string | undefined,
  contractEndDate: undefined as string | undefined,
  contractPeriod: undefined as number | undefined,
  probationStartDate: undefined as string | undefined,
  probationEndDate: undefined as string | undefined,
  probationPeriod: undefined as number | undefined,
  healthCertType: undefined as string | undefined,
  healthLimitedPeriod: '',
  healthStartTime: undefined as string | undefined,
  healthEndTime: undefined as string | undefined,
  trainType: undefined as string | undefined,
  trainServicePeriod: '',
  trainServiceStart: undefined as string | undefined,
  trainServiceEnd: undefined as string | undefined,
  dispatchCompany: undefined as string | undefined,
  dispatchSettlementMethod: undefined as string | undefined,
  dispatchCompany2: undefined as string | undefined,
  dispatchSettlementMethod2: undefined as string | undefined,
});

const rules: Record<string, Rule[]> = {
  name: [{ required: true, message: '请输入姓名' }],
  mobileNo: [{ required: true, message: '请输入手机号' }],
  idCardNo: [{ required: true, message: '请输入证件号码' }],
  idCardType: [{ required: true, message: '请选择证件类型' }],
  compId: [{ required: true, message: '请选择公司' }],
  deptId: [{ required: true, message: '请选择部门' }],
  dutyId: [{ required: true, message: '请选择岗位' }],
  type: [{ required: true, message: '请选择员工类型' }],
  gradeLevel: [{ required: true, message: '请选择职等' }],
  fristJoinDate: [{ required: true, message: '请选择入职日期' }],
};

async function loadDepartments() {
  const items = await queryItems('v_t_base_department', {
    Logic: 'AND',
    Conditions: [],
    Groups: [],
  });
  deptRows.value = (items as any[]).map((r) => ({
    id: String(r.id),
    name: String(r.name ?? ''),
    parent_id: r.parent_id ? String(r.parent_id) : null,
  }));
}

async function loadRegions() {
  const items = await queryItems(
    'v_t_base_region_city',
    { Logic: 'AND', Conditions: [], Groups: [] },
    6000,
    'id',
    'asc',
  );
  regionRows.value = (items as any[]).map((r) => ({
    id: String(r.id),
    name: String(r.name ?? ''),
    parent_id: r.parent_id != null ? String(r.parent_id) : null,
  }));
}

async function loadCompanies() {
  const items = await queryItems('v_t_base_company', {
    Logic: 'AND',
    Conditions: [],
    Groups: [],
  });
  companyOptions.value = (items as any[]).map((r) => ({
    value: String(r.FID),
    label: `${String(r.SimpleName ?? '').trim()} — ${String(r.Name ?? '').trim()}`,
  }));
}

async function loadReferenceData(opts?: { skipLoading?: boolean }) {
  const manageLoading = opts?.skipLoading !== true;
  if (manageLoading) loading.value = true;
  try {
    await Promise.all([
      loadDepartments(),
      loadCompanies(),
      loadRegions(),
      loadDictDetail('hr_mingzu').then((rows) => {
        nationOptions.value = mapDictRows(rows as any[]);
      }),
      loadDictDetail('hr_IDCardType').then((rows) => {
        idCardTypeOptions.value = mapDictRows(rows as any[]);
      }),
      loadDictDetail('hr_yuangongleixing').then((rows) => {
        empTypeOptions.value = (rows as any[])
          .filter((r) => isDictRowActive(r as Record<string, unknown>))
          .map((r) => ({
            value: String(r.name ?? '').trim(),
            label: String(r.name ?? '').trim(),
          }))
          .filter((o) => o.label.length > 0 && !o.label.includes('暑') && !o.label.includes('寒假'));
      }),
      loadDictDetail('hr_GradeLevel').then((rows) => {
        gradeLevelOptions.value = (rows as any[])
          .filter((r) => isDictRowActive(r as Record<string, unknown>))
          .map((r) => ({
            value: String(r.value ?? r.name ?? '')
              .trim()
              .charAt(0),
            label: String(r.name ?? '').trim(),
          }))
          .filter((o) => o.label.length > 0);
      }),
      loadDictDetail('hr_HealthCertificate', { sortOrder: 'desc' })
        .then((rows) => {
          healthCertOptions.value = mapDictRows(rows as any[]);
        })
        .catch(() => {
          healthCertOptions.value = [];
        }),
      loadDictDetail('hr_RecruitingChannel').then((rows) => {
        recruitingChannelOptions.value = mapDictRows(rows as any[]);
      }),
      loadDictDetail('hr_xueli', { sortOrder: 'asc' }).then((rows) => {
        educationOptions.value = mapDictRows(rows as any[]);
      }),
      loadDictDetail('hr_zhengzhimianmao').then((rows) => {
        politicalOptions.value = mapDictRows(rows as any[]);
      }),
      loadDictDetail('hr_ContractType').then((rows) => {
        contractTypeOptions.value = mapDictRows(rows as any[]);
      }),
      loadDictDetail('hr_TrainService', { sortOrder: 'desc' }).then(
        (rows) => {
          trainTypeOptions.value = mapDictRows(rows as any[]);
        },
      ),
      loadDictDetail('DepositBank', { pageSize: 8000 }).then((rows) => {
        depositBankOptions.value = mapDictRows(rows as any[]);
      }),
      loadDictDetail('NetworkRecruiting').then((rows) => {
        networkRecruitingOptions.value = mapDictRows(rows as any[]);
      }),
      loadDictDetail('hr_DispatchCompany', { pageSize: 8000 }).then(
        (rows) => {
          dispatchCompanyOptions.value = mapDictRows(rows as any[]);
        },
      ),
      loadDictDetail('hr_DispatchSettlementMethod').then((rows) => {
        dispatchSettlementOptions.value = mapDictRows(rows as any[]);
      }),
      loadDictDetail('exoticwarrant').then((rows) => {
        specialEquipmentOptions.value = mapDictRows(rows as any[]);
      }),
    ]);
  } catch (e: unknown) {
    message.error(e instanceof Error ? e.message : '加载基础数据失败');
  } finally {
    if (manageLoading) loading.value = false;
  }
}

async function loadDutyAndRank(
  deptId: string,
  options?: { resetSelection?: boolean },
) {
  const resetSelection = options?.resetSelection !== false;
  dutyOptions.value = [];
  rankOptions.value = [];
  if (resetSelection) {
    formState.dutyId = undefined;
    formState.rankId = undefined;
  }
  if (!deptId) return;
  const [posts, ranks] = await Promise.all([
    queryItems('v_t_base_post', whereEq('department_id', deptId), 2000),
    queryItems('v_base_dep_rank', whereEq('department_id', deptId), 2000),
  ]);
  const dutyMap = new Map<string, string>();
  for (const p of posts as any[]) {
    const id = String(p.duty_id ?? '').trim();
    if (!id || dutyMap.has(id)) continue;
    dutyMap.set(id, String(p.duty_name ?? '').trim());
  }
  dutyOptions.value = [...dutyMap.entries()].map(([value, label]) => ({
    value,
    label,
  }));
  const rankMap = new Map<string, string>();
  for (const r of ranks as any[]) {
    const id = String(r.rank_id ?? '').trim();
    if (!id || rankMap.has(id)) continue;
    rankMap.set(id, String(r.rank_name ?? '').trim());
  }
  rankOptions.value = [...rankMap.entries()].map(([value, label]) => ({
    value,
    label,
  }));
}

watch(
  () => formState.deptId,
  (id, prev) => {
    if (!id) {
      dutyOptions.value = [];
      rankOptions.value = [];
      formState.dutyId = undefined;
      formState.rankId = undefined;
      return;
    }
    const changed =
      prev != null && String(prev).trim() !== '' && String(prev) !== String(id);
    void loadDutyAndRank(String(id), { resetSelection: changed });
  },
);

function resetForm() {
  Object.assign(formState, {
    name: '',
    gender: '男',
    brithDate: undefined,
    nation: undefined,
    nativePlace: '',
    addr: '',
    idCardType: '身份证',
    idCardNo: '',
    idCardLicence: '',
    idCardStartDate: undefined,
    idCardEndDate: undefined,
    nowAddr: '',
    isPartyMember: 0,
    isVeteran: 0,
    ishandicapped: 0,
    isMartyr: 0,
    isSingleParent: 0,
    isMilitary: 0,
    isLowIncomeAid: 0,
    mobileNo: '',
    phoneNo: '',
    compId: undefined,
    deptId: undefined,
    dutyId: undefined,
    rankId: undefined,
    type: '合同工',
    gradeLevel: 'L',
    fristJoinDate: dayjs().format('YYYY-MM-DD'),
    empNormalDate: dayjs().add(3, 'month').format('YYYY-MM-DD'),
    specialequipment: undefined,
    specialequipmentDate: undefined,
    specialequipmentPlace: '',
    entryInformation: '',
    recruitingChannel: undefined,
    school: '',
    specialty: '',
    empEducation: undefined,
    politicalStatus: undefined,
    maritalStatus: undefined,
    empTimeCard: '',
    bcId: '',
    depositBank: undefined,
    bankBranch: '',
    bankAttribution: '',
    regionCode: undefined,
    contact: '',
    contactTel: '',
    contactAddr: '',
    networkRecruiting: undefined,
    reference: '',
    remake: '',
    contractType: undefined,
    contractStartDate: undefined,
    contractEndDate: undefined,
    contractPeriod: undefined,
    probationStartDate: undefined,
    probationEndDate: undefined,
    probationPeriod: undefined,
    healthCertType: undefined,
    healthLimitedPeriod: '',
    healthStartTime: undefined,
    healthEndTime: undefined,
    trainType: undefined,
    trainServicePeriod: '',
    trainServiceStart: undefined,
    trainServiceEnd: undefined,
    dispatchCompany: undefined,
    dispatchSettlementMethod: undefined,
    dispatchCompany2: undefined,
    dispatchSettlementMethod2: undefined,
  });
  clearBadgePhoto();
  clearDoorPhoto();
  dutyOptions.value = [];
  rankOptions.value = [];
}

function toOptStr(v: unknown): string | undefined {
  if (v == null) return undefined;
  const s = String(v).trim();
  return s === '' ? undefined : s;
}

function genderFromIdCard(idCardNo?: string): '男' | '女' | null {
  const s = (idCardNo ?? '').trim();
  if (!/^\d{17}[\dXx]$/.test(s)) return null;
  const g = s.charAt(16);
  const n = Number(g);
  if (!Number.isFinite(n)) return null;
  return n % 2 === 0 ? '女' : '男';
}

function normalizeGender(
  v: unknown,
  opts?: { idCardNo?: string },
): '男' | '女' {
  const s = String(v ?? '').trim();
  if (!s) return genderFromIdCard(opts?.idCardNo) ?? '男';

  const low = s.toLowerCase();
  if (s === '男' || low === 'm' || low === 'male') return '男';
  if (s === '女' || low === 'f' || low === 'female') return '女';

  // 兼容部分库里存的“先生/女士”等，兜底按包含关键字判断
  if (s.includes('女')) return '女';
  if (s.includes('男')) return '男';

  // 0/1/true/false 等存法不统一：优先用身份证号推断
  if (s === '0' || s === '1' || low === 'true' || low === 'false') {
    return genderFromIdCard(opts?.idCardNo) ?? '男';
  }

  return genderFromIdCard(opts?.idCardNo) ?? '男';
}

function toNum01(v: unknown): number {
  return Number(v) === 1 ? 1 : 0;
}

function toOptNum(v: unknown): number | undefined {
  if (v == null || v === '') return undefined;
  const n = Number(v);
  return Number.isFinite(n) ? n : undefined;
}

function applyDetailToForm(d: Record<string, unknown>) {
  formState.name = String(d.name ?? '').trim();
  const idCardNo = String(d.idCardNo ?? '').trim();
  formState.gender = normalizeGender(d.gender, { idCardNo });
  formState.brithDate = toOptStr(d.brithDate);
  formState.nation = toOptStr(d.nation);
  formState.nativePlace = String(d.nativePlace ?? '').trim();
  formState.addr = String(d.addr ?? '').trim();
  formState.idCardType = String(d.idCardType ?? '身份证').trim() || '身份证';
  formState.idCardNo = idCardNo;
  formState.idCardLicence = String(d.idCardLicence ?? '').trim();
  formState.idCardStartDate = toOptStr(d.idCardStartDate);
  formState.idCardEndDate = toOptStr(d.idCardEndDate);
  formState.nowAddr = String(d.nowAddr ?? '').trim();
  formState.isPartyMember = toNum01(d.isPartyMember);
  formState.isVeteran = toNum01(d.isVeteran);
  formState.ishandicapped = toNum01(d.ishandicapped);
  formState.isMartyr = toNum01(d.isMartyr);
  formState.isSingleParent = toNum01(d.isSingleParent);
  formState.isMilitary = toNum01(d.isMilitary);
  formState.isLowIncomeAid = toNum01(d.isLowIncomeAid);
  formState.mobileNo = String(d.mobileNo ?? '').trim();
  formState.phoneNo = String(d.phoneNo ?? '').trim();
  formState.compId = toOptStr(d.compId);
  formState.deptId = toOptStr(d.deptId);
  formState.dutyId = toOptStr(d.dutyId);
  formState.rankId = toOptStr(d.rankId);
  formState.type = String(d.type ?? '合同工').trim() || '合同工';
  const gl = String(d.gradeLevel ?? 'L').trim();
  formState.gradeLevel = gl.length >= 1 ? gl.charAt(0) : 'L';
  formState.fristJoinDate =
    toOptStr(d.fristJoinDate) ?? formState.fristJoinDate;
  formState.empNormalDate = toOptStr(d.empNormalDate);
  formState.specialequipment = toOptStr(d.specialequipment);
  formState.specialequipmentDate = toOptStr(d.specialequipmentDate);
  formState.specialequipmentPlace = String(
    d.specialequipmentPlace ?? '',
  ).trim();
  formState.entryInformation = String(d.entryInformation ?? '').trim();
  formState.recruitingChannel = toOptStr(d.recruitingChannel);
  formState.school = String(d.school ?? '').trim();
  formState.specialty = String(d.specialty ?? '').trim();
  formState.empEducation = toOptStr(d.empEducation);
  formState.politicalStatus = toOptStr(d.politicalStatus);
  formState.maritalStatus = toOptStr(d.maritalStatus);
  formState.empTimeCard = String(d.empTimeCard ?? '').trim();
  formState.bcId = String(d.bcId ?? '').trim();
  formState.depositBank = toOptStr(d.depositBank);
  formState.bankBranch = String(d.bankBranch ?? '').trim();
  formState.bankAttribution = String(d.bankAttribution ?? '').trim();
  formState.regionCode = toOptStr(d.regionCode);
  formState.contact = String(d.contact ?? '').trim();
  formState.contactTel = String(d.contactTel ?? '').trim();
  formState.contactAddr = String(d.contactAddr ?? '').trim();
  formState.networkRecruiting = toOptStr(d.networkRecruiting);
  formState.reference = String(d.reference ?? '').trim();
  formState.remake = String(d.remake ?? '').trim();
  formState.contractType = toOptStr(d.contractType);
  formState.contractStartDate = toOptStr(d.contractStartDate);
  formState.contractEndDate = toOptStr(d.contractEndDate);
  formState.contractPeriod = toOptNum(d.contractPeriod);
  formState.probationStartDate = toOptStr(d.probationStartDate);
  formState.probationEndDate = toOptStr(d.probationEndDate);
  formState.probationPeriod = toOptNum(d.probationPeriod);
  formState.healthCertType = toOptStr(d.healthCertType);
  formState.healthLimitedPeriod = String(d.healthLimitedPeriod ?? '').trim();
  formState.healthStartTime = toOptStr(d.healthStartTime);
  formState.healthEndTime = toOptStr(d.healthEndTime);
  formState.trainType = toOptStr(d.trainType);
  formState.trainServicePeriod = String(d.trainServicePeriod ?? '').trim();
  formState.trainServiceStart = toOptStr(d.trainServiceStart);
  formState.trainServiceEnd = toOptStr(d.trainServiceEnd);
  formState.dispatchCompany = toOptStr(d.dispatchCompany);
  formState.dispatchSettlementMethod = toOptStr(d.dispatchSettlementMethod);
  formState.dispatchCompany2 = toOptStr(d.dispatchCompany2);
  formState.dispatchSettlementMethod2 = toOptStr(
    d.dispatchSettlementMethod2,
  );
}

watch(open, async (v) => {
  if (!v) return;
  employeeCodeDisplay.value = '';
  resetForm();
  const eid = editId.value;
  if (eid) {
    loading.value = true;
    try {
      await loadReferenceData({ skipLoading: true });
      const detail = await getEmployeeOnboardingDetail(eid);
      employeeCodeDisplay.value = String(detail.code ?? '').trim();
      applyDetailToForm(detail as Record<string, unknown>);
    } catch (e: unknown) {
      message.error(e instanceof Error ? e.message : '加载员工详情失败');
      open.value = false;
    } finally {
      loading.value = false;
    }
  } else {
    loadReferenceData();
  }
});

const formRef = ref();

const badgeFile = ref<File | null>(null);
const doorFile = ref<File | null>(null);
const badgePreviewUrl = ref('');
const doorPreviewUrl = ref('');
const badgePickInputRef = ref<HTMLInputElement | null>(null);
const badgeCamInputRef = ref<HTMLInputElement | null>(null);
const doorPickInputRef = ref<HTMLInputElement | null>(null);
const doorCamInputRef = ref<HTMLInputElement | null>(null);

function revokePreview(url: string) {
  if (url.startsWith('blob:')) URL.revokeObjectURL(url);
}

function clearBadgePhoto() {
  revokePreview(badgePreviewUrl.value);
  badgePreviewUrl.value = '';
  badgeFile.value = null;
}

function clearDoorPhoto() {
  revokePreview(doorPreviewUrl.value);
  doorPreviewUrl.value = '';
  doorFile.value = null;
}

function onBadgeFileInput(e: Event) {
  const el = e.target as HTMLInputElement;
  const f = el.files?.[0];
  el.value = '';
  if (!f) return;
  if (!f.type.startsWith('image/')) {
    message.warning('请选择图片文件');
    return;
  }
  revokePreview(badgePreviewUrl.value);
  badgeFile.value = f;
  badgePreviewUrl.value = URL.createObjectURL(f);
}

function onDoorFileInput(e: Event) {
  const el = e.target as HTMLInputElement;
  const f = el.files?.[0];
  el.value = '';
  if (!f) return;
  if (!f.type.startsWith('image/')) {
    message.warning('请选择图片文件');
    return;
  }
  revokePreview(doorPreviewUrl.value);
  doorFile.value = f;
  doorPreviewUrl.value = URL.createObjectURL(f);
}

async function onOk() {
  try {
    await formRef.value?.validate();
  } catch {
    return Promise.reject(new Error('validate'));
  }
  const u = userStore.userInfo as Record<string, unknown> | null | undefined;
  const modifyName =
    (u?.realName as string) ||
    (u?.username as string) ||
    (u?.name as string) ||
    '';

  const payload: CreateOnboardingPayload = {
    name: formState.name.trim(),
    gender: formState.gender,
    brithDate: formState.brithDate,
    nation: formState.nation,
    nativePlace: formState.nativePlace || undefined,
    addr: formState.addr || undefined,
    idCardType: formState.idCardType,
    idCardNo: formState.idCardNo.trim(),
    idCardLicence: formState.idCardLicence || undefined,
    idCardStartDate: formState.idCardStartDate,
    idCardEndDate: formState.idCardEndDate,
    nowAddr: formState.nowAddr || undefined,
    isPartyMember: formState.isPartyMember,
    isVeteran: formState.isVeteran,
    ishandicapped: formState.ishandicapped,
    isMartyr: formState.isMartyr,
    isSingleParent: formState.isSingleParent,
    isMilitary: formState.isMilitary,
    isLowIncomeAid: formState.isLowIncomeAid,
    mobileNo: formState.mobileNo.trim(),
    phoneNo: formState.phoneNo || undefined,
    compId: formState.compId!,
    deptId: formState.deptId!,
    dutyId: formState.dutyId!,
    rankId: formState.rankId,
    type: formState.type,
    gradeLevel: formState.gradeLevel,
    fristJoinDate: formState.fristJoinDate,
    empNormalDate: formState.empNormalDate,
    modifyName: modifyName || undefined,
    specialequipment: formState.specialequipment,
    specialequipmentDate: formState.specialequipmentDate,
    specialequipmentPlace: formState.specialequipmentPlace || undefined,
    entryInformation: formState.entryInformation || undefined,
    recruitingChannel: formState.recruitingChannel,
    school: formState.school || undefined,
    specialty: formState.specialty || undefined,
    empEducation: formState.empEducation,
    politicalStatus: formState.politicalStatus,
    maritalStatus: formState.maritalStatus,
    empTimeCard: formState.empTimeCard || undefined,
    bcId: formState.bcId || undefined,
    depositBank: formState.depositBank,
    bankBranch: formState.bankBranch || undefined,
    bankAttribution: formState.bankAttribution || undefined,
    regionCode: formState.regionCode,
    contact: formState.contact || undefined,
    contactTel: formState.contactTel || undefined,
    contactAddr: formState.contactAddr || undefined,
    networkRecruiting: formState.networkRecruiting,
    reference: formState.reference || undefined,
    remake: formState.remake || undefined,
    contractType: formState.contractType,
    contractStartDate: formState.contractStartDate,
    contractEndDate: formState.contractEndDate,
    contractPeriod: formState.contractPeriod,
    probationStartDate: formState.probationStartDate,
    probationEndDate: formState.probationEndDate,
    probationPeriod: formState.probationPeriod,
    healthCertType: formState.healthCertType,
    healthLimitedPeriod: formState.healthLimitedPeriod || undefined,
    healthStartTime: formState.healthStartTime,
    healthEndTime: formState.healthEndTime,
    trainType: formState.trainType,
    trainServicePeriod: formState.trainServicePeriod || undefined,
    trainServiceStart: formState.trainServiceStart,
    trainServiceEnd: formState.trainServiceEnd,
    dispatchCompany: formState.dispatchCompany,
    dispatchSettlementMethod: formState.dispatchSettlementMethod,
    dispatchCompany2: formState.dispatchCompany2,
    dispatchSettlementMethod2: formState.dispatchSettlementMethod2,
  };

  saving.value = true;
  try {
    const eid = editId.value;
    const data = eid
      ? await updateEmployeeOnboarding({ ...payload, id: eid })
      : await createEmployeeOnboarding(payload);
    const code =
      String(data.code ?? '').trim() ||
      employeeCodeDisplay.value ||
      '';
    if (badgeFile.value || doorFile.value) {
      if (!code) {
        message.warning('已保存，但缺少工号无法上传照片');
      } else {
        try {
          await uploadEmployeeOnboardingPhotos({
            employeeCode: code,
            badgePhoto: badgeFile.value ?? undefined,
            doorPhoto: doorFile.value ?? undefined,
          });
          message.success(`保存成功，工号：${code}，照片已上传`);
        } catch (e: unknown) {
          message.warning(
            `员工已保存（工号 ${code}），照片上传失败：${
              e instanceof Error ? e.message : String(e)
            }`,
          );
        }
      }
    } else {
      message.success(`保存成功，工号：${code || '—'}`);
    }
    open.value = false;
    emit('saved');
  } catch (err: unknown) {
    const msg =
      err && typeof err === 'object' && 'message' in err
        ? String((err as { message?: string }).message)
        : String(err);
    message.error(msg || '保存失败');
    return Promise.reject(err);
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <Modal
    v-model:open="open"
    :title="modalTitle"
    :width="'calc(100vw - 16px)'"
    :centered="false"
    :confirm-loading="saving"
    :mask-closable="false"
    destroy-on-close
    ok-text="保存"
    wrap-class-name="employee-onboarding-modal-wrap"
    @ok="onOk"
  >
    <Spin :spinning="loading">
      <Form
        ref="formRef"
        class="employee-onboarding-form employee-onboarding-form-horizontal"
        :model="formState"
        :rules="rules"
        layout="horizontal"
        :colon="false"
        label-align="right"
        :label-col="{ flex: '0 0 118px' }"
        :wrapper-col="{ flex: '1', style: { minWidth: 0 } }"
      >
        <Row :gutter="16">
          <Col :span="17">
            <Collapse :default-active-key="collapseKeys" :bordered="false">
              <CollapsePanel key="id" header="身份信息">
                <Row :gutter="16">
                  <Col :span="8">
                    <FormItem label="姓名" name="name" required>
                      <Input v-model:value="formState.name" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="性别" name="gender">
                      <RadioGroup v-model:value="formState.gender">
                        <Radio value="男">男</Radio>
                        <Radio value="女">女</Radio>
                      </RadioGroup>
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="出生日期" name="brithDate">
                      <DatePicker
                        v-model:value="formState.brithDate"
                        class="w-full"
                        value-format="YYYY-MM-DD"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="民族" name="nation">
                      <AutoComplete
                        v-model:value="formState.nation"
                        :options="nationOptions"
                        allow-clear
                        placeholder="请选择或输入"
                        class="w-full"
                        :filter-option="
                          (input, opt) =>
                            String((opt as { value?: string })?.value ?? '')
                              .toLowerCase()
                              .includes(String(input).toLowerCase())
                        "
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="籍贯" name="nativePlace">
                      <Input v-model:value="formState.nativePlace" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="24">
                    <FormItem label="身份证地址" name="addr">
                      <Input v-model:value="formState.addr" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="证件类型" name="idCardType" required>
                      <Select
                        v-model:value="formState.idCardType"
                        :options="idCardTypeOptions"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="证件号码" name="idCardNo" required>
                      <Input v-model:value="formState.idCardNo" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="发证机关" name="idCardLicence">
                      <Input v-model:value="formState.idCardLicence" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="证件开始日期" name="idCardStartDate">
                      <DatePicker
                        v-model:value="formState.idCardStartDate"
                        class="w-full"
                        value-format="YYYY-MM-DD"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="证件截止日期" name="idCardEndDate">
                      <DatePicker
                        v-model:value="formState.idCardEndDate"
                        class="w-full"
                        value-format="YYYY-MM-DD"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="读取身份证">
                      <Button disabled>读取身份证</Button>
                    </FormItem>
                  </Col>
                  <Col :span="24">
                    <FormItem label="现居地址" name="nowAddr">
                      <Input v-model:value="formState.nowAddr" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="是否党员" name="isPartyMember">
                      <RadioGroup v-model:value="formState.isPartyMember">
                        <Radio :value="1">是</Radio>
                        <Radio :value="0">否</Radio>
                      </RadioGroup>
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="是否退伍军人" name="isVeteran">
                      <RadioGroup v-model:value="formState.isVeteran">
                        <Radio :value="1">是</Radio>
                        <Radio :value="0">否</Radio>
                      </RadioGroup>
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="是否残疾人" name="ishandicapped">
                      <RadioGroup v-model:value="formState.ishandicapped">
                        <Radio :value="1">是</Radio>
                        <Radio :value="0">否</Radio>
                      </RadioGroup>
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="是否烈士遗属" name="isMartyr">
                      <RadioGroup v-model:value="formState.isMartyr">
                        <Radio :value="1">是</Radio>
                        <Radio :value="0">否</Radio>
                      </RadioGroup>
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="是否单亲家庭" name="isSingleParent">
                      <RadioGroup v-model:value="formState.isSingleParent">
                        <Radio :value="1">是</Radio>
                        <Radio :value="0">否</Radio>
                      </RadioGroup>
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="是否军人家属" name="isMilitary">
                      <RadioGroup v-model:value="formState.isMilitary">
                        <Radio :value="1">是</Radio>
                        <Radio :value="0">否</Radio>
                      </RadioGroup>
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="是否低保家属" name="isLowIncomeAid">
                      <RadioGroup v-model:value="formState.isLowIncomeAid">
                        <Radio :value="1">是</Radio>
                        <Radio :value="0">否</Radio>
                      </RadioGroup>
                    </FormItem>
                  </Col>
                </Row>
              </CollapsePanel>

              <CollapsePanel key="job" header="入职信息">
                <Row :gutter="16">
                  <Col :span="8">
                    <FormItem label="工号">
                      <Input
                        :value="employeeCodeDisplay"
                        disabled
                        :placeholder="
                          editId ? '工号' : '保存后由系统生成'
                        "
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="公司" name="compId" required>
                      <Select
                        v-model:value="formState.compId"
                        allow-clear
                        show-search
                        :filter-option="
                          (input, opt) =>
                            String(opt?.label ?? '')
                              .toLowerCase()
                              .includes(input.toLowerCase())
                        "
                        :options="companyOptions"
                        placeholder="请选择公司"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="职级" name="rankId">
                      <Select
                        v-model:value="formState.rankId"
                        allow-clear
                        show-search
                        placeholder="先选部门"
                        :options="rankOptions"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="部门" name="deptId" required>
                      <TreeSelect
                        v-model:value="formState.deptId"
                        show-search
                        tree-default-expand-all
                        :dropdown-style="{ maxHeight: '360px' }"
                        placeholder="请选择部门"
                        allow-clear
                        tree-node-filter-prop="title"
                        :field-names="{
                          label: 'title',
                          value: 'value',
                          children: 'children',
                        }"
                        :tree-data="deptTree"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="岗位" name="dutyId" required>
                      <Select
                        v-model:value="formState.dutyId"
                        allow-clear
                        show-search
                        placeholder="先选部门"
                        :options="dutyOptions"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="员工类型" name="type" required>
                      <Select
                        v-model:value="formState.type"
                        :options="empTypeOptions"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="职等" name="gradeLevel" required>
                      <Select
                        v-model:value="formState.gradeLevel"
                        :options="gradeLevelOptions"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="入职日期" name="fristJoinDate" required>
                      <DatePicker
                        v-model:value="formState.fristJoinDate"
                        class="w-full"
                        value-format="YYYY-MM-DD"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="转正日期" name="empNormalDate">
                      <DatePicker
                        v-model:value="formState.empNormalDate"
                        class="w-full"
                        value-format="YYYY-MM-DD"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="特种设备操作证类型" name="specialequipment">
                      <Select
                        v-model:value="formState.specialequipment"
                        allow-clear
                        show-search
                        :options="specialEquipmentOptions"
                        placeholder="请选择"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem
                      label="特种设备操作证有效期"
                      name="specialequipmentDate"
                    >
                      <DatePicker
                        v-model:value="formState.specialequipmentDate"
                        class="w-full"
                        value-format="YYYY-MM-DD"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem
                      label="特种设备发证机关"
                      name="specialequipmentPlace"
                    >
                      <Input
                        v-model:value="formState.specialequipmentPlace"
                        allow-clear
                      />
                    </FormItem>
                  </Col>
                  <Col :span="24">
                    <FormItem label="入职资料" name="entryInformation">
                      <Input.TextArea
                        v-model:value="formState.entryInformation"
                        :rows="3"
                        allow-clear
                        placeholder="可填写需签署的资料清单等"
                      />
                    </FormItem>
                  </Col>
                </Row>
              </CollapsePanel>

              <CollapsePanel key="health" header="健康证明">
                <Row :gutter="16">
                  <Col :span="8">
                    <FormItem label="健康证明类型" name="healthCertType">
                      <Select
                        v-model:value="formState.healthCertType"
                        allow-clear
                        show-search
                        :options="healthCertOptions"
                        placeholder="请选择"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="有效期说明" name="healthLimitedPeriod">
                      <Input
                        v-model:value="formState.healthLimitedPeriod"
                        allow-clear
                        placeholder="如：一年"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="有效期起始" name="healthStartTime">
                      <DatePicker
                        v-model:value="formState.healthStartTime"
                        class="w-full"
                        value-format="YYYY-MM-DD"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="有效期结束" name="healthEndTime">
                      <DatePicker
                        v-model:value="formState.healthEndTime"
                        class="w-full"
                        value-format="YYYY-MM-DD"
                      />
                    </FormItem>
                  </Col>
                </Row>
              </CollapsePanel>

              <CollapsePanel key="hr" header="人事信息">
                <Row :gutter="16">
                  <Col :span="8">
                    <FormItem label="手机号码" name="mobileNo" required>
                      <Input v-model:value="formState.mobileNo" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="招聘渠道" name="recruitingChannel">
                      <Select
                        v-model:value="formState.recruitingChannel"
                        allow-clear
                        show-search
                        :options="recruitingChannelOptions"
                        placeholder="请选择"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="毕业院校" name="school">
                      <Input v-model:value="formState.school" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="专业" name="specialty">
                      <Input v-model:value="formState.specialty" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="学历" name="empEducation">
                      <Select
                        v-model:value="formState.empEducation"
                        allow-clear
                        show-search
                        :options="educationOptions"
                        placeholder="请选择"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="政治面貌" name="politicalStatus">
                      <Select
                        v-model:value="formState.politicalStatus"
                        allow-clear
                        show-search
                        :options="politicalOptions"
                        placeholder="请选择"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="婚姻状况" name="maritalStatus">
                      <Select
                        v-model:value="formState.maritalStatus"
                        allow-clear
                        :options="maritalOptions"
                        placeholder="请选择"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="工卡号码" name="empTimeCard">
                      <Input v-model:value="formState.empTimeCard" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="银行卡号" name="bcId">
                      <Input v-model:value="formState.bcId" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="开户银行" name="depositBank">
                      <AutoComplete
                        v-model:value="formState.depositBank"
                        :options="depositBankOptions"
                        allow-clear
                        placeholder="请选择或输入"
                        class="w-full"
                        :filter-option="
                          (input, opt) =>
                            String((opt as { value?: string })?.value ?? '')
                              .toLowerCase()
                              .includes(String(input).toLowerCase())
                        "
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="开户支行" name="bankBranch">
                      <Input v-model:value="formState.bankBranch" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="开户地（行政区划）" name="regionCode">
                      <TreeSelect
                        v-model:value="formState.regionCode"
                        show-search
                        tree-default-expand-all
                        :dropdown-style="{ maxHeight: '280px' }"
                        placeholder="省市区"
                        allow-clear
                        tree-node-filter-prop="title"
                        :field-names="{
                          label: 'title',
                          value: 'value',
                          children: 'children',
                        }"
                        :tree-data="regionTree"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="开户备注/归属" name="bankAttribution">
                      <Input
                        v-model:value="formState.bankAttribution"
                        allow-clear
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="联系电话" name="phoneNo">
                      <Input v-model:value="formState.phoneNo" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="紧急联系人" name="contact">
                      <Input v-model:value="formState.contact" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="紧急联系人电话" name="contactTel">
                      <Input v-model:value="formState.contactTel" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="24">
                    <FormItem label="紧急联系人地址" name="contactAddr">
                      <Input v-model:value="formState.contactAddr" allow-clear />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="内招渠道" name="networkRecruiting">
                      <AutoComplete
                        v-model:value="formState.networkRecruiting"
                        :options="networkRecruitingOptions"
                        allow-clear
                        placeholder="请选择或输入"
                        class="w-full"
                        :filter-option="
                          (input, opt) =>
                            String((opt as { value?: string })?.value ?? '')
                              .toLowerCase()
                              .includes(String(input).toLowerCase())
                        "
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="介绍人(工号)" name="reference">
                      <Input
                        v-model:value="formState.reference"
                        allow-clear
                        placeholder="最多10位"
                        :maxlength="10"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="24">
                    <FormItem label="备注" name="remake">
                      <Input v-model:value="formState.remake" allow-clear />
                    </FormItem>
                  </Col>
                </Row>
              </CollapsePanel>

              <CollapsePanel key="contract" header="合同与试用期">
                <Row :gutter="16">
                  <Col :span="8">
                    <FormItem label="合同类型" name="contractType">
                      <Select
                        v-model:value="formState.contractType"
                        allow-clear
                        show-search
                        :options="contractTypeOptions"
                        placeholder="请选择"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="合同开始日期" name="contractStartDate">
                      <DatePicker
                        v-model:value="formState.contractStartDate"
                        class="w-full"
                        value-format="YYYY-MM-DD"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="合同结束日期" name="contractEndDate">
                      <DatePicker
                        v-model:value="formState.contractEndDate"
                        class="w-full"
                        value-format="YYYY-MM-DD"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="合同期限(月)" name="contractPeriod">
                      <InputNumber
                        v-model:value="formState.contractPeriod"
                        class="w-full"
                        :min="0"
                        placeholder="月"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="试用开始" name="probationStartDate">
                      <DatePicker
                        v-model:value="formState.probationStartDate"
                        class="w-full"
                        value-format="YYYY-MM-DD"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="试用结束" name="probationEndDate">
                      <DatePicker
                        v-model:value="formState.probationEndDate"
                        class="w-full"
                        value-format="YYYY-MM-DD"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="试用期限(月)" name="probationPeriod">
                      <InputNumber
                        v-model:value="formState.probationPeriod"
                        class="w-full"
                        :min="0"
                      />
                    </FormItem>
                  </Col>
                </Row>
              </CollapsePanel>

              <CollapsePanel key="train" header="专项培训">
                <Row :gutter="16">
                  <Col :span="8">
                    <FormItem label="培训类型" name="trainType">
                      <Select
                        v-model:value="formState.trainType"
                        allow-clear
                        show-search
                        :options="trainTypeOptions"
                        placeholder="请选择"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="服务期说明" name="trainServicePeriod">
                      <Input
                        v-model:value="formState.trainServicePeriod"
                        allow-clear
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="服务期开始" name="trainServiceStart">
                      <DatePicker
                        v-model:value="formState.trainServiceStart"
                        class="w-full"
                        value-format="YYYY-MM-DD"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="8">
                    <FormItem label="服务期结束" name="trainServiceEnd">
                      <DatePicker
                        v-model:value="formState.trainServiceEnd"
                        class="w-full"
                        value-format="YYYY-MM-DD"
                      />
                    </FormItem>
                  </Col>
                </Row>
              </CollapsePanel>

              <CollapsePanel key="dispatch" header="派遣 / 代招">
                <Row :gutter="16">
                  <Col :span="24">
                    <Alert
                      type="info"
                      show-icon
                      message="数据库中派遣与代招共用一个工号一条记录；若同时填写代招，将以代招为准写入（与老系统两次保存最终态一致）。"
                    />
                  </Col>
                  <Col :span="12">
                    <FormItem label="派遣单位" name="dispatchCompany">
                      <AutoComplete
                        v-model:value="formState.dispatchCompany"
                        :options="dispatchCompanyOptions"
                        allow-clear
                        placeholder="请选择或输入"
                        class="w-full"
                        :filter-option="
                          (input, opt) =>
                            String((opt as { value?: string })?.value ?? '')
                              .toLowerCase()
                              .includes(String(input).toLowerCase())
                        "
                      />
                    </FormItem>
                  </Col>
                  <Col :span="12">
                    <FormItem
                      label="派遣结算方式"
                      name="dispatchSettlementMethod"
                    >
                      <Select
                        v-model:value="formState.dispatchSettlementMethod"
                        allow-clear
                        show-search
                        :options="dispatchSettlementOptions"
                        placeholder="请选择"
                      />
                    </FormItem>
                  </Col>
                  <Col :span="12">
                    <FormItem label="代招单位" name="dispatchCompany2">
                      <AutoComplete
                        v-model:value="formState.dispatchCompany2"
                        :options="dispatchCompanyOptions"
                        allow-clear
                        placeholder="请选择或输入"
                        class="w-full"
                        :filter-option="
                          (input, opt) =>
                            String((opt as { value?: string })?.value ?? '')
                              .toLowerCase()
                              .includes(String(input).toLowerCase())
                        "
                      />
                    </FormItem>
                  </Col>
                  <Col :span="12">
                    <FormItem
                      label="代招结算方式"
                      name="dispatchSettlementMethod2"
                    >
                      <Select
                        v-model:value="formState.dispatchSettlementMethod2"
                        allow-clear
                        show-search
                        :options="dispatchSettlementOptions"
                        placeholder="请选择"
                      />
                    </FormItem>
                  </Col>
                </Row>
              </CollapsePanel>
            </Collapse>

            <Card class="mt-2" size="small" :bordered="false">
              <div class="text-muted-foreground text-xs leading-relaxed">
                说明：主表字段写入
                <code>t_base_employee</code>
                ；健康证明、网招、银行卡、专项培训、派遣等写入对应子表。工号由
                <code>dbo.ufn_get_employee_code()</code>
                生成。老系统中的「是否住宿」走宿舍登记子流程，当前库无对应主表列故未做表单项。保存成功后可上传工牌/门禁照至 StoneApi
                wwwroot/images/employeePhotos。身份证读卡需对接硬件。
              </div>
            </Card>
          </Col>

          <Col :span="7">
            <Card size="small" title="照片" :bordered="false">
              <Tabs>
                <Tabs.TabPane key="badge" tab="工牌照片" :force-render="true">
                  <div class="onboarding-photo-panel">
                    <div
                      class="onboarding-photo-preview border-border bg-muted/40 flex min-h-[168px] items-center justify-center overflow-hidden rounded border"
                    >
                      <img
                        v-if="badgePreviewUrl"
                        :src="badgePreviewUrl"
                        alt="工牌预览"
                        class="max-h-56 max-w-full object-contain"
                      />
                      <span v-else class="text-muted-foreground text-sm">
                        暂无预览
                      </span>
                    </div>
                    <Space wrap class="mt-2">
                      <Button
                        size="small"
                        type="primary"
                        @click="badgeCamInputRef?.click()"
                      >
                        拍照
                      </Button>
                      <Button
                        size="small"
                        @click="badgePickInputRef?.click()"
                      >
                        浏览
                      </Button>
                      <Button
                        v-if="badgeFile"
                        size="small"
                        danger
                        type="link"
                        @click="clearBadgePhoto"
                      >
                        清除
                      </Button>
                    </Space>
                    <input
                      ref="badgeCamInputRef"
                      type="file"
                      accept="image/*"
                      capture="user"
                      class="hidden"
                      @change="onBadgeFileInput"
                    />
                    <input
                      ref="badgePickInputRef"
                      type="file"
                      accept="image/jpeg,image/png,image/webp,.jpg,.jpeg,.png,.webp"
                      class="hidden"
                      @change="onBadgeFileInput"
                    />
                    <p class="text-muted-foreground mt-1 text-xs leading-relaxed">
                      保存入职后自动上传；支持 JPEG / PNG / WebP。
                    </p>
                  </div>
                </Tabs.TabPane>
                <Tabs.TabPane key="door" tab="门禁照片" :force-render="true">
                  <div class="onboarding-photo-panel">
                    <div
                      class="onboarding-photo-preview border-border bg-muted/40 flex min-h-[168px] items-center justify-center overflow-hidden rounded border"
                    >
                      <img
                        v-if="doorPreviewUrl"
                        :src="doorPreviewUrl"
                        alt="门禁预览"
                        class="max-h-56 max-w-full object-contain"
                      />
                      <span v-else class="text-muted-foreground text-sm">
                        暂无预览
                      </span>
                    </div>
                    <Space wrap class="mt-2">
                      <Button
                        size="small"
                        type="primary"
                        @click="doorCamInputRef?.click()"
                      >
                        拍照
                      </Button>
                      <Button
                        size="small"
                        @click="doorPickInputRef?.click()"
                      >
                        浏览
                      </Button>
                      <Button
                        v-if="doorFile"
                        size="small"
                        danger
                        type="link"
                        @click="clearDoorPhoto"
                      >
                        清除
                      </Button>
                    </Space>
                    <input
                      ref="doorCamInputRef"
                      type="file"
                      accept="image/*"
                      capture="environment"
                      class="hidden"
                      @change="onDoorFileInput"
                    />
                    <input
                      ref="doorPickInputRef"
                      type="file"
                      accept="image/jpeg,image/png,image/webp,.jpg,.jpeg,.png,.webp"
                      class="hidden"
                      @change="onDoorFileInput"
                    />
                    <p class="text-muted-foreground mt-1 text-xs leading-relaxed">
                      门禁照单独存储为工号_door.*，与工牌照区分。
                    </p>
                  </div>
                </Tabs.TabPane>
              </Tabs>
            </Card>
          </Col>
        </Row>
      </Form>
    </Spin>
  </Modal>
</template>

<style scoped>
.employee-onboarding-form :deep(.ant-collapse-header) {
  font-weight: 600;
}

/* 老系统风格：标签在左、浅绿底 */
.employee-onboarding-form-horizontal :deep(.ant-form-item-label) {
  padding-bottom: 0;
}

.employee-onboarding-form-horizontal :deep(.ant-form-item-label > label) {
  display: block;
  width: 100%;
  min-height: 32px;
  line-height: 32px;
  padding: 0 8px;
  margin-right: 0;
  background: #e3f4e3;
  border: 1px solid #b7deb9;
  border-radius: 2px;
  font-weight: 500;
}

.employee-onboarding-form-horizontal :deep(.ant-form-item-label > label::after) {
  display: none;
}

.employee-onboarding-form-horizontal :deep(.ant-form-item) {
  margin-bottom: 10px;
}

.employee-onboarding-form-horizontal :deep(.ant-form-item-control) {
  max-width: 100%;
}
</style>

<style>
.employee-onboarding-modal-wrap .ant-modal {
  top: 8px;
  max-width: calc(100vw - 16px) !important;
  padding-bottom: 0;
}

.employee-onboarding-modal-wrap .ant-modal-content {
  display: flex;
  flex-direction: column;
  max-height: calc(100vh - 16px);
}

.employee-onboarding-modal-wrap .ant-modal-body {
  flex: 1;
  min-height: 0;
  max-height: none;
  overflow-y: auto;
}
</style>
