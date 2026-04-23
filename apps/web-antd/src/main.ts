import { initPreferences } from '@vben/preferences';
import { unmountGlobalLoading } from '@vben/utils';

import { overridesPreferences } from './preferences';

// import Antd from 'ant-design-vue';
// import 'ant-design-vue/dist/antd.css';
 

function normalizeDingTalkHomeEntry() {
  if (typeof window === 'undefined') return;
  const { pathname, hash, search, origin } = window.location;
  if (!pathname.toLowerCase().startsWith('/dingtalk/home')) return;

  // 直接访问 /dingtalk/home 时（无 hash 路由），强制落到移动端首页路由，
  // 避免被根路由重定向到默认首页（如 /analytics）。
  if (!hash || hash === '#' || hash === '#/' || hash === '#/analytics') {
    const target = `${origin}${pathname}${search}#/dingtalk/home`;
    window.location.replace(target);
  }
}

/**
 * 应用初始化完成之后再进行页面加载渲染
 */
async function initApplication() {
  normalizeDingTalkHomeEntry();

  // name用于指定项目唯一标识
  // 用于区分不同项目的偏好设置以及存储数据的key前缀以及其他一些需要隔离的数据
  const env = import.meta.env.PROD ? 'prod' : 'dev';
  const appVersion = import.meta.env.VITE_APP_VERSION;
  const namespace = `${import.meta.env.VITE_APP_NAMESPACE}-${appVersion}-${env}`;

  // app偏好设置初始化
  await initPreferences({
    namespace,
    overrides: overridesPreferences,
  });

 
  // 启动应用并挂载
  // vue应用主要逻辑及视图
  const { bootstrap } = await import('./bootstrap');
  await bootstrap(namespace);

  // 移除并销毁loading
  unmountGlobalLoading();
}

initApplication();
