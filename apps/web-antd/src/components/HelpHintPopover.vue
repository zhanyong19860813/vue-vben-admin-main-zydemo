<script setup lang="ts">
/**
 * 通用「问号」帮助：默认点击展开 Popover（适合多行说明、移动端）。
 * 需要悬停即显时传入 trigger="hover"。
 */
import { IconifyIcon } from '@vben/icons';
import { Popover } from 'ant-design-vue';

withDefaults(
  defineProps<{
    /** Popover 标题，可省略 */
    title?: string;
    trigger?: 'click' | 'hover';
    placement?:
      | 'top'
      | 'left'
      | 'right'
      | 'bottom'
      | 'topLeft'
      | 'topRight'
      | 'bottomLeft'
      | 'bottomRight'
      | 'leftTop'
      | 'leftBottom'
      | 'rightTop'
      | 'rightBottom';
    /** 无障碍名称 */
    ariaLabel?: string;
  }>(),
  {
    title: undefined,
    trigger: 'click',
    placement: 'bottomLeft',
    ariaLabel: '查看说明',
  },
);
</script>

<template>
  <Popover
    :trigger="trigger"
    :placement="placement"
    overlay-class-name="help-hint-popover-overlay"
  >
    <template v-if="title" #title>{{ title }}</template>
    <template #content>
      <div class="help-hint-popover-body max-w-[min(92vw,360px)] text-xs leading-relaxed">
        <slot />
      </div>
    </template>
    <button
      type="button"
      class="text-muted-foreground hover:text-foreground inline-flex shrink-0 rounded p-0.5 align-middle transition-colors"
      :aria-label="ariaLabel"
      @click.stop
    >
      <IconifyIcon icon="mdi:help-circle-outline" class="text-base" />
    </button>
  </Popover>
</template>

<style scoped>
button:focus-visible {
  outline: 2px solid hsl(var(--ring));
  outline-offset: 1px;
}
</style>
