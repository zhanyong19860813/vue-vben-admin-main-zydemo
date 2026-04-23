/**
 * 排班作业 Excel 导入 → StoneApi AttJobSchedulingImport（对齐老系统 FI_ID=1042）
 */
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

/** 与老系统 Sys_ImportSetting.FI_ID 一致 */
export const JOB_SCHED_IMPORT_MARK = '1042';

export type JobImportPreviewError = {
  itemId?: string;
  itemName?: string;
  itemDetail?: string;
  reason?: string;
};

export type JobImportPreviewData = {
  rowCount: number;
  canCommit: boolean;
  errors: JobImportPreviewError[];
};

export async function previewJobSchedulingImport(
  file: File,
  operatorName: string,
  operatorEmpId: string,
  mark: string = JOB_SCHED_IMPORT_MARK,
): Promise<JobImportPreviewData> {
  const fd = new FormData();
  fd.append('file', file);
  fd.append('operatorName', operatorName);
  fd.append('operatorEmpId', operatorEmpId);
  fd.append('mark', mark);
  return requestClient.post(backendApi('AttJobSchedulingImport/preview'), fd, {
    timeout: 120_000,
  } as any);
}

export async function commitJobSchedulingImport(
  operatorName: string,
  mark: string = JOB_SCHED_IMPORT_MARK,
): Promise<void> {
  await requestClient.post(backendApi('AttJobSchedulingImport/commit'), {
    operatorName,
    mark,
  });
}
