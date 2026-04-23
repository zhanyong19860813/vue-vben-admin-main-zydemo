<script lang="ts" setup>
import { computed, ref } from 'vue';

import { Button, Card, Input, Space, message } from 'ant-design-vue';

import {
  dingDemoLoginByUserId,
  dingLoginByCode,
  getDingH5Config,
  type DingH5Config,
} from '#/api/dingtalkAuth';

type MaybeDingWindow = Window & {
  dd?: {
    config?: (cfg: Record<string, unknown>) => void;
    error?: (cb: (err: unknown) => void) => void;
    ready?: (cb: () => void) => void;
    runtime?: {
      permission?: {
        requestAuthCode?: (arg: {
          corpId: string;
          onSuccess?: (res: { code?: string }) => void;
          onFail?: (err: unknown) => void;
        }) => void;
      };
    };
  };
};

const loadingConfig = ref(false);
const loadingLogin = ref(false);
const loadingDemoLogin = ref(false);

const currentUrl = ref(typeof location === 'undefined' ? '' : location.href.split('#')[0] || '');
const authCode = ref('');
const demoUserId = ref('');
const h5Config = ref<DingH5Config | null>(null);
const loginResult = ref<Record<string, unknown> | null>(null);
const lastError = ref<string>('');

const dingReady = ref(false);
const hasDd = computed(() => Boolean((window as MaybeDingWindow).dd));

function pickPayload<T extends Record<string, any>>(res: any): T | null {
  if (!res || typeof res !== 'object') return null;
  if ('data' in res && res.data && typeof res.data === 'object') return res.data as T;
  return res as T;
}

function looksLikeH5Config(v: any): v is DingH5Config {
  return Boolean(
    v &&
      typeof v === 'object' &&
      typeof v.corpId === 'string' &&
      typeof v.agentId === 'string' &&
      typeof v.signature === 'string',
  );
}

async function loadH5Config() {
  const url = currentUrl.value.trim();
  if (!url) {
    message.warning('请先填写当前 URL');
    return;
  }
  loadingConfig.value = true;
  try {
    const res = await getDingH5Config(url);
    const payload = pickPayload<DingH5Config>(res);
    if (!looksLikeH5Config(payload)) {
      const detail = `获取 h5-config 失败\ncode=${String(res?.code ?? '')}\nmessage=${String(res?.message ?? '')}\nresponse=${JSON.stringify(res ?? {}, null, 2)}`;
      lastError.value = detail;
      message.error(res?.message || `获取 h5-config 失败（code=${String(res?.code ?? '')}）`);
      return;
    }
    h5Config.value = payload;
    lastError.value = '';
    dingReady.value = false;
    bindDdConfig(payload);
    message.success('h5-config 获取成功');
  } catch (e: any) {
    const backendMsg = e?.response?.data?.message || e?.response?.data?.msg || '';
    const backendCode = e?.response?.data?.code;
    const status = e?.response?.status;
    const raw = e?.response?.data ? JSON.stringify(e.response.data, null, 2) : '';
    const detail = `获取 h5-config 异常\nhttpStatus=${String(status ?? '')}\nbackendCode=${String(backendCode ?? '')}\nbackendMessage=${String(backendMsg)}\nerrorMessage=${String(e?.message ?? '')}\nresponse=${raw}`;
    lastError.value = detail;
    message.error(backendMsg || e?.message || '获取 h5-config 异常');
  } finally {
    loadingConfig.value = false;
  }
}

function bindDdConfig(cfg: DingH5Config) {
  const dd = (window as MaybeDingWindow).dd;
  if (!dd?.config) {
    message.warning('当前环境未检测到 dd.js');
    return;
  }
  dd.error?.((err: unknown) => {
    dingReady.value = false;
    console.error('dd.error', err);
    message.error('dd.config 校验失败，请检查签名');
  });
  dd.ready?.(() => {
    dingReady.value = true;
    message.success('dd.ready 成功，可申请 authCode');
  });
  dd.config({
    agentId: cfg.agentId,
    corpId: cfg.corpId,
    timeStamp: cfg.timeStamp,
    nonceStr: cfg.nonceStr,
    signature: cfg.signature,
    jsApiList: ['runtime.permission.requestAuthCode'],
  });
}

async function loginByCode() {
  const code = authCode.value.trim();
  if (!code) return message.warning('请先填写/获取 authCode');
  loadingLogin.value = true;
  try {
    const res = await dingLoginByCode(code);
    const payload = pickPayload<any>(res);
    if (!payload?.accessToken) {
      message.error(res?.message || '免登换 token 失败');
      return;
    }
    loginResult.value = payload as Record<string, unknown>;
    message.success('免登成功，已拿到 JWT');
  } catch (e: any) {
    message.error(e?.message || '免登失败');
  } finally {
    loadingLogin.value = false;
  }
}

function requestAuthCodeFromDingTalk() {
  const dd = (window as MaybeDingWindow).dd;
  if (!h5Config.value) {
    message.warning('请先获取 h5-config');
    return;
  }
  if (!dd?.runtime?.permission?.requestAuthCode) {
    message.warning('当前环境不支持 requestAuthCode');
    return;
  }
  dd.runtime.permission.requestAuthCode({
    corpId: h5Config.value.corpId,
    onSuccess: (res) => {
      authCode.value = (res?.code || '').trim();
      if (authCode.value) {
        message.success('已获取 authCode');
      } else {
        message.warning('钉钉返回 code 为空');
      }
    },
    onFail: (err) => {
      console.error(err);
      message.error('获取 authCode 失败');
    },
  });
}

async function demoLogin() {
  const userId = demoUserId.value.trim();
  if (!userId) return message.warning('请输入 userId');
  loadingDemoLogin.value = true;
  try {
    const res = await dingDemoLoginByUserId(userId);
    const payload = pickPayload<any>(res);
    if (!payload?.accessToken) {
      message.error(res?.message || 'demo 登录失败');
      return;
    }
    loginResult.value = payload as Record<string, unknown>;
    message.success('demo 登录成功');
  } catch (e: any) {
    message.error(e?.message || 'demo 登录异常');
  } finally {
    loadingDemoLogin.value = false;
  }
}
</script>

<template>
  <div class="p-4">
    <Card title="钉钉免登联调 Demo（StoneApi + Vue）">
      <Space direction="vertical" style="width: 100%" :size="14">
        <div>步骤：1) 获取 h5-config 2) 钉钉取 code 3) code 换系统 JWT</div>
        <div>dd.js 检测：{{ hasDd ? '已检测到' : '未检测到（非钉钉环境正常）' }}，ready：{{ dingReady ? '是' : '否' }}</div>

        <Space wrap>
          <Input v-model:value="currentUrl" style="width: 520px" placeholder="当前页面 URL（用于签名）" />
          <Button type="primary" :loading="loadingConfig" @click="loadH5Config">获取 h5-config</Button>
        </Space>

        <Space wrap>
          <Input v-model:value="authCode" style="width: 520px" placeholder="钉钉 authCode" />
          <Button @click="requestAuthCodeFromDingTalk">钉钉取 code</Button>
          <Button type="primary" :loading="loadingLogin" @click="loginByCode">code 换 JWT</Button>
        </Space>

        <Space wrap>
          <Input v-model:value="demoUserId" style="width: 520px" placeholder="本地联调 userId（employee_id/username/id）" />
          <Button :loading="loadingDemoLogin" @click="demoLogin">Demo 登录（不走钉钉）</Button>
        </Space>

        <Card v-if="h5Config" size="small" title="h5-config 返回">
          <pre class="m-0">{{ JSON.stringify(h5Config, null, 2) }}</pre>
        </Card>

        <Card v-if="loginResult" size="small" title="登录返回（含 accessToken）">
          <pre class="m-0">{{ JSON.stringify(loginResult, null, 2) }}</pre>
        </Card>

        <Card v-if="lastError" size="small" title="最近一次失败原因">
          <pre class="m-0 text-red-500">{{ lastError }}</pre>
        </Card>
      </Space>
    </Card>
  </div>
</template>
