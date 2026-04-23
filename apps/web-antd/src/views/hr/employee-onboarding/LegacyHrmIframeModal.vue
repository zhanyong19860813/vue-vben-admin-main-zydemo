<script lang="ts" setup>
import { Button, Modal } from 'ant-design-vue';

const open = defineModel<boolean>('open', { default: false });

defineProps<{
  /** 完整 URL（由 legacyHrmUrl 拼接） */
  src: string;
  title?: string;
}>();

function openInNewTab(url: string) {
  if (url) window.open(url, '_blank', 'noopener,noreferrer');
}
</script>

<template>
  <Modal
    v-model:open="open"
    :title="title || '老系统'"
    :footer="null"
    destroy-on-close
    :mask-closable="true"
    width="100%"
    wrap-class-name="legacy-hrm-iframe-modal-wrap"
  >
    <div class="legacy-hrm-iframe-toolbar">
      <Button size="small" type="link" @click="openInNewTab(src)">
        在新标签中打开
      </Button>
      <span class="legacy-hrm-iframe-hint text-muted-foreground text-xs">
        若内嵌空白，老系统可能设置了禁止 iframe（X-Frame-Options），请用此项或配置同源反向代理。
      </span>
    </div>
    <iframe
      v-if="open && src"
      :src="src"
      class="legacy-hrm-iframe"
      referrerpolicy="no-referrer-when-downgrade"
      title="legacy-hrm"
    />
  </Modal>
</template>

<style scoped>
.legacy-hrm-iframe-toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin-bottom: 8px;
}

.legacy-hrm-iframe-hint {
  flex: 1;
  min-width: 200px;
  line-height: 1.4;
}

.legacy-hrm-iframe {
  display: block;
  width: 100%;
  border: 0;
  background: #fff;
}
</style>

<style>
/* 全屏大弹窗（贴近老系统 mini.open + win.max） */
.legacy-hrm-iframe-modal-wrap .ant-modal {
  top: 8px;
  max-width: calc(100vw - 16px);
  padding-bottom: 0;
  margin: 0 auto;
}

.legacy-hrm-iframe-modal-wrap .ant-modal-content {
  display: flex;
  flex-direction: column;
  max-height: calc(100vh - 16px);
  padding: 16px;
}

.legacy-hrm-iframe-modal-wrap .ant-modal-header {
  flex-shrink: 0;
}

.legacy-hrm-iframe-modal-wrap .ant-modal-body {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.legacy-hrm-iframe-modal-wrap .ant-modal-body .legacy-hrm-iframe {
  flex: 1;
  min-height: 320px;
  height: auto;
}
</style>
