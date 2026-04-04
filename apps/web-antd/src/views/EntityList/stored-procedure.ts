import { Modal, message } from 'ant-design-vue';

import type { QueryTableActionContext } from '#/components/QueryTable/types';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

type ProcButtonConfig = {
  label?: string;
  procedureName?: string;
  procedure?: string;
  requiresSelection?: boolean;
  selectionField?: string;
  selectionParam?: string;
  askYear?: boolean;
  yearParam?: string;
  yearDefault?: number;
  staticParams?: Record<string, any>;
  confirm?: string;
  reloadAfter?: boolean;
};

function parseYear(defaultYear: number): string | null {
  const raw = window.prompt('请输入年份（例如 2026）', String(defaultYear));
  if (raw === null) return null;
  const y = Number(String(raw).trim());
  if (!Number.isInteger(y) || y < 2000 || y > 2100) return null;
  return String(y);
}

const actions: Record<string, (ctx: QueryTableActionContext) => any> = {
  async executeProcedure({ gridApi, btn }: any) {
    const cfg = (btn ?? {}) as ProcButtonConfig;
    const procedureName = (cfg.procedureName || cfg.procedure || '').trim();
    if (!procedureName) {
      message.warning('未配置 procedureName');
      return;
    }

    const params: Record<string, any> = { ...(cfg.staticParams ?? {}) };

    if (cfg.askYear) {
      const y = parseYear(cfg.yearDefault || new Date().getFullYear());
      if (!y) {
        message.warning('年份无效，已取消');
        return;
      }
      params[cfg.yearParam || 'year'] = y;
    }

    if (cfg.requiresSelection) {
      const rows = gridApi.grid?.getCheckboxRecords?.() ?? [];
      if (!rows.length) {
        message.warning('请先勾选一条数据');
        return;
      }
      const field = cfg.selectionField || 'EMP_ID';
      const p = cfg.selectionParam || 'emp_id';
      const first = rows[0] as Record<string, any>;
      const val = first[field];
      params[p] = val == null ? '' : String(val).trim();
    } else if (cfg.selectionParam && params[cfg.selectionParam] === undefined) {
      // 显式配置 selectionParam 且不要求勾选时：传空串（如 att_pro_Vacation 全员重算）
      params[cfg.selectionParam] = '';
    }

    const content = cfg.confirm || `确认执行【${cfg.label || '操作'}】？`;
    Modal.confirm({
      title: cfg.label || '执行存储过程',
      content,
      async onOk() {
        await requestClient.post(backendApi('Procedure/execute'), {
          procedureName,
          parameters: params,
          returnData: false,
        });
        message.success('执行成功');
        if (cfg.reloadAfter !== false) gridApi.reload();
      },
    });
  },
};

export default actions;

