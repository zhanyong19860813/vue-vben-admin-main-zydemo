<script setup lang="ts">
defineProps<{
  /** true：全页居中 + 手机外框；false：普通宽屏内边距 */
  frame: boolean;
}>();
</script>

<template>
  <!-- 移动端：整页舞台 + 机身 + 屏幕内滚动 -->
  <div v-if="frame" class="wf-pp-stage">
    <div class="wf-pp-phone-spotlight" aria-hidden="true" />
    <div class="wf-pp-phone-rim" aria-label="手机预览框">
      <div class="wf-pp-phone">
        <i class="wf-pp-btn wf-pp-btn--mute" aria-hidden="true" />
        <i class="wf-pp-btn wf-pp-btn--vol-up" aria-hidden="true" />
        <i class="wf-pp-btn wf-pp-btn--vol-down" aria-hidden="true" />
        <i class="wf-pp-btn wf-pp-btn--power" aria-hidden="true" />
        <div class="wf-pp-phone-island" aria-hidden="true" />
        <div class="wf-pp-phone-screen">
          <div class="wf-pp-phone-scroll">
            <slot />
          </div>
        </div>
        <div class="wf-pp-phone-home" aria-hidden="true" />
      </div>
    </div>
  </div>
  <!-- 桌面端 -->
  <div v-else class="flex flex-col gap-4 p-4">
    <slot />
  </div>
</template>

<style scoped>
.wf-pp-stage {
  position: relative;
  box-sizing: border-box;
  display: flex;
  flex: 1;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: calc(100dvh - 7.5rem);
  padding: 1.25rem 1rem 1.5rem;
  overflow-x: hidden;
  /* 浅灰蓝工作台背景，避免纯黑 */
  background:
    radial-gradient(ellipse 72% 48% at 50% 38%, rgb(255 255 255 / 0.9) 0%, transparent 58%),
    radial-gradient(ellipse 90% 70% at 50% 100%, rgb(180 200 230 / 0.35), transparent 52%),
    linear-gradient(168deg, #e4e9f2 0%, #d6dde8 38%, #c8d2e0 72%, #bcc7d6 100%);
}

/* 机身背后柔光（浅色底上用淡蓝晕） */
.wf-pp-phone-spotlight {
  pointer-events: none;
  position: absolute;
  top: 50%;
  left: 50%;
  width: min(440px, 96vw);
  height: min(92dvh, 920px);
  transform: translate(-50%, -50%);
  border-radius: 50%;
  background: radial-gradient(
    closest-side,
    rgb(120 160 220 / 0.18) 0%,
    rgb(160 185 220 / 0.1) 45%,
    transparent 72%
  );
  filter: blur(4px);
}

.wf-pp-phone-rim {
  position: relative;
  z-index: 1;
  padding: 3px;
  border-radius: 2.85rem;
  background: linear-gradient(
    165deg,
    rgb(255 255 255 / 0.22) 0%,
    rgb(120 125 145 / 0.12) 22%,
    rgb(40 42 52 / 0.85) 55%,
    rgb(15 16 22 / 0.95) 100%
  );
  box-shadow:
    0 0 0 1px rgb(0 0 0 / 0.45),
    0 2px 4px rgb(255 255 255 / 0.06) inset,
    0 40px 80px rgb(0 0 0 / 0.65),
    0 12px 28px rgb(0 0 0 / 0.35);
}

.wf-pp-phone {
  position: relative;
  display: flex;
  width: min(390px, calc(100vw - 2rem));
  max-width: 100%;
  flex-direction: column;
  align-items: stretch;
  padding: 13px 12px 11px;
  border-radius: 2.65rem;
  background:
    linear-gradient(115deg, rgb(255 255 255 / 0.14) 0%, transparent 42%),
    linear-gradient(210deg, #4a4d5c 0%, #32343f 18%, #22232c 45%, #15161d 78%, #0e0f14 100%);
  box-shadow:
    inset 0 1px 0 rgb(255 255 255 / 0.18),
    inset 0 -2px 6px rgb(0 0 0 / 0.35),
    0 0 0 1px rgb(0 0 0 / 0.5);
}

/* 左侧音量键、右侧电源键（装饰） */
.wf-pp-btn {
  display: block;
  position: absolute;
  z-index: 2;
  border-radius: 2px;
  background: linear-gradient(90deg, #2b2c34, #16171c);
  box-shadow:
    1px 0 0 rgb(255 255 255 / 0.06),
    -1px 0 2px rgb(0 0 0 / 0.4) inset;
}

.wf-pp-btn--mute {
  top: 18%;
  left: -3px;
  width: 3px;
  height: 22px;
}

.wf-pp-btn--vol-up {
  top: 26%;
  left: -3px;
  width: 3px;
  height: 40px;
}

.wf-pp-btn--vol-down {
  top: 36%;
  left: -3px;
  width: 3px;
  height: 40px;
}

.wf-pp-btn--power {
  top: 24%;
  right: -3px;
  width: 3px;
  height: 56px;
}

/* 灵动岛 */
.wf-pp-phone-island {
  flex-shrink: 0;
  height: 30px;
  margin: 0 auto 10px;
  width: 118px;
  border-radius: 999px;
  background: linear-gradient(180deg, #0a0a0d 0%, #000 100%);
  box-shadow:
    0 0 0 1px rgb(255 255 255 / 0.08),
    inset 0 2px 6px rgb(0 0 0 / 0.85),
    0 4px 12px rgb(0 0 0 / 0.4);
}

.wf-pp-phone-screen {
  display: flex;
  min-height: 0;
  flex: 1;
  flex-direction: column;
  overflow: hidden;
  border-radius: 1.75rem;
  background: hsl(var(--background));
  box-shadow:
    inset 0 0 0 1px rgb(255 255 255 / 0.12),
    inset 0 2px 12px rgb(0 0 0 / 0.12),
    0 0 0 1px rgb(0 0 0 / 0.25);
}

.wf-pp-phone-scroll {
  flex: 1;
  min-height: 0;
  max-height: min(76dvh, 760px);
  overflow-x: hidden;
  overflow-y: auto;
  padding: 10px 10px 12px;
  -webkit-overflow-scrolling: touch;
}

.wf-pp-phone-scroll :deep(.ant-card) {
  border-radius: 10px;
}

.wf-pp-phone-home {
  flex-shrink: 0;
  height: 5px;
  margin: 12px auto 2px;
  width: 132px;
  border-radius: 999px;
  background: linear-gradient(90deg, transparent, rgb(255 255 255 / 0.22), transparent);
  box-shadow: 0 0 8px rgb(255 255 255 / 0.06);
}
</style>
