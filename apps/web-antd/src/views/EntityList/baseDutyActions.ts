import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import type { QueryTableActionContext } from '#/components/QueryTable/types';
import { Modal, message } from 'ant-design-vue';

function getFirstSelected(ctx: QueryTableActionContext): any | null {
  const rows = (ctx.gridApi.grid?.getCheckboxRecords?.() ?? []) as any[];
  return rows.length > 0 ? rows[0] : null;
}

export default {
  async add() {
    const res = await requestClient.post<{ items: Array<{ SJID?: string }> }>(backendApi('DynamicQueryBeta/queryforvben'), {
      TableName: 't_base_duty',
      Page: 1,
      PageSize: 5000,
      QueryField: 'SJID',
      SortBy: 'SJID',
      SortOrder: 'desc',
      Where: { Logic: 'AND', Conditions: [], Groups: [] },
    });
    const max = (res.items ?? []).reduce((m, r) => Math.max(m, Number(String(r.SJID ?? '0').trim()) || 0), 0);
    return {
      type: 'openFormFromDesigner' as const,
      formCode: 'hr_base_duty_add',
      title: '新增岗位',
      initialValues: {
        id: (typeof crypto !== 'undefined' && crypto.randomUUID) ? crypto.randomUUID() : undefined,
        SJID: String(max + 1),
        is_manager: '0',
        code: 'SJ',
      },
    };
  },

  async edit(ctx: QueryTableActionContext) {
    const row = getFirstSelected(ctx);
    if (!row) {
      message.warning('请选中一条记录');
      return;
    }
    return {
      type: 'openFormFromDesigner' as const,
      formCode: 'hr_base_duty_edit',
      title: '修改岗位',
      initialValues: row,
    };
  },

  async deleteWithGuard(ctx: QueryTableActionContext) {
    const row = getFirstSelected(ctx);
    if (!row) {
      message.warning('请选中一条记录');
      return;
    }
    const dutyId = String(row.id ?? '').trim();
    if (!dutyId) {
      message.warning('未识别到岗位主键');
      return;
    }

    const used = await requestClient.post<{ total?: number }>(backendApi('DynamicQueryBeta/queryforvben'), {
      TableName: 't_base_employee',
      Page: 1,
      PageSize: 1,
      QueryField: 'id',
      Where: { Logic: 'AND', Conditions: [{ Field: 'duty_id', Operator: 'eq', Value: dutyId }], Groups: [] },
    });
    if ((used.total ?? 0) > 0) {
      message.warning('当前岗位下有在职人员,不能进行删除操作!');
      return;
    }

    Modal.confirm({
      title: '删除',
      content: '确定删除选中记录？',
      async onOk() {
        await requestClient.post(backendApi('DataBatchDelete/BatchDelete'), [
          {
            tableName: 't_base_duty',
            key: 'id',
            keys: [dutyId],
          },
        ]);
        message.success('删除成功');
        ctx.gridApi.reload();
      },
    });
  },
};

