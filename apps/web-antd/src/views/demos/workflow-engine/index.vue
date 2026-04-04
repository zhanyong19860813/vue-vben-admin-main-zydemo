<script setup lang="ts">
import { computed, ref } from 'vue';

import { Page } from '@vben/common-ui';
import { Button, Card, Steps, Table, Tabs, Tag, Timeline } from 'ant-design-vue';

type FlowStatus = 'done' | 'process' | 'wait';

interface FlowNode {
  key: string;
  title: string;
  owner: string;
  status: FlowStatus;
}

const flowNo = 'WF-20260401-0007';
const formTitle = '采购申请审批（演示）';
const applicant = '张三';
const department = '研发中心';
const submitTime = '2026-04-01 09:28:16';

const nodes = ref<FlowNode[]>([
  { key: 'start', title: '发起申请', owner: '张三', status: 'done' },
  { key: 'leader', title: '部门负责人审批', owner: '李经理', status: 'done' },
  { key: 'finance', title: '财务复核', owner: '王会计', status: 'process' },
  { key: 'gm', title: '总经理审批', owner: '赵总', status: 'wait' },
  { key: 'end', title: '流程结束', owner: '系统', status: 'wait' },
]);

const currentStep = computed(() => {
  const idx = nodes.value.findIndex((n) => n.status === 'process');
  return idx === -1 ? 0 : idx;
});

const detailRows = [
  { item: '采购类型', value: '办公设备' },
  { item: '预算金额', value: '12,500.00 CNY' },
  { item: '用途说明', value: '开发组新增工位设备采购' },
  { item: '优先级', value: '高' },
];

const timelineRows = [
  { time: '2026-04-01 09:28:16', action: '张三 发起流程', result: '已提交' },
  { time: '2026-04-01 09:35:02', action: '李经理 审批', result: '同意' },
  { time: '2026-04-01 10:12:40', action: '王会计 接收任务', result: '处理中' },
];

const stepItems = computed(() =>
  nodes.value.map((node) => {
    const statusMap: Record<FlowStatus, 'finish' | 'process' | 'wait'> = {
      done: 'finish',
      process: 'process',
      wait: 'wait',
    };
    return {
      title: node.title,
      description: `处理人：${node.owner}`,
      status: statusMap[node.status],
    };
  }),
);

const detailColumns = [
  { title: '字段', dataIndex: 'item', key: 'item', width: 140 },
  { title: '值', dataIndex: 'value', key: 'value' },
];
</script>

<template>
  <Page
    title="流程引擎（静态演示）"
    description="该页面仅做前端静态演示，不接流程引擎后端接口，主要用于先确认交互和视觉布局。"
  >
    <div class="flex flex-col gap-4 p-4">
      <Card size="small" title="流程信息与业务数据">
        <div class="grid grid-cols-2 gap-3 text-sm md:grid-cols-4">
          <div><span class="text-muted-foreground">流程编号：</span>{{ flowNo }}</div>
          <div><span class="text-muted-foreground">表单标题：</span>{{ formTitle }}</div>
          <div><span class="text-muted-foreground">发起人：</span>{{ applicant }}</div>
          <div><span class="text-muted-foreground">发起部门：</span>{{ department }}</div>
          <div class="md:col-span-2"><span class="text-muted-foreground">发起时间：</span>{{ submitTime }}</div>
          <div class="md:col-span-2">
            <span class="text-muted-foreground">当前状态：</span>
            <Tag color="processing">财务复核中</Tag>
          </div>
        </div>
        <div class="mt-4 border-t border-border pt-4">
          <div class="mb-2 text-sm font-medium">业务数据（示例）</div>
          <Table
            :columns="detailColumns"
            :data-source="detailRows"
            :pagination="false"
            row-key="item"
            size="small"
          />
        </div>
      </Card>

      <Card size="small">
        <Tabs>
          <Tabs.TabPane key="nodes" tab="流程节点">
            <Steps :current="currentStep" :items="stepItems" />
          </Tabs.TabPane>
          <Tabs.TabPane key="timeline" tab="审批记录">
            <Timeline>
              <Timeline.Item
                v-for="row in timelineRows"
                :key="`${row.time}-${row.action}`"
                :color="row.result === '处理中' ? 'blue' : 'green'"
              >
                <div class="flex flex-col gap-0.5">
                  <span class="text-xs text-muted-foreground">{{ row.time }}</span>
                  <span>{{ row.action }}</span>
                  <Tag
                    :color="row.result === '处理中' ? 'processing' : 'success'"
                    class="w-fit"
                  >
                    {{ row.result }}
                  </Tag>
                </div>
              </Timeline.Item>
            </Timeline>
          </Tabs.TabPane>
        </Tabs>
      </Card>

      <Card size="small" title="模拟审批操作（静态）">
        <div class="flex flex-wrap gap-2">
          <Button type="primary">同意</Button>
          <Button danger>驳回</Button>
          <Button>转交</Button>
          <Button>加签</Button>
          <Button>撤回</Button>
        </div>
        <p class="mt-3 text-muted-foreground text-xs">
          提示：当前按钮仅用于页面展示，尚未接入真实流程实例、任务流转和权限控制。
        </p>
      </Card>
    </div>
  </Page>
</template>
