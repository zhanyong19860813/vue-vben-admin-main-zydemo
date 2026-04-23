<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';

import { useAccessStore, useUserStore } from '@vben/stores';
import { Avatar, Button, Card, Spin, message } from 'ant-design-vue';

import { dingLoginByCode, getDingH5Config, type DingH5Config } from '#/api/dingtalkAuth';
import { useAuthStore } from '#/store/auth';
import {
  bindDdConfigAsync,
  ensureDingSdkLoadedAsync,
  isDingTalkContainer,
  looksLikeH5Config,
  pickPayload,
  requestAuthCodeAsync,
} from '#/utils/dingtalkJsApi';

type EntryStatus =
  | 'idle'
  | 'ding-loading'
  | 'ding-success'
  | 'ding-error'
  | 'browser-no-dd'
  | 'browser-session';

const userStore = useUserStore();
const authStore = useAuthStore();
const accessStore = useAccessStore();
const router = useRouter();

const entryStatus = ref<EntryStatus>('idle');
const dingErrorDetail = ref('');

onMounted(() => {
  void runEntry();
});

async function runEntry() {
  dingErrorDetail.value = '';
  // 兜底加载钉钉 SDK，覆盖 WebView 未自动注入 dd 的场景
  await ensureDingSdkLoadedAsync();

  if (isDingTalkContainer()) {
    entryStatus.value = 'ding-loading';
    try {
      const url =
        (typeof location !== 'undefined' ? location.href.split('#')[0] : '') || '';
      const res = await getDingH5Config(url);
      const cfg = pickPayload<DingH5Config>(res);
      if (!looksLikeH5Config(cfg)) {
        throw new Error(
          `获取 h5-config 失败: code=${String((res as any)?.code ?? '')} message=${String((res as any)?.message ?? '')} raw=${JSON.stringify(res)}`,
        );
      }
      await bindDdConfigAsync(cfg);
      const code = await requestAuthCodeAsync(cfg.corpId);
      const loginRes = await dingLoginByCode(code);
      const loginPayload = pickPayload<{ accessToken: string }>(loginRes);
      if (!loginPayload?.accessToken) {
        throw new Error(
          `login-by-code 失败: ${JSON.stringify(loginRes)}`,
        );
      }
      accessStore.setAccessToken(loginPayload.accessToken);
      await authStore.fetchUserInfo();
      entryStatus.value = 'ding-success';
      message.success('钉钉免登成功');
    } catch (e: unknown) {
      entryStatus.value = 'ding-error';
      const msg = e instanceof Error ? e.message : String(e);
      dingErrorDetail.value = msg;
      message.error(msg);
    }
    return;
  }

  if (accessStore.accessToken) {
    entryStatus.value = 'browser-session';
    await authStore.fetchUserInfo();
    return;
  }

  entryStatus.value = 'browser-no-dd';
}

const user = computed<Record<string, any>>(() => (userStore.userInfo || {}) as Record<string, any>);

const userName = computed(() => {
  return String(
    user.value.realName || user.value.name || user.value.username || user.value.userName || '',
  ).trim();
});

const employeeNo = computed(() => {
  return String(
    user.value.employeeId ||
      user.value.employeeNo ||
      user.value.employeeCode ||
      user.value.userCode ||
      '',
  ).trim();
});

const positionName = computed(() => {
  return String(
    user.value.positionName ||
      user.value.dutyName ||
      user.value.postName ||
      user.value.position ||
      user.value.post ||
      '',
  ).trim();
});

const avatarUrl = computed(() => {
  return String(user.value.avatar || user.value.avatarUrl || user.value.photo || '').trim();
});

const avatarText = computed(() => {
  const n = userName.value;
  return n ? n.slice(0, 1) : 'U';
});

const statusHint = computed(() => {
  switch (entryStatus.value) {
    case 'ding-loading':
      return '正在通过钉钉免登…';
    case 'ding-success':
      return '已通过钉钉免登登录';
    case 'browser-session':
      return '当前为浏览器环境，已使用系统登录态';
    case 'browser-no-dd':
      return '当前为浏览器环境且未登录；请在钉钉内打开本页完成免登，或先登录系统';
    case 'ding-error':
      return '钉钉免登失败，请查看下方原因';
    default:
      return '';
  }
});

function goNewProcess() {
  router.push('/workflow/new-process');
}

function goMyTodo() {
  router.push('/workflow/todo-all');
}

function goLogin() {
  router.push({
    path: '/auth/login',
    query: { redirect: encodeURIComponent('/dingtalk/home') },
  });
}
</script>

<template>
  <div class="ding-home-page">
    <Spin :spinning="entryStatus === 'ding-loading'" tip="钉钉免登中…">
      <div v-if="statusHint" class="ding-home-hint">{{ statusHint }}</div>

      <Card v-if="entryStatus === 'ding-error'" class="ding-home-card ding-error-card" :bordered="false">
        <div class="ding-error-title">免登失败</div>
        <pre class="ding-error-pre">{{ dingErrorDetail }}</pre>
        <Button type="primary" block class="mt-2" @click="runEntry">重试</Button>
      </Card>

      <Card v-if="entryStatus === 'browser-no-dd'" class="ding-home-card ding-error-card" :bordered="false">
        <div class="ding-error-title">未登录</div>
        <p class="ding-browser-tip">钉钉内打开本地址将自动完成免登。电脑端请先登录系统后再访问。</p>
        <Button type="primary" block @click="goLogin">去登录</Button>
      </Card>

      <template v-if="entryStatus !== 'browser-no-dd' && entryStatus !== 'ding-error'">
        <Card class="ding-home-card ding-user-card" :bordered="false">
          <div class="ding-home-header">
            <Avatar :size="72" :src="avatarUrl || undefined">
              {{ avatarText }}
            </Avatar>
            <div class="ding-home-name">{{ userName || '未获取到姓名' }}</div>
          </div>

          <div class="ding-home-row">
            <span class="ding-home-label">工号</span>
            <span class="ding-home-value">{{ employeeNo || '—' }}</span>
          </div>
          <div class="ding-home-row">
            <span class="ding-home-label">姓名</span>
            <span class="ding-home-value">{{ userName || '—' }}</span>
          </div>
          <div class="ding-home-row">
            <span class="ding-home-label">岗位</span>
            <span class="ding-home-value">{{ positionName || '—' }}</span>
          </div>
        </Card>

        <Card class="ding-home-card ding-entry-card" :bordered="false">
          <div class="ding-entry-title">常用入口</div>
          <Button type="primary" block class="ding-entry-btn" @click="goNewProcess">
            发起流程
          </Button>
          <Button block class="ding-entry-btn ding-entry-btn--todo" @click="goMyTodo">
            我的待办
          </Button>
        </Card>
      </template>
    </Spin>
  </div>
</template>

<style scoped>
/* 钉钉/暗色主题下也强制浅底深字，避免卡片区文字与背景对比度不足 */
.ding-home-page {
  box-sizing: border-box;
  min-height: 100vh;
  padding: 16px;
  color: #1a1a1a;
  background: #e8ecf0;
}

.ding-home-page :deep(.ant-card) {
  color: #1a1a1a;
  background: #fff !important;
  border: 1px solid #d9dee5;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.06);
}

.ding-home-page :deep(.ant-card-body) {
  color: #1a1a1a;
}

.ding-home-hint {
  max-width: 560px;
  margin: 0 auto 10px;
  padding: 8px 12px;
  font-size: 13px;
  color: #4b5563;
  background: #eef2f7;
  border-radius: 8px;
}

.ding-home-card {
  max-width: 560px;
  margin: 0 auto;
  border-radius: 14px;
}

.ding-error-card {
  margin-bottom: 12px;
}

.ding-error-title {
  font-weight: 600;
  margin-bottom: 8px;
  color: #b91c1c;
}

.ding-error-pre {
  margin: 0;
  font-size: 12px;
  white-space: pre-wrap;
  word-break: break-all;
  color: #374151;
}

.ding-browser-tip {
  margin: 0 0 12px;
  font-size: 14px;
  color: #6b7280;
}

.mt-2 {
  margin-top: 8px;
}

.ding-entry-card {
  margin-top: 12px;
}

.ding-entry-title {
  margin-bottom: 12px;
  font-size: 14px;
  color: #6b7280;
}

.ding-home-header {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 12px 0 18px;
}

.ding-home-name {
  margin-top: 10px;
  font-size: 18px;
  font-weight: 600;
  color: #0f172a;
}

.ding-home-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 12px 0;
  border-top: 1px solid #eef2f7;
}

.ding-home-label {
  color: #6b7280;
  font-size: 14px;
}

.ding-home-value {
  color: #0f172a;
  font-size: 15px;
  font-weight: 500;
}

.ding-entry-btn {
  height: 42px;
  border-radius: 10px;
  font-size: 15px;
}

.ding-entry-btn + .ding-entry-btn {
  margin-top: 10px;
}

.ding-entry-btn--todo {
  border-color: #dbe2ea;
}
</style>
