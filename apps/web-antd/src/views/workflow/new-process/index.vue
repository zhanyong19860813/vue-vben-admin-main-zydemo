<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';

import { Page } from '@vben/common-ui';

import { Card, Empty, Spin, Typography, message } from 'ant-design-vue';

import { type WfEngineProcessRow, wfEngineGetTree } from '#/api/workflowEngine';

const router = useRouter();
const loading = ref(false);
const processes = ref<WfEngineProcessRow[]>([]);

/** 仅展示「是否有效」为 true 的流程（未返回 isValid 的旧数据视为有效） */
const validProcesses = computed(() =>
  (processes.value || []).filter((p) => p.isValid !== false),
);

async function loadList() {
  loading.value = true;
  try {
    const data = await wfEngineGetTree();
    processes.value = [...(data.processes ?? [])];
  } catch (e) {
    message.error(`加载失败：${(e as Error).message}`);
  } finally {
    loading.value = false;
  }
}

/**
 * 新开独立运行台（无侧栏），与「流程查看」全屏一致；填写表单后再点发起。
 */
function openRuntimeStartPage(row: WfEngineProcessRow) {
  openRuntimeStartByMode(row, false);
}

function openRuntimeStartByMode(row: WfEngineProcessRow, isMobile: boolean) {
  const query: Record<string, string> = { processDefId: row.id };
  const pc = String(row.processCode || '').trim();
  if (pc) query.processCode = pc;
  const pn = String(row.processName || '').trim();
  if (pn) query.processName = pn;
  if (isMobile) query.mode = 'mobile';
  const href = router.resolve({ path: '/workflow/runtime-embed', query }).href;
  window.open(
    href,
    '_blank',
    isMobile ? 'noopener,noreferrer,width=430,height=900' : 'noopener,noreferrer,width=1320,height=920',
  );
}

onMounted(() => {
  void loadList();
});
</script>

<template>
  <Page>
    <Card size="small" title="有效流程">
      <Spin :spinning="loading">
        <Empty v-if="!loading && validProcesses.length === 0" description="暂无有效流程" />
        <ul v-else class="wf-new-proc-list">
          <li v-for="p in validProcesses" :key="p.id">
            <Typography.Link @click.prevent="openRuntimeStartPage(p)">
              {{ p.processName || p.processCode }}
            </Typography.Link>
            <Typography.Link
              class="wf-new-proc-mobile"
              @click.prevent="openRuntimeStartByMode(p, true)"
            >
              【移动端】
            </Typography.Link>
            <span v-if="p.processCode" class="wf-new-proc-code">{{ p.processCode }}</span>
          </li>
        </ul>
      </Spin>
    </Card>
  </Page>
</template>

<style scoped>
.wf-new-proc-list {
  margin: 0;
  padding-left: 1.25rem;
  list-style: disc;
}

.wf-new-proc-list li {
  margin-bottom: 0.5rem;
}

.wf-new-proc-code {
  margin-left: 0.5rem;
  font-size: 12px;
  color: var(--text-color-secondary, #888);
}

.wf-new-proc-mobile {
  margin-left: 0.5rem;
}
</style>
