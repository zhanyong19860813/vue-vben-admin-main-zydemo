<script setup lang="ts">
import { reactive, ref } from 'vue';
import { ColPage } from '@vben/common-ui';
import { Card } from 'ant-design-vue';

import DictionaryTree from './DictionaryTree.vue';
import DictionaryDetailGrid from './DictionaryDetailGrid.vue';

const props = reactive({
  leftCollapsedWidth: 5,
  leftCollapsible: true,
  leftMaxWidth: 50,
  leftMinWidth: 20,
  leftWidth: 25,
  resizable: true,
  rightWidth: 75,
  splitHandle: true,
  splitLine: true,
});

const currentDictionaryId = ref<string>();
const currentDictionaryName = ref<string>();

function handleDictionaryChange(id: string, name: string) {
  currentDictionaryId.value = id;
  currentDictionaryName.value = name;
}
</script>

<template>
  <ColPage v-bind="props" auto-content-height>
    <template #left>
      <DictionaryTree @change="handleDictionaryChange" />
    </template>

    <Card
      class="ml-1 flex h-full flex-1 flex-col !border-border"
      :body-style="{
        flex: 1,
        minHeight: 0,
        display: 'flex',
        flexDirection: 'column',
        padding: '12px',
      }"
    >
      <div v-if="currentDictionaryId" class="mb-2 text-sm text-gray-500">
        当前字典：{{ currentDictionaryName }}
      </div>
      <DictionaryDetailGrid :current-dictionary-id="currentDictionaryId" />
    </Card>
  </ColPage>
</template>
