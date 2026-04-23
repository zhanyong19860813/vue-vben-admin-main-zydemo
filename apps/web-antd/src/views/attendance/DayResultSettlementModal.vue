<script setup lang="ts">
/**
 * 考勤日结：与老系统「执行日结」一致，调用 dbo.att_pro_DayResult
 * 参数：工号串/部门、按人/按部门、起止日期、操作人
 */
import { computed, ref } from 'vue';
import {
  Button,
  DatePicker,
  Form,
  Modal,
  Space,
  Table,
  Typography,
  message,
} from 'ant-design-vue';
import type { Key } from 'ant-design-vue/es/_util/type';
import dayjs, { type Dayjs } from 'dayjs';

import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import {
  SelectDepartmentModal,
  SelectPersonnelModal,
} from '#/components/org-picker';
import type { OrgDeptItem, OrgPersonnelItem } from '#/components/org-picker';
import { useUserStore } from '@vben/stores';

const emit = defineEmits<{
  success: [];
  cancel: [];
}>();

type Row = OrgPersonnelItem & { key: string };

const userStore = useUserStore();

const dateRange = ref<[Dayjs, Dayjs]>([
  dayjs().startOf('month'),
  dayjs().endOf('month'),
]);

const selectedDepts = ref<OrgDeptItem[]>([]);
const deptModalOpen = ref(false);

const personnel = ref<Row[]>([]);
const personModalOpen = ref(false);
const selectedRowKeys = ref<Key[]>([]);

const deptLabel = computed(() =>
  selectedDepts.value.length
    ? selectedDepts.value.map((d) => d.name).join('、')
    : '',
);

/** 固定列宽 + scroll.x，避免长部门路径把弹窗撑宽；ellipsis 需配合 width */
const columns = [
  { title: '工号', dataIndex: 'empId', key: 'empId', width: 96, fixed: 'left' as const },
  { title: '姓名', dataIndex: 'name', key: 'name', width: 88 },
  {
    title: '部门',
    dataIndex: 'deptName',
    key: 'deptName',
    width: 240,
    ellipsis: true,
  },
  { title: '岗位', dataIndex: 'dutyName', key: 'dutyName', width: 100, ellipsis: true },
];

/** 表体区域最大高度，避免人多时把底部按钮顶出视口 */
const personnelTableScroll = { x: 700, y: 240 } as const;

function rowsToMap(list: Row[]): Map<string, Row> {
  const m = new Map<string, Row>();
  for (const r of list) {
    const k = String(r.empId || r.id || '').trim();
    if (k) m.set(k, r);
  }
  return m;
}

function onPersonnelConfirm(items: OrgPersonnelItem[]) {
  const m = rowsToMap(personnel.value);
  for (const it of items) {
    const empId = String(it.empId || '').trim();
    if (!empId) continue;
    m.set(empId, {
      ...it,
      key: empId,
    });
  }
  personnel.value = [...m.values()];
  personModalOpen.value = false;
}

function onDeptConfirm(items: OrgDeptItem[]) {
  if (items.length > 1) {
    message.info('按部门日结仅使用所选的第一个部门');
  }
  selectedDepts.value = items.length ? [items[0]!] : [];
  deptModalOpen.value = false;
}

function clearDept() {
  selectedDepts.value = [];
}

function removeSelectedRows() {
  const drop = new Set(selectedRowKeys.value.map(String));
  personnel.value = personnel.value.filter((r) => !drop.has(String(r.key)));
  selectedRowKeys.value = [];
}

function resolveOperator(): string {
  const u = userStore.userInfo as Record<string, any> | null | undefined;
  if (!u) return '系统';
  const v =
    u.employeeId ??
    u.employee_id ??
    u.empId ??
    u.emp_id ??
    u.code ??
    u.username ??
    u.userName ??
    u.realName ??
    u.name;
  const s = v == null ? '' : String(v).trim();
  return s || '系统';
}

const submitting = ref(false);

async function onSubmit() {
  const dr = dateRange.value;
  if (!dr?.[0] || !dr[1]) {
    message.warning('请选择日结开始、结束日期');
    return;
  }
  const start = dr[0].format('YYYY-MM-DD');
  const end = dr[1].format('YYYY-MM-DD');
  if (dayjs(end).isBefore(dayjs(start), 'day')) {
    message.warning('结束日期不能早于开始日期');
    return;
  }

  const emps = personnel.value.filter((r) => String(r.empId || '').trim());
  let emp_list: string;
  let DayResultType: string;

  if (emps.length > 0) {
    DayResultType = '0';
    emp_list = emps.map((r) => String(r.empId).trim()).join(',');
    if (emp_list.length > 4000) {
      message.error('所选人员过多，请缩小范围（工号串长度超过 4000）');
      return;
    }
  } else if (selectedDepts.value[0]?.id) {
    DayResultType = '1';
    emp_list = String(selectedDepts.value[0].id).trim();
  } else {
    message.warning('请「选择部门」或「批量人员选择」添加至少一名人员');
    return;
  }

  const op = resolveOperator();

  Modal.confirm({
    title: '确认执行日结',
    content:
      emps.length > 0
        ? `将对 ${emps.length} 名指定人员在 ${start} ~ ${end} 执行日结，耗时可能较长，是否继续？`
        : `将按部门「${selectedDepts.value[0]?.name ?? ''}」在 ${start} ~ ${end} 执行日结（含子部门），耗时可能较长，是否继续？`,
    okText: '执行',
    async onOk() {
      submitting.value = true;
      try {
        await requestClient.post(backendApi('Procedure/execute'), {
          procedureName: 'dbo.att_pro_DayResult',
          parameters: {
            emp_list,
            DayResultType,
            attStartDate: `${start}T00:00:00`,
            attEndDate: `${end}T23:59:59`,
            op,
          },
          returnData: false,
          timeoutSeconds: 600,
        });
        message.success('日结执行成功');
        emit('success');
      } catch (e: any) {
        message.error(e?.message || e?.data?.message || '日结执行失败');
        throw e;
      } finally {
        submitting.value = false;
      }
    },
  });
}

function onCancel() {
  emit('cancel');
}
</script>

<template>
  <div class="day-result-settlement">
    <div class="settlement-top">
    <Typography.Paragraph type="secondary" class="!mb-3">
      按工号日结：下方表格中有人员时优先；否则按所选部门（含子部门）日结。月结果已审核人员会被存储过程排除。
    </Typography.Paragraph>

    <Form layout="vertical" class="compact-form">
      <Form.Item label="日结日期范围" required>
        <DatePicker.RangePicker
          v-model:value="dateRange"
          class="w-full max-w-md"
          format="YYYY-MM-DD"
        />
      </Form.Item>

      <Form.Item label="部门选择（按部门日结时使用）">
        <Space wrap>
          <Typography.Text v-if="deptLabel" class="mr-2">{{ deptLabel }}</Typography.Text>
          <Typography.Text v-else type="secondary">未选择</Typography.Text>
          <Button type="primary" ghost size="small" @click="deptModalOpen = true">选择部门</Button>
          <Button v-if="selectedDepts.length" size="small" @click="clearDept">清除</Button>
        </Space>
      </Form.Item>
    </Form>

    <div class="personnel-toolbar mb-2 flex flex-wrap items-center justify-between gap-2">
      <Typography.Text strong>人员列表</Typography.Text>
      <Space wrap>
        <Button type="primary" size="small" @click="personModalOpen = true">批量人员选择</Button>
        <Button danger size="small" :disabled="!selectedRowKeys.length" @click="removeSelectedRows">
          删除
        </Button>
      </Space>
    </div>

    <div class="personnel-table-wrap">
      <Table
        size="small"
        table-layout="fixed"
        :columns="columns"
        :data-source="personnel"
        :pagination="false"
        :scroll="personnelTableScroll"
        row-key="key"
        :row-selection="{
          selectedRowKeys,
          onChange: (keys: Key[]) => (selectedRowKeys = keys),
        }"
        bordered
      />
    </div>
    </div>

    <div class="modal-footer-actions">
      <Space :size="12">
        <Button @click="onCancel">取消</Button>
        <Button type="primary" :loading="submitting" @click="onSubmit">执行日结</Button>
      </Space>
    </div>

    <SelectDepartmentModal
      v-model:open="deptModalOpen"
      title="选择部门（按部门日结）"
      :default-checked-ids="selectedDepts.map((d) => d.id)"
      @confirm="onDeptConfirm"
    />

    <SelectPersonnelModal
      v-model:open="personModalOpen"
      title="批量人员选择"
      :default-selected="personnel"
      @confirm="onPersonnelConfirm"
    />
  </div>
</template>

<style scoped>
/* 限制整块内容高度，底部按钮始终留在弹窗内；表格单独滚动 */
.day-result-settlement {
  display: flex;
  flex-direction: column;
  max-height: min(72vh, 620px);
  max-width: 100%;
  min-width: 0;
  padding: 4px 0 0;
  box-sizing: border-box;
}

.settlement-top {
  flex: 1 1 auto;
  min-height: 0;
  min-width: 0;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.compact-form :deep(.ant-form-item) {
  margin-bottom: 12px;
}

.personnel-table-wrap {
  flex: 1 1 auto;
  min-height: 0;
  min-width: 0;
  max-height: min(40vh, 300px);
  width: 100%;
  /* 仅由 Table scroll 滚动，避免出现双滚动条 */
  overflow: hidden;
}

.personnel-table-wrap :deep(.ant-table-wrapper) {
  max-width: 100%;
}

.modal-footer-actions {
  flex-shrink: 0;
  display: flex;
  justify-content: center;
  margin-top: 16px;
  padding-top: 16px;
  border-top: 1px solid rgba(0, 0, 0, 0.06);
}
</style>
