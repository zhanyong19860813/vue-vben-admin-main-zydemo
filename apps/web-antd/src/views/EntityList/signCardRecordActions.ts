/**
 * 签卡作业列表：审核 / 取消审核（对齐老系统 t_sys_function_operation：审核、取消审核）
 * 数据表：att_lst_Cardrecord（AppState char：'1' 已审、'0' 未审；视图 v_att_lst_RegRecord 将状态显示为中文）
 * 列表 schema 需配置：actionModule: '/src/views/EntityList/signCardRecordActions.ts'
 */
import { Modal, message } from 'ant-design-vue';

import type { QueryTableActionContext } from '#/components/QueryTable/types';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { useUserStore } from '@vben/stores';

function padChar(s: string, len: number): string {
  const t = String(s ?? '').slice(0, len);
  return t.padEnd(len, ' ');
}

function getCheckboxRows(gridApi: any): Record<string, any>[] {
  return gridApi?.grid?.getCheckboxRecords?.() ?? [];
}

function primaryKeyOf(schema: QueryTableActionContext['schema']): string {
  return String(schema.primaryKey ?? 'FID').trim() || 'FID';
}

function saveTableName(schema: QueryTableActionContext['schema']): string {
  const raw = String(
    schema.saveEntityName ?? schema.deleteEntityName ?? 'att_lst_Cardrecord',
  ).trim();
  // 列表视图 v_att_lst_RegRecord 的基表是 att_lst_Cardrecord；误配 att_lst_RegRecord 时 DataSave 会报无主键 FID
  if (/^att_lst_RegRecord$/i.test(raw)) return 'att_lst_Cardrecord';
  return raw;
}

/** 列表行上状态列为视图计算后的中文 */
function appStateLabel(row: Record<string, any>): string {
  const v = row?.AppState;
  return v == null ? '' : String(v).trim();
}

function isApproved(row: Record<string, any>): boolean {
  return appStateLabel(row) === '已审核';
}

function canSubmitAudit(row: Record<string, any>): boolean {
  const s = appStateLabel(row);
  if (!s) return true;
  return s === '审批中' || s === '未审核';
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
  async auditSignCards({ gridApi, schema }: QueryTableActionContext) {
    const rows = getCheckboxRows(gridApi);
    if (!rows.length) {
      message.warning('请先勾选要审核的记录');
      return;
    }
    const pk = primaryKeyOf(schema);
    const toDo = rows.filter((r) => !isApproved(r) && canSubmitAudit(r));
    const skipped = rows.length - toDo.length;
    if (!toDo.length) {
      message.warning('所选记录均已审核或当前状态不可审核');
      return;
    }
    const table = saveTableName(schema);
    const approver = getApproverDisplayName();
    const now = new Date().toISOString();

    Modal.confirm({
      title: '审核',
      content: `将对 ${toDo.length} 条记录执行审核${skipped ? `（跳过 ${skipped} 条）` : ''}，是否继续？`,
      async onOk() {
        const data = toDo.map((r) => {
          const keyVal = r[pk] ?? r[String(pk).toLowerCase()] ?? r.FID;
          return {
            [pk]: keyVal,
            AppState: padChar('1', 50),
            Approver: padChar(approver, 200),
            approverTime: now,
          };
        });
        await postDatasaveMulti(table, pk, data);
        message.success('审核成功');
        gridApi.reload?.();
      },
    });
  },

  async cancelAuditSignCards({ gridApi, schema }: QueryTableActionContext) {
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
            AppState: padChar('0', 50),
            Approver: null,
            approverTime: null,
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
