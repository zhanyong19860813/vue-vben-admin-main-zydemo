import { Modal, message } from 'ant-design-vue';

import type { QueryTableActionContext } from '#/components/QueryTable/types';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

function askYear(defaultYear: number): number | null {
  const raw = window.prompt('请输入重算年份（例如 2026）', String(defaultYear));
  if (raw === null) return null;
  const y = Number(String(raw).trim());
  if (!Number.isInteger(y) || y < 2000 || y > 2100) return null;
  return y;
}

const actions: Record<string, (ctx: QueryTableActionContext) => any> = {
  async recalculate({ gridApi }) {
    const nowYear = new Date().getFullYear();
    const year = askYear(nowYear);
    if (!year) {
      message.warning('年份无效，已取消');
      return;
    }

    const selected = gridApi.grid?.getCheckboxRecords?.() ?? [];
    const empIds = selected
      .map((r: any) => String(r?.EMP_ID ?? '').trim())
      .filter((v: string) => !!v);

    Modal.confirm({
      title: '确认重算年假',
      content:
        empIds.length > 0
          ? `将重算 ${year} 年，范围：已勾选 ${empIds.length} 人。是否继续？`
          : `将重算 ${year} 年，范围：全部员工。是否继续？`,
      async onOk() {
        await requestClient.post(backendApi('Attendance/recalculate-vacation'), {
          year: String(year),
          empIds,
        });
        message.success('重算已完成');
        gridApi.reload();
      },
    });
  },
};

export default actions;

