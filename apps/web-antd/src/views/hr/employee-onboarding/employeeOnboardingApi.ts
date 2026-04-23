import { BACKEND_API_BASE, backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { useAccessStore } from '@vben/stores';

/** 与 StoneApi HrEmployeeOnboardingController.CreateOnboardingRequest 对齐（camelCase JSON） */
export interface CreateOnboardingPayload {
  name: string;
  gender: string;
  brithDate?: string;
  nation?: string;
  nativePlace?: string;
  addr?: string;
  idCardType: string;
  idCardNo: string;
  idCardLicence?: string;
  idCardStartDate?: string;
  idCardEndDate?: string;
  nowAddr?: string;
  isPartyMember: number;
  isVeteran: number;
  ishandicapped: number;
  isMartyr: number;
  isSingleParent: number;
  isMilitary: number;
  isLowIncomeAid: number;
  mobileNo: string;
  phoneNo?: string;
  compId: string;
  deptId: string;
  dutyId: string;
  rankId?: string;
  type: string;
  gradeLevel: string;
  fristJoinDate: string;
  empNormalDate?: string;
  modifyName?: string;
  specialequipment?: string;
  specialequipmentDate?: string;
  specialequipmentPlace?: string;
  entryInformation?: string;
  recruitingChannel?: string;
  school?: string;
  specialty?: string;
  empEducation?: string;
  politicalStatus?: string;
  maritalStatus?: string;
  empTimeCard?: string;
  contact?: string;
  contactTel?: string;
  contactAddr?: string;
  reference?: string;
  remake?: string;
  contractType?: string;
  contractStartDate?: string;
  contractEndDate?: string;
  contractPeriod?: number;
  probationStartDate?: string;
  probationEndDate?: string;
  probationPeriod?: number;
  healthCertType?: string;
  healthLimitedPeriod?: string;
  healthStartTime?: string;
  healthEndTime?: string;
  networkRecruiting?: string;
  bcId?: string;
  depositBank?: string;
  bankBranch?: string;
  bankAttribution?: string;
  regionCode?: string;
  trainType?: string;
  trainServicePeriod?: string;
  trainServiceStart?: string;
  trainServiceEnd?: string;
  dispatchCompany?: string;
  dispatchSettlementMethod?: string;
  dispatchCompany2?: string;
  dispatchSettlementMethod2?: string;
}

export interface CreateOnboardingResult {
  id: string;
  code: string;
  message?: string;
}

export function createEmployeeOnboarding(payload: CreateOnboardingPayload) {
  return requestClient.post<CreateOnboardingResult>(
    backendApi('HrEmployeeOnboarding/create'),
    payload,
  );
}

/** 与 StoneApi UpdateOnboardingRequest 一致：create 字段 + 员工主键 id */
export type UpdateOnboardingPayload = CreateOnboardingPayload & { id: string };

/** 详情接口返回与 create 请求体同形，并带工号 code（只读展示） */
export type EmployeeOnboardingDetail = CreateOnboardingPayload & {
  code?: string;
};

export function getEmployeeOnboardingDetail(id: string) {
  return requestClient.get<EmployeeOnboardingDetail>(
    `${backendApi('HrEmployeeOnboarding/detail')}?id=${encodeURIComponent(id)}`,
  );
}

export function updateEmployeeOnboarding(payload: UpdateOnboardingPayload) {
  return requestClient.post<CreateOnboardingResult>(
    backendApi('HrEmployeeOnboarding/update'),
    payload,
  );
}

/** 保存入职成功后上传工牌/门禁照片（multipart，需 Bearer）。 */
export async function uploadEmployeeOnboardingPhotos(opts: {
  employeeCode: string;
  badgePhoto?: File | Blob;
  doorPhoto?: File | Blob;
}): Promise<void> {
  const accessStore = useAccessStore();
  const token = accessStore.accessToken;
  const fd = new FormData();
  fd.append('EmployeeCode', opts.employeeCode);
  if (opts.badgePhoto) fd.append('BadgePhoto', opts.badgePhoto);
  if (opts.doorPhoto) fd.append('DoorPhoto', opts.doorPhoto);

  const url = `${BACKEND_API_BASE}/api/HrEmployeeOnboarding/upload-photos`;
  const res = await fetch(url, {
    method: 'POST',
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: fd,
  });

  let body: { code?: number; message?: string } = {};
  try {
    body = (await res.json()) as { code?: number; message?: string };
  } catch {
    /* ignore */
  }

  if (!res.ok) {
    throw new Error(body.message || `上传失败（HTTP ${res.status}）`);
  }
  if (body.code !== 0) {
    throw new Error(body.message || '上传失败');
  }
}
