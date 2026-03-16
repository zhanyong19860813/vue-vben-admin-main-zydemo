<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { Tree as ATree, Button, message } from 'ant-design-vue';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { useVbenModal } from '@vben/common-ui';

import DictionaryCategoryModal from './DictionaryCategoryModal.vue';

const emit = defineEmits<{
  (e: 'change', id: string, name: string): void;
}>();

const dictionaryTreeDatas = ref<any[]>([]);
const expandedKeys = ref<string[]>([]);
const currentDictionaryId = ref<string>();
const currentDictionaryName = ref<string>();

const ROOT_PARENT = '00000000-0000-0000-0000-000000000000';

/** 转换为 TreeSelect 所需格式（含根节点），用于弹窗选择父节点 */
function toTreeSelectData(nodes: any[]): any[] {
  const root = { title: '根节点', value: ROOT_PARENT, key: 'root' };
  if (!nodes?.length) return [root];
  const map = (list: any[]) =>
    list.map((n) => ({
      title: n.title || n.name || '未命名',
      value: n.key ?? n.id,
      key: n.key ?? n.id,
      children: n.children?.length ? map(n.children) : undefined,
    }));
  return [root, ...map(nodes)];
}

function normId(v: any): string {
  const s = (v ?? ROOT_PARENT) + '';
  return s.toLowerCase();
}

function buildTree(list: any[], parentId: string | null): any[] {
  const pid = normId(parentId ?? ROOT_PARENT);
  return list
    .filter(
      (x) =>
        normId(x.parent_id ?? x.parentId) === pid
    )
    .sort((a, b) => (a.sort ?? 0) - (b.sort ?? 0))
    .map((x) => ({
      key: x.id,
      id: x.id,
      title: x.name || x.code || '未命名',
      name: x.name,
      code: x.code,
      data_type: x.data_type,
      description: x.description,
      parent_id: x.parent_id ?? x.parentId,
      sort: x.sort,
      children: buildTree(list, x.id),
    }));
}

const loadTree = async () => {
  try {
    const res = await requestClient.post(backendApi('DynamicQueryBeta/queryforvben'), {
      TableName: 'vben_t_base_dictionary',
      Page: 1,
      PageSize: 5000,
      SortBy: 'sort',
      SortOrder: 'asc',
    });
    const raw = res?.data ?? res;
    const list = raw?.items ?? raw?.records ?? [];
    const tree = buildTree(list, null);
    dictionaryTreeDatas.value = tree;
    expandedKeys.value = tree.map((n: any) => n.key);
  } catch (error) {
    console.error('加载字典树失败:', error);
    message.error('加载字典树失败');
    dictionaryTreeDatas.value = [];
  }
};

onMounted(loadTree);

const handleExpand = (keys: string[]) => {
  expandedKeys.value = keys;
};

const handleSelect = (selectedKeys: string[], info: any) => {
  if (!selectedKeys?.length) return;
  currentDictionaryId.value = selectedKeys[0];
  currentDictionaryName.value = info.node?.title ?? info.node?.name ?? '';
  emit('change', currentDictionaryId.value, currentDictionaryName.value);
};

const [FormModal, formModalApi] = useVbenModal({
  connectedComponent: DictionaryCategoryModal,
});

function openAddDictionary() {
  formModalApi
    .setData({
      values: {
        parent_id: currentDictionaryId.value ?? ROOT_PARENT,
        treeData: toTreeSelectData(dictionaryTreeDatas.value),
        onSuccess: loadTree,
      },
    })
    .open();
}

function openEditDictionary() {
  if (!currentDictionaryId.value) {
    message.warning('请先选择一个字典分类');
    return;
  }
  const node = findNode(dictionaryTreeDatas.value, currentDictionaryId.value);
  if (!node) return;
  formModalApi
    .setData({
      values: {
        id: currentDictionaryId.value,
        name: node.name,
        code: node.code,
        data_type: node.data_type,
        description: node.description,
        parent_id: node.parent_id ?? ROOT_PARENT,
        sort: node.sort,
        treeData: toTreeSelectData(dictionaryTreeDatas.value),
        onSuccess: loadTree,
      },
    })
    .open();
}

function findNode(nodes: any[], id: string): any {
  for (const n of nodes) {
    if (n.key === id || n.id === id) return n;
    if (n.children?.length) {
      const found = findNode(n.children, id);
      if (found) return found;
    }
  }
  return null;
}

async function deleteDictionary() {
  if (!currentDictionaryId.value) {
    message.warning('请先选择一个字典分类');
    return;
  }
  try {
    await requestClient.post(backendApi('DataBatchDelete/BatchDelete'), [
      {
        tablename: 'vben_t_base_dictionary',
        key: 'id',
        Keys: [currentDictionaryId.value],
      },
    ], { headers: { 'Content-Type': 'application/json' } });
    message.success('删除成功');
    currentDictionaryId.value = undefined;
    currentDictionaryName.value = undefined;
    await loadTree();
  } catch (e) {
    message.error('删除失败');
  }
}
</script>

<template>
  <div
    class="mr-2 flex h-full min-w-[220px] flex-col rounded-[var(--radius)] border border-border bg-card p-2"
  >
    <div class="mb-2 font-bold text-lg">
      <Button class="mr-1" type="primary" size="small" @click="openAddDictionary">
        新增字典
      </Button>
      <Button class="mr-1" size="small" @click="openEditDictionary">编辑字典</Button>
      <Button danger size="small" @click="deleteDictionary">删除</Button>
    </div>
    <div class="min-h-0 flex-1 overflow-auto">
      <ATree
        :tree-data="dictionaryTreeDatas"
        :expanded-keys="expandedKeys"
        @expand="handleExpand"
        @select="handleSelect"
      />
    </div>
    <FormModal />
  </div>
</template>
