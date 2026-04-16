<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue';

import LogicFlow from '@logicflow/core';
import '@logicflow/core/es/style/index.css';

import { inferBizTypeFromGraphNode } from '#/views/workflow/wfFormPreviewUtils';

const props = withDefaults(
  defineProps<{
    definitionJson: string;
    currentNodeId?: string;
    timelineRows?: Array<Record<string, any>>;
    allTimelineRows?: Array<Record<string, any>>;
    height?: number;
  }>(),
  { currentNodeId: '', timelineRows: () => [], allTimelineRows: () => [], height: 260 },
);

const canvasRef = ref<HTMLElement | null>(null);
let lf: LogicFlow | null = null;

function nodeStyleFor(bizType: string, lfType: string): Record<string, number | string> {
  if (lfType === 'circle') {
    if (bizType === 'end') return { fill: '#fff1f2', stroke: '#f43f5e', strokeWidth: 2 };
    return { fill: '#ecfdf5', stroke: '#22c55e', strokeWidth: 2 };
  }
  if (lfType === 'diamond') return { fill: '#fff7ed', stroke: '#f97316', strokeWidth: 2 };
  if (bizType === 'cc') return { fill: '#f5f3ff', stroke: '#8b5cf6', strokeWidth: 1.5, radius: 10 };
  return { fill: '#eff6ff', stroke: '#3b82f6', strokeWidth: 1.5, radius: 10 };
}

function parseGraphData(rawJson: string): { edges: any[]; nodes: any[] } {
  if (!rawJson.trim()) return { nodes: [], edges: [] };
  try {
    const parsed = JSON.parse(rawJson) as { graphData?: { nodes?: any[]; edges?: any[] } };
    const graphData = parsed?.graphData ?? {};
    return {
      nodes: Array.isArray(graphData.nodes) ? graphData.nodes : [],
      edges: Array.isArray(graphData.edges) ? graphData.edges : [],
    };
  } catch {
    return { nodes: [], edges: [] };
  }
}

function decorateNodes(nodes: any[], currentNodeId: string) {
  const cur = String(currentNodeId || '').trim();
  return nodes.map((n) => {
    const biz = String(n?.properties?.bizType || '').trim() || inferBizTypeFromGraphNode(n);
    const base = nodeStyleFor(biz, String(n?.type || 'rect'));
    const isCurrent = cur && String(n?.id || '').trim() === cur;
    const style = isCurrent
      ? { ...base, stroke: '#2563eb', strokeWidth: 3, fill: '#dbeafe' }
      : base;
    return {
      ...n,
      properties: {
        ...(n?.properties || {}),
        bizType: biz,
        style: { ...style, ...(n?.properties?.style || {}) },
      },
    };
  });
}

function buildTraversedEdgePairs(currentNodeId: string, rows: Array<Record<string, any>>) {
  const seq: string[] = [];
  for (const row of rows || []) {
    const action = String(row?.action_type || '').trim().toLowerCase();
    if (!action) continue;
    if (!['submit', 'approve', 'agree', 'reject', 'withdraw'].includes(action)) continue;
    const nodeId = String(row?.node_id || '').trim();
    if (!nodeId) continue;
    if (!seq.length || seq[seq.length - 1] !== nodeId) seq.push(nodeId);
  }
  const cur = String(currentNodeId || '').trim();
  if (cur && (!seq.length || seq[seq.length - 1] !== cur)) {
    seq.push(cur);
  }
  const pairs = new Set<string>();
  for (let i = 0; i < seq.length - 1; i++) {
    const s = seq[i];
    const t = seq[i + 1];
    if (s && t) pairs.add(`${s}=>${t}`);
  }
  return pairs;
}

/** 历史上由 reject 动作触发的跳转边（用于保留驳回路径高亮） */
function buildHistoryRejectEdgePairs(rows: Array<Record<string, any>>) {
  const events: Array<{ action: string; nodeId: string }> = [];
  for (const row of rows || []) {
    const action = String(row?.action_type || '').trim().toLowerCase();
    if (!action) continue;
    if (!['submit', 'approve', 'agree', 'reject', 'withdraw'].includes(action)) continue;
    const nodeId = String(row?.node_id || '').trim();
    if (!nodeId) continue;
    events.push({ action, nodeId });
  }
  const pairs = new Set<string>();
  for (let i = 0; i < events.length - 1; i++) {
    const cur = events[i];
    const next = events[i + 1];
    if (!cur || !next) continue;
    if (cur.action !== 'reject') continue;
    if (cur.nodeId && next.nodeId && cur.nodeId !== next.nodeId) {
      pairs.add(`${cur.nodeId}=>${next.nodeId}`);
    }
  }
  return pairs;
}

function decorateEdges(
  edges: any[],
  traversedPairs: Set<string>,
): any[] {
  return edges.map((e) => {
    const s = String(e?.sourceNodeId || '').trim();
    const t = String(e?.targetNodeId || '').trim();
    const used = traversedPairs.has(`${s}=>${t}`);
    const edgeStyle = used
      ? { stroke: '#ef4444', strokeWidth: 2.8 }
      : { stroke: '#111827', strokeWidth: 1.8 };
    return {
      ...e,
      properties: {
        ...(e?.properties || {}),
        style: { ...(e?.properties?.style || {}), ...edgeStyle },
      },
    };
  });
}

function renderGraph() {
  if (!lf) return;
  const data = parseGraphData(props.definitionJson);
  if (!data.nodes.length) {
    lf.render({ nodes: [], edges: [] });
    return;
  }
  const nodes = decorateNodes(data.nodes, props.currentNodeId || '');
  const traversedPairs = buildTraversedEdgePairs(
    props.currentNodeId || '',
    props.timelineRows || [],
  );
  const historyRejectPairs = buildHistoryRejectEdgePairs(props.allTimelineRows || []);
  for (const p of historyRejectPairs) traversedPairs.add(p);
  const edges = decorateEdges(data.edges, traversedPairs);
  lf.render({ nodes, edges });
  lf.fitView?.(40, 32);
}

onMounted(async () => {
  await nextTick();
  if (!canvasRef.value) return;
  lf = new LogicFlow({
    container: canvasRef.value,
    keyboard: { enabled: false },
    stopScrollGraph: false,
    stopZoomGraph: false,
    adjustEdge: false,
    allowResize: false,
    allowRotate: false,
    isSilentMode: true,
    grid: { visible: false },
    style: {
      edgeText: {
        fontSize: 12,
        color: '#334155',
      },
    },
  });
  renderGraph();
});

watch(
  () => [props.definitionJson, props.currentNodeId, props.timelineRows, props.allTimelineRows] as const,
  async () => {
    await nextTick();
    renderGraph();
  },
  { deep: true },
);

onBeforeUnmount(() => {
  lf?.destroy();
  lf = null;
});
</script>

<template>
  <div ref="canvasRef" class="w-full rounded border border-border" :style="{ height: `${height}px` }" />
</template>
