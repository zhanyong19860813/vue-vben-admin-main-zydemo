<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';

import { Page } from '@vben/common-ui';
import LogicFlow from '@logicflow/core';
import { Button, Card, Input, InputNumber, Select, Space, Tag, message } from 'ant-design-vue';
import { publishWorkflowDefinition, saveWorkflowDefinition } from '#/api/workflow';

import '@logicflow/core/es/style/index.css';

const processName = ref('请假审批流程（LogicFlow）');
const processCode = ref('WF_LEAVE_DEMO');
const processVersion = ref(1);
const storageKey = computed(() => `workflow-designer-layout:${processCode.value || 'default'}`);
const jsonText = ref('');
const canvasRef = ref<HTMLElement | null>(null);

const selectedNodeId = ref('');
const selectedEdgeId = ref('');
const selectedNodeType = ref('rect');
const selectedNodeName = ref('');
const selectedAssignee = ref('');
const selectedDesc = ref('');
const selectedEdgeCondition = ref('');

let lf: any = null;

const nodeTypeOptions = [
  { label: '开始节点', value: 'start' },
  { label: '审批节点', value: 'approve' },
  { label: '条件分支', value: 'condition' },
  { label: '抄送节点', value: 'cc' },
  { label: '结束节点', value: 'end' },
];

function mapToLfType(type: string) {
  if (type === 'condition') return 'diamond';
  if (type === 'start' || type === 'end') return 'circle';
  return 'rect';
}

function mapFromLfType(type: string) {
  if (type === 'diamond') return 'condition';
  if (type === 'circle') return 'approve';
  return 'approve';
}

function getDefaultGraphData() {
  return {
    nodes: [
      { id: 'N1', type: 'circle', x: 120, y: 220, text: '发起申请', properties: { bizType: 'start', assignee: '发起人' } },
      { id: 'N2', type: 'rect', x: 320, y: 220, text: '部门审批', properties: { bizType: 'approve', assignee: '部门负责人' } },
      { id: 'N3', type: 'diamond', x: 520, y: 220, text: '金额条件', properties: { bizType: 'condition', assignee: '系统' } },
      { id: 'N4', type: 'rect', x: 720, y: 220, text: '总经理审批', properties: { bizType: 'approve', assignee: '总经理' } },
      { id: 'N5', type: 'circle', x: 900, y: 220, text: '流程结束', properties: { bizType: 'end', assignee: '系统' } },
    ],
    edges: [
      { id: 'E1', type: 'polyline', sourceNodeId: 'N1', targetNodeId: 'N2' },
      { id: 'E2', type: 'polyline', sourceNodeId: 'N2', targetNodeId: 'N3' },
      { id: 'E3', type: 'polyline', sourceNodeId: 'N3', targetNodeId: 'N4' },
      { id: 'E4', type: 'polyline', sourceNodeId: 'N4', targetNodeId: 'N5' },
    ],
  };
}

function refreshSelectedNodePanel(nodeId: string) {
  if (!lf || !nodeId) return;
  const node = lf.getNodeModelById(nodeId);
  if (!node) return;
  selectedNodeId.value = node.id;
  selectedNodeType.value = node.properties?.bizType || mapFromLfType(node.type);
  selectedNodeName.value = node.text?.value || '';
  selectedAssignee.value = node.properties?.assignee || '';
  selectedDesc.value = node.properties?.desc || '';
  selectedEdgeId.value = '';
  selectedEdgeCondition.value = '';
}

function refreshSelectedEdgePanel(edgeId: string) {
  if (!lf || !edgeId) return;
  const edge = lf.getEdgeModelById(edgeId);
  if (!edge) return;
  selectedEdgeId.value = edge.id;
  selectedEdgeCondition.value =
    edge.properties?.condition || edge.text?.value || '';
  selectedNodeId.value = '';
}

function initLogicFlow(data?: any) {
  if (!canvasRef.value) return;
  lf = new LogicFlow({
    container: canvasRef.value,
    grid: true,
    keyboard: { enabled: true },
    stopScrollGraph: false,
    stopZoomGraph: false,
    edgeTextDraggable: true,
  });

  lf.render(data || getDefaultGraphData());
  lf.translateCenter();

  lf.on('node:click', ({ data: nodeData }: any) => {
    refreshSelectedNodePanel(nodeData.id);
  });
  lf.on('edge:click', ({ data: edgeData }: any) => {
    refreshSelectedEdgePanel(edgeData.id);
  });
}

function addNode(type: string) {
  if (!lf) return;
  const lfType = mapToLfType(type);
  const id = `N${Date.now()}`;
  lf.addNode({
    id,
    type: lfType,
    x: 220 + Math.floor(Math.random() * 400),
    y: 120 + Math.floor(Math.random() * 220),
    text: nodeTypeOptions.find((n) => n.value === type)?.label || '新节点',
    properties: {
      bizType: type,
      assignee: type === 'start' ? '发起人' : type === 'end' ? '系统' : '待设置',
      desc: '',
    },
  });
}

function removeSelectedNode() {
  if (!lf || !selectedNodeId.value) return;
  lf.deleteNode(selectedNodeId.value);
  selectedNodeId.value = '';
}

function applyNodeProperty() {
  if (!lf || !selectedNodeId.value) return;
  lf.updateText(selectedNodeId.value, selectedNodeName.value || '未命名节点');
  lf.setProperties(selectedNodeId.value, {
    bizType: selectedNodeType.value,
    assignee: selectedAssignee.value,
    desc: selectedDesc.value,
  });
  message.success('已更新节点属性');
}

function applyEdgeCondition() {
  if (!lf || !selectedEdgeId.value) return;
  lf.setProperties(selectedEdgeId.value, {
    condition: selectedEdgeCondition.value,
  });
  lf.updateText(selectedEdgeId.value, selectedEdgeCondition.value);
  message.success('已更新连线条件');
}

function exportCurrentJson() {
  if (!lf) return;
  const payload = {
    processName: processName.value,
    processCode: processCode.value,
    processVersion: processVersion.value,
    graphData: lf.getGraphData(),
    exportedAt: new Date().toISOString(),
  };
  jsonText.value = JSON.stringify(payload, null, 2);
  message.success('已导出 LogicFlow JSON');
}

function saveLayout() {
  if (!lf) return;
  try {
    const payload = {
      processName: processName.value,
      processCode: processCode.value,
      processVersion: processVersion.value,
      graphData: lf.getGraphData(),
      savedAt: new Date().toISOString(),
    };
    jsonText.value = JSON.stringify(payload, null, 2);
    localStorage.setItem(storageKey.value, jsonText.value);
    message.success('已保存布局到 localStorage');
  } catch (error) {
    message.error(`保存失败：${(error as Error).message}`);
  }
}

async function saveToServer() {
  if (!lf) return;
  const definitionJson = JSON.stringify(
    {
      processName: processName.value,
      processCode: processCode.value,
      processVersion: processVersion.value,
      graphData: lf.getGraphData(),
    },
    null,
    2,
  );
  const resp = await saveWorkflowDefinition({
    processCode: processCode.value,
    processName: processName.value,
    definitionJson,
  });
  processVersion.value = Number(resp?.version ?? processVersion.value);
  message.success('已保存到后端草稿版本');
}

function loadSavedLayout() {
  const raw = localStorage.getItem(storageKey.value);
  if (!raw) return;
  try {
    const parsed = JSON.parse(raw);
    processName.value = parsed.processName ?? processName.value;
    processVersion.value = Number(parsed.processVersion ?? processVersion.value);
    if (parsed?.graphData?.nodes) {
      lf?.render(parsed.graphData);
      lf?.translateCenter();
    }
    jsonText.value = JSON.stringify(parsed, null, 2);
    message.success('已加载已保存布局');
  } catch (error) {
    message.error(`加载失败：${(error as Error).message}`);
  }
}

function importJsonLayout() {
  if (!jsonText.value.trim()) {
    message.warning('请先粘贴 JSON');
    return;
  }
  try {
    const parsed = JSON.parse(jsonText.value);
    if (!parsed?.graphData?.nodes) throw new Error('JSON 中缺少 graphData.nodes');
    processName.value = parsed.processName ?? processName.value;
    processCode.value = parsed.processCode ?? processCode.value;
    processVersion.value = Number(parsed.processVersion ?? processVersion.value);
    lf?.render(parsed.graphData);
    lf?.translateCenter();
    localStorage.setItem(storageKey.value, JSON.stringify(parsed, null, 2));
    message.success('导入成功并已保存');
  } catch (error) {
    message.error(`导入失败：${(error as Error).message}`);
  }
}

async function publishFlow() {
  const resp = await publishWorkflowDefinition({
    processCode: processCode.value,
    version: processVersion.value,
  });
  processVersion.value = Number(resp?.version ?? processVersion.value);
  message.success('流程已发布');
}

onMounted(() => {
  initLogicFlow();
  loadSavedLayout();
});

onBeforeUnmount(() => {
  lf?.destroy();
  lf = null;
});
</script>

<template>
  <Page
    title="流程引擎设计器（LogicFlow）"
    description="基于 LogicFlow 的拖拽连线设计器演示，可保存/导入导出 JSON。"
  >
    <div class="flex flex-col gap-4 p-4">
      <Card size="small">
        <div class="flex flex-wrap items-end justify-between gap-3">
          <Space wrap>
            <div>
              <div class="mb-1 text-xs text-muted-foreground">流程名称</div>
              <Input v-model:value="processName" class="w-56" />
            </div>
            <div>
              <div class="mb-1 text-xs text-muted-foreground">流程编码</div>
              <Input v-model:value="processCode" class="w-48" />
            </div>
            <div>
              <div class="mb-1 text-xs text-muted-foreground">版本</div>
              <InputNumber v-model:value="processVersion" :min="1" :precision="0" />
            </div>
          </Space>
          <Space wrap>
            <Button @click="addNode('approve')">+ 审批节点</Button>
            <Button @click="addNode('condition')">+ 条件节点</Button>
            <Button @click="addNode('cc')">+ 抄送节点</Button>
            <Button @click="removeSelectedNode">删除选中</Button>
            <Button type="primary" @click="saveToServer">保存到后端</Button>
            <Button type="primary" ghost @click="publishFlow">发布流程</Button>
          </Space>
        </div>
      </Card>

      <div class="grid grid-cols-1 gap-4 xl:grid-cols-[1fr_320px]">
        <Card size="small" title="流程画布（LogicFlow 拖拽/连线）">
          <div ref="canvasRef" class="lf-canvas"></div>
        </Card>

        <Card size="small" title="节点属性">
          <template v-if="selectedNodeId">
            <div class="mb-2">
              <Tag color="blue">节点 ID: {{ selectedNodeId }}</Tag>
            </div>
            <div class="flex flex-col gap-3">
              <div>
                <div class="mb-1 text-xs text-muted-foreground">节点名称</div>
                <Input v-model:value="selectedNodeName" />
              </div>
              <div>
                <div class="mb-1 text-xs text-muted-foreground">节点业务类型</div>
                <Select v-model:value="selectedNodeType" :options="nodeTypeOptions" />
              </div>
              <div>
                <div class="mb-1 text-xs text-muted-foreground">处理人</div>
                <Input v-model:value="selectedAssignee" />
              </div>
              <div>
                <div class="mb-1 text-xs text-muted-foreground">说明</div>
                <Input v-model:value="selectedDesc" />
              </div>
              <Button type="primary" @click="applyNodeProperty">应用到节点</Button>
            </div>
          </template>
          <div v-else class="text-sm text-muted-foreground">请先在画布中点击节点</div>
        </Card>

        <Card size="small" title="连线条件">
          <template v-if="selectedEdgeId">
            <div class="mb-2">
              <Tag color="orange">连线 ID: {{ selectedEdgeId }}</Tag>
            </div>
            <div class="mb-1 text-xs text-muted-foreground">条件表达式</div>
            <Input
              v-model:value="selectedEdgeCondition"
              placeholder='示例: amount >= 1000 或 dept == "研发部"'
            />
            <p class="mt-2 text-xs text-muted-foreground">
              支持运算符：== != > >= < <= contains startsWith endsWith
            </p>
            <Button class="mt-2" type="primary" @click="applyEdgeCondition">
              应用到连线
            </Button>
          </template>
          <div v-else class="text-sm text-muted-foreground">
            请先在画布中点击一条连线
          </div>
        </Card>
      </div>

      <Card size="small" title="布局 JSON（导入/导出）">
        <div class="mb-2 text-xs text-muted-foreground">
          存储键：{{ storageKey }}
        </div>
        <Input.TextArea
          v-model:value="jsonText"
          :rows="12"
          placeholder="导出后可复制；也可粘贴后导入"
        />
        <div class="mt-3 flex flex-wrap gap-2">
          <Button @click="exportCurrentJson">导出 JSON</Button>
          <Button type="primary" @click="importJsonLayout">导入 JSON</Button>
          <Button @click="saveLayout">保存到 localStorage</Button>
          <Button @click="loadSavedLayout">从 localStorage 加载</Button>
        </div>
      </Card>
    </div>
  </Page>
</template>

<style scoped>
.lf-canvas {
  min-height: 560px;
  height: calc(100vh - 280px);
  border: 1px dashed rgb(203 213 225);
  border-radius: 8px;
  background: rgb(248 250 252);
}
</style>
