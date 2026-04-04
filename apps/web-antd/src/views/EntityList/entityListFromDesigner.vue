<script setup lang="ts">
/**
 * 实体列表 - 从列表设计器 schema 动态渲染
 * 根据菜单 meta.query.entityname 查询 vben_entitylist_desinger 表的 code 字段，获取 schema_json 渲染列表
 * 根据当前用户 + menuid 查询 vben_v_user_role_menu_actions 过滤可见按钮，与权限体系融合
 * 菜单配置示例: meta: { "title": "实体列表", "query": { "entityname": "entityListDesinger", "menuid": "xxx" } }
 */
import { ref, computed, onMounted } from 'vue';
import { useRoute, onBeforeRouteUpdate } from 'vue-router';
import { useUserStore } from '@vben/stores';
import { useAuthStore } from '#/store';
import QueryTable from '#/components/QueryTable/index.vue';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { message } from 'ant-design-vue';
import type { QueryTableSchema } from '#/components/QueryTable/types';

const route = useRoute();
const userStore = useUserStore();
const authStore = useAuthStore();
const schema = ref<QueryTableSchema | null>(null);
const isLoading = ref(false);

// 调试信息：URL 加 ?debug=1 显示，方便复制发给 AI 排查
const debugInfo = ref<Record<string, any>>({});
const showDebug = computed(() => route.query?.debug === '1' || route.query?.debug === 'true');

// 支持 meta.query（菜单配置）和 route.query（URL 参数）
const entityName = computed(
  () =>
    ((route.meta?.query as Record<string, string>)?.['entityname'] ?? route.query?.entityname) as string,
);
const menuId = computed(
  () =>
    ((route.meta?.query as Record<string, string>)?.['menuid'] ?? route.query?.menuid) as string,
);

async function loadSchema() {
  if (!entityName.value?.trim()) {
    schema.value = null;
    return;
  }

  isLoading.value = true;
  schema.value = null;

  try {
    const res = await requestClient.post<{ items: Array<{ schema_json?: string }>; total: number }>(
      backendApi('DynamicQueryBeta/queryforvben'),
      {
        TableName: 'vben_entitylist_desinger',
        Page: 1,
        PageSize: 1,
        SortBy: 'updated_at',
        SortOrder: 'desc',
        Where: {
          Logic: 'AND',
          Conditions: [
            { Field: 'code', Operator: 'eq', Value: entityName.value.trim() },
          ],
          Groups: [],
        },
      },
    );

    const items = res?.items ?? [];
    const first = items[0];
    if (!first?.schema_json) {
      message.warning(`未找到 code 为「${entityName.value}」的列表配置`);
      return;
    }

    const parsed = JSON.parse(first.schema_json) as QueryTableSchema;

    // 根据当前用户权限过滤按钮（需配置 menuid）
    let allowedKeys = new Set<string>();
    let rawPermissionItems: any[] = [];
    if (menuId.value) {
      let userId = (userStore.userInfo as any)?.userId ?? (userStore.userInfo as any)?.id;
      if (!userId) {
        await authStore.fetchUserInfo();
        const u = userStore.userInfo as any;
        userId = u?.userId ?? u?.id;
      }
      if (userId) {
        const result = await loadUserAllowedActionKeys(userId);
        allowedKeys = result.keys;
        rawPermissionItems = result.rawItems;
        const toolbarBefore = parsed.toolbar?.actions?.map((a: any) => a.key) ?? [];
        parsed.toolbar = filterToolbarByAllowed(parsed.toolbar, allowedKeys);
        parsed.api = filterApiByAllowed(parsed.api, allowedKeys);
        if (showDebug.value) {
          debugInfo.value = {
            entityName: entityName.value,
            menuId: menuId.value,
            userId: (userStore.userInfo as any)?.userId ?? (userStore.userInfo as any)?.id,
            userInfoKeys: Object.keys(userStore.userInfo || {}),
            allowedKeys: [...allowedKeys],
            rawPermissionItems,
            schemaToolbarBefore: toolbarBefore,
            schemaToolbarAfter: parsed.toolbar?.actions?.map((a: any) => a.key) ?? [],
            permissionApiError: result.error,
          };
        }
      } else if (showDebug.value) {
        debugInfo.value = {
          entityName: entityName.value,
          menuId: menuId.value,
          userId: null,
          userInfoRaw: userStore.userInfo,
          note: 'userId 未获取到，未做权限过滤',
        };
      }
    } else if (showDebug.value) {
      debugInfo.value = { entityName: entityName.value, menuId: menuId.value, note: 'menuId 为空，未做权限过滤' };
    }

    schema.value = parsed;
  } catch (err) {
    console.error('加载 schema 失败:', err);
    message.error('获取列表配置失败');
  } finally {
    isLoading.value = false;
  }
}

/** 查询用户在该菜单下拥有的按钮 action_key 列表 */
async function loadUserAllowedActionKeys(
  userId: string,
): Promise<{ keys: Set<string>; rawItems: any[]; error?: string }> {
  try {
    const res = await requestClient.post<{ items: any[] }>(
      backendApi('DynamicQueryBeta/queryforvben'),
      {
        TableName: 'vben_v_user_role_menu_actions',
        Page: 1,
        PageSize: 500,
        Where: {
          Logic: 'AND',
          Conditions: [
            { Field: 'userid', Operator: 'eq', Value: userId },
            { Field: 'menu_id', Operator: 'eq', Value: menuId.value! },
          ],
          Groups: [],
        },
      },
    );
    const rawItems = res?.items ?? [];
    const keys = new Set<string>();
    rawItems.forEach((r: any) => {
      const key = r.action_key ?? r.actionKey ?? r.code;
      if (key) keys.add(String(key));
    });
    return { keys, rawItems };
  } catch (e) {
    return { keys: new Set(), rawItems: [], error: String(e) };
  }
}

/** action_key 别名：DB 可能存 delete/expol，schema 用 deleteSelected/export */
const ACTION_KEY_ALIASES: Record<string, string[]> = {
  deleteSelected: ['deleteSelected', 'delete'],
  export: ['export', 'expol'],
};

function isActionAllowed(key: string, allowed: Set<string>): boolean {
  if (allowed.has(key)) return true;
  const aliases = ACTION_KEY_ALIASES[key];
  if (aliases) return aliases.some((a) => allowed.has(a));
  return false;
}

/** 按允许的 action_key 过滤 toolbar.actions */
function filterToolbarByAllowed(
  toolbar: QueryTableSchema['toolbar'],
  allowed: Set<string>,
): QueryTableSchema['toolbar'] {
  if (!toolbar?.actions?.length) return toolbar;
  return {
    ...toolbar,
    actions: toolbar.actions.filter((a) => isActionAllowed(a.key, allowed)),
  };
}

/** 按允许的 action_key 过滤 api（删除=deleteSelected/delete，导出=export/expol） */
function filterApiByAllowed(
  api: QueryTableSchema['api'],
  allowed: Set<string>,
): QueryTableSchema['api'] {
  if (!api) return api;
  const next = { ...api };
  if (api.delete && !allowed.has('deleteSelected') && !allowed.has('delete')) next.delete = '';
  if (api.export && !allowed.has('export') && !allowed.has('expol')) next.export = '';
  return next;
}

onMounted(() => {
  loadSchema();
});

onBeforeRouteUpdate(() => {
  loadSchema();
});
</script>

<template>
  <div class="relative flex h-full min-h-0 flex-1 flex-col overflow-hidden">
    <QueryTable v-if="schema" :schema="schema" :loading="isLoading" />
    <div
      v-else-if="!entityName"
      class="flex h-64 items-center justify-center text-muted-foreground"
    >
      请在菜单 meta.query 中配置 entityname 参数
    </div>
    <div
      v-else-if="!isLoading && !schema"
      class="flex h-64 items-center justify-center text-muted-foreground"
    >
      未找到对应列表配置，请检查 entityname 是否正确
    </div>
    <!-- 调试面板：URL 加 ?debug=1 显示，复制内容发给 AI 排查 -->
    <div
      v-if="showDebug && Object.keys(debugInfo).length"
      class="fixed bottom-2 right-2 z-50 max-h-80 w-[400px] overflow-auto rounded border border-orange-300 bg-amber-50 p-3 text-xs shadow-lg"
    >
      <div class="mb-2 font-bold text-orange-700">调试信息（复制下面 JSON 发给 AI）</div>
      <pre class="whitespace-pre-wrap break-all">{{ JSON.stringify(debugInfo, null, 2) }}</pre>
    </div>
  </div>
</template>
