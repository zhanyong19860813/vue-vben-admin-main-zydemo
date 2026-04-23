<script setup lang="ts">
/**
 * 表单设计器 + 流程设计器 同页对照（不使用 iframe，避免整站布局套娃与路由 404）
 */
import { defineAsyncComponent } from 'vue';

import { Page } from '@vben/common-ui';

const FormDesignerPage = defineAsyncComponent(() => import('#/views/demos/form-designer/index.vue'));
const WorkflowDesignerPage = defineAsyncComponent(() => import('#/views/demos/workflow-designer/index.vue'));
</script>

<template>
  <Page
    title="表单+流程一体化设计"
    content-class="min-h-0 overflow-y-auto"
    description="下方为两个设计器页面直接挂载在同一路由中。若首屏只看到表单设计器，请向下滚动；两块区域均可各自内部滚动。"
  >
    <div class="fwi-page">
      <section class="fwi-section">
        <div class="fwi-section-head">
          <span class="fwi-section-bar" />
          <span class="fwi-section-title">表单设计器</span>
          <span class="fwi-section-sub">/demos/form-designer</span>
        </div>
        <div class="fwi-embed">
          <FormDesignerPage />
        </div>
      </section>

      <section class="fwi-section">
        <div class="fwi-section-head">
          <span class="fwi-section-bar" />
          <span class="fwi-section-title">流程设计器</span>
          <span class="fwi-section-sub">/workflow/designer</span>
        </div>
        <div class="fwi-embed">
          <WorkflowDesignerPage />
        </div>
      </section>
    </div>
  </Page>
</template>

<style scoped>
.fwi-page {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 4px 0 16px;
}

.fwi-section {
  background: #fff;
  border: 1px solid #d7e0ea;
  border-radius: 4px;
  box-shadow: 0 1px 2px rgb(15 23 42 / 4%);
  /* 勿用 overflow:hidden，否则子页 min-h-full 撑高后会把下一区块顶出可视区且不易滚动 */
  overflow: visible;
  min-height: 0;
}

.fwi-section-head {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border-bottom: 1px solid #e3eaf2;
  background: #f6f9fc;
}

.fwi-section-bar {
  width: 3px;
  height: 14px;
  border-radius: 1px;
  background: #2b6cb0;
}

.fwi-section-title {
  font-size: 13px;
  font-weight: 600;
  color: #274c77;
}

.fwi-section-sub {
  font-size: 12px;
  color: #64748b;
}

.fwi-embed {
  max-height: min(65vh, 820px);
  min-height: 0;
  overflow: auto;
  background: #f8fafc;
  /* 内嵌的 Page 默认 min-h-full，会按「整页主区域」高度拉伸，必须压回由本容器滚动 */
  isolation: isolate;
}

.fwi-embed :deep(.relative.flex.min-h-full) {
  min-height: 0 !important;
}

.fwi-embed :deep(.relative.flex.min-h-full .h-full.p-4) {
  height: auto !important;
  min-height: 0 !important;
}

</style>
