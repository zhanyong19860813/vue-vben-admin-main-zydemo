/**
 * 加班作业：审核 / 取消审核（老系统 t_sys_function_operation：审核、取消审核）
 * 列表视图 v_att_lst_OverTime；物理表 att_lst_OverTime；视图 ApproveStatus 为「已审核」/ 空
 * 库存 ApproveStatus：已审多为 '1'（与视图 CASE a.ApproveStatus = 1 一致）
 */
import { Modal, message } from 'ant-design-vue';

import type { QueryTableActionContext } from '#/components/QueryTable/types';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { useUserStore } from '@vben/stores';

function getCheckboxRows(gridApi: any): Record<string, any>[] {
  return gridApi?.grid?.getCheckboxRecords?.() ?? [];
}

function primaryKeyOf(schema: QueryTableActionContext['schema']): string {
  return String(schema.primaryKey ?? 'FID').trim() || 'FID';
}

function saveTableName(schema: QueryTableActionContext['schema']): string {
  return String(
    schema.saveEntityName ?? schema.deleteEntityName ?? 'att_lst_OverTime',
  ).trim();
}

function approveLabel(row: Record<string, any>): string {
  const v = row?.ApproveStatus;
  return v == null ? '' : String(v).trim();
}

function isApproved(row: Record<string, any>): boolean {
  return approveLabel(row) === '已审核';
}

function canSubmitAudit(row: Record<string, any>): boolean {
  return !isApproved(row);
}

function getApproverDisplayName(): string {
  const u = useUserStore().userInfo as Record<string, any> | null | undefined;
  return String(u?.realName ?? u?.username ?? u?.name ?? '').trim() || '系统';
}

async function postDatasaveMulti(
  tableName: string,
  pk: string,
  data: Record<string, any>[],
) {
  await requestClient.post(backendApi('DataSave/datasave-multi'), {
    tables: [
      {
        tableName,
        primaryKey: pk,
        data,
        deleteRows: [],
      },
    ],
  });
}

const actions = {
  async auditOvertimeRows({ gridApi, schema }: QueryTableActionContext) {
    const rows = getCheckboxRows(gridApi);
    if (!rows.length) {
      message.warning('请先勾选要审核的记录');
      return;
    }
    const pk = primaryKeyOf(schema);
    const toDo = rows.filter((r) => canSubmitAudit(r));
    const skipped = rows.length - toDo.length;
    if (!toDo.length) {
      message.warning('所选记录均已审核或不可审核');
      return;
    }
    const table = saveTableName(schema);
    const approver = getApproverDisplayName().slice(0, 50);
    const now = new Date().toISOString();

    Modal.confirm({
      title: '审核',
      content: `将对 ${toDo.length} 条记录执行审核${skipped ? `（跳过 ${skipped} 条）` : ''}，是否继续？`,
      async onOk() {
        const data = toDo.map((r) => {
          const keyVal = r[pk] ?? r[String(pk).toLowerCase()] ?? r.FID;
          return {
            [pk]: keyVal,
            ApproveStatus: '1',
            Approver: approver,
            ApproveTime: now,
          };
        });
        await postDatasaveMulti(table, pk, data);
        message.success('审核成功');
        gridApi.reload?.();
      },
    });
  },

  async cancelAuditOvertimeRows({ gridApi, schema }: QueryTableActionContext) {
    const rows = getCheckboxRows(gridApi);
    if (!rows.length) {
      message.warning('请先勾选要取消审核的记录');
      return;
    }
    const pk = primaryKeyOf(schema);
    const toDo = rows.filter((r) => isApproved(r));
    const skipped = rows.length - toDo.length;
    if (!toDo.length) {
      message.warning('所选记录中没有「已审核」状态，无法取消审核');
      return;
    }
    const table = saveTableName(schema);

    Modal.confirm({
      title: '取消审核',
      content: `将对 ${toDo.length} 条记录取消审核${skipped ? `（跳过 ${skipped} 条）` : ''}，是否继续？`,
      async onOk() {
        const data = toDo.map((r) => {
          const keyVal = r[pk] ?? r[String(pk).toLowerCase()] ?? r.FID;
          return {
            [pk]: keyVal,
            ApproveStatus: null,
            Approver: null,
            ApproveTime: null,
          };
        });
        await postDatasaveMulti(table, pk, data);
        message.success('已取消审核');
        gridApi.reload?.();
      },
    });
  },
};

export default actions;
