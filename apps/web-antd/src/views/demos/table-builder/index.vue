<script setup lang="ts">
/**
 * 表结构设计器 - 在界面上建表，真实在数据库中创建
 * 创建的表名必须以 vben_t_ 开头
 */
import { ref, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { Page } from '@vben/common-ui';
import {
  Button,
  Card,
  Input,
  InputNumber,
  message,
  Select,
  Space,
} from 'ant-design-vue';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

const TABLE_PREFIX = 'vben_t_';

interface ColumnDef {
  key: string;
  name: string;
  dataType: string;
  length: number;
  precision?: number;
  scale?: number;
  nullable: boolean;
  isPrimaryKey: boolean;
  defaultValue: string;
}

const tableName = ref('');
const tableDescription = ref('');
const columns = ref<ColumnDef[]>([]);
const saving = ref(false);
const existingTables = ref<string[]>([]);
const loadingTables = ref(false);
const router = useRouter();

const DATA_TYPE_OPTIONS = [
  { value: 'uniqueidentifier', label: 'GUID (uniqueidentifier)' },
  { value: 'nvarchar', label: '文本 (nvarchar)' },
  { value: 'varchar', label: '文本-ascii (varchar)' },
  { value: 'int', label: '整数 (int)' },
  { value: 'bigint', label: '长整数 (bigint)' },
  { value: 'smallint', label: '短整数 (smallint)' },
  { value: 'decimal', label: '小数 (decimal)' },
  { value: 'bit', label: '布尔 (bit)' },
  { value: 'datetime', label: '日期时间 (datetime)' },
  { value: 'date', label: '日期 (date)' },
];

function needsLength(type: string) {
  return ['nvarchar', 'varchar', 'char', 'nchar'].includes(type);
}
function needsPrecision(type: string) {
  return type === 'decimal';
}

function addColumn() {
  const key = `col_${Date.now()}`;
  columns.value.push({
    key,
    name: '',
    dataType: 'nvarchar',
    length: 50,
    nullable: true,
    isPrimaryKey: columns.value.length === 0,
    defaultValue: '',
  });
}

function removeColumn(index: number) {
  columns.value.splice(index, 1);
}

function moveUp(index: number) {
  if (index <= 0) return;
  const a = columns.value[index - 1];
  const b = columns.value[index];
  columns.value[index - 1] = b;
  columns.value[index] = a;
}

function moveDown(index: number) {
  if (index >= columns.value.length - 1) return;
  const a = columns.value[index];
  const b = columns.value[index + 1];
  columns.value[index] = b;
  columns.value[index + 1] = a;
}

async function loadExistingTables() {
  loadingTables.value = true;
  try {
    const res = await requestClient.get<{ data?: string[] }>(
      backendApi('TableBuilder/ListTables'),
    );
    existingTables.value = res?.data ?? [];
  } catch {
    existingTables.value = [];
  } finally {
    loadingTables.value = false;
  }
}

async function createTable() {
  const input = tableName.value?.trim() || '';
  if (!input) {
    message.warning('请输入表名');
    return;
  }
  const name = input.startsWith(TABLE_PREFIX) ? input : TABLE_PREFIX + input;
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(name)) {
    message.warning('表名只能包含字母、数字、下划线');
    return;
  }

  const primaryCount = columns.value.filter((c) => c.isPrimaryKey).length;
  if (primaryCount === 0) {
    message.warning('请指定一个主键字段');
    return;
  }
  if (primaryCount > 1) {
    message.warning('暂只支持单主键');
    return;
  }

  const invalidCols = columns.value.filter((c) => !c.name?.trim() || !/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(c.name.trim()));
  if (invalidCols.length) {
    message.warning('请填写有效的字段名（字母、数字、下划线）');
    return;
  }

  saving.value = true;
  try {
    await requestClient.post(backendApi('TableBuilder/CreateTable'), {
      tableName: name,
      description: tableDescription.value?.trim() || undefined,
      columns: columns.value.map((c) => ({
        name: c.name.trim(),
        dataType: c.dataType,
        length: needsLength(c.dataType) ? c.length : undefined,
        precision: needsPrecision(c.dataType) ? (c.precision ?? 18) : undefined,
        scale: needsPrecision(c.dataType) ? (c.scale ?? 2) : undefined,
        nullable: c.nullable,
        isPrimaryKey: c.isPrimaryKey,
        defaultValue: c.defaultValue?.trim() || undefined,
      })),
    });
    message.success('表创建成功');
    await loadExistingTables();
    tableName.value = '';
    tableDescription.value = '';
    columns.value = [];
  } catch (e: any) {
    message.error(e?.data?.message || e?.message || '创建失败');
  } finally {
    saving.value = false;
  }
}

function goToListDesigner(t: string) {
  const path = router.resolve({
    name: 'ListDesigner',
    query: { table: t },
  });
  window.open(path.href, '_blank');
}

onMounted(() => {
  loadExistingTables();
});
</script>

<template>
  <Page
    description="在界面上建表，直接在数据库中创建。表名必须以 vben_t_ 开头，创建后可前往列表设计器配置"
    title="表结构设计器"
  >
    <div class="table-builder flex flex-col gap-4 p-4">
      <div class="flex gap-4">
        <!-- 左侧：建表表单 -->
        <Card class="flex-1" size="small" title="新建表">
          <div class="flex flex-col gap-4">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <div class="mb-1 text-xs">表名 <span class="text-red-500">*</span></div>
                <Input
                  v-model:value="tableName"
                  :addon-before="TABLE_PREFIX"
                  placeholder="base_product（自动补全前缀）"
                  size="small"
                />
                <div class="mt-1 text-muted-foreground text-xs">
                  完整表名：{{ tableName ? (tableName.startsWith(TABLE_PREFIX) ? tableName : TABLE_PREFIX + tableName) : '...' }}
                </div>
              </div>
              <div>
                <div class="mb-1 text-xs">表说明</div>
                <Input
                  v-model:value="tableDescription"
                  placeholder="可选"
                  size="small"
                />
              </div>
            </div>

            <div>
              <div class="mb-2 flex items-center justify-between">
                <span class="text-xs font-medium">字段定义</span>
                <Button size="small" type="primary" @click="addColumn">+ 添加字段</Button>
              </div>

              <div v-if="columns.length === 0" class="rounded border border-dashed p-6 text-center text-muted-foreground text-sm">
                点击「添加字段」开始定义表结构
              </div>

              <div v-else class="space-y-2">
                <div
                  v-for="(col, i) in columns"
                  :key="col.key"
                  class="flex flex-wrap items-center gap-2 rounded border p-2"
                >
                  <Input
                    v-model:value="col.name"
                    placeholder="字段名"
                    size="small"
                    class="w-28"
                  />
                  <Select
                    v-model:value="col.dataType"
                    :options="DATA_TYPE_OPTIONS"
                    size="small"
                    class="w-40"
                  />
                  <InputNumber
                    v-if="needsLength(col.dataType)"
                    v-model:value="col.length"
                    :min="1"
                    :max="8000"
                    size="small"
                    class="w-20"
                  />
                  <template v-if="needsPrecision(col.dataType)">
                    <InputNumber v-model:value="col.precision" :min="1" :max="38" size="small" class="w-16" placeholder="p" />
                    <InputNumber v-model:value="col.scale" :min="0" :max="38" size="small" class="w-16" placeholder="s" />
                  </template>
                  <Space>
                    <span class="text-xs">
                      <input v-model="col.nullable" type="checkbox" :id="`null-${col.key}`" />
                      <label :for="`null-${col.key}`" class="ml-1">可空</label>
                    </span>
                    <span class="text-xs">
                      <input v-model="col.isPrimaryKey" type="checkbox" :id="`pk-${col.key}`" />
                      <label :for="`pk-${col.key}`" class="ml-1">主键</label>
                    </span>
                  </Space>
                  <Input
                    v-model:value="col.defaultValue"
                    placeholder="默认值 (NEWID/GETDATE/0/1)"
                    size="small"
                    class="w-36"
                  />
                  <div class="flex gap-1">
                    <Button size="small" @click="moveUp(i)" :disabled="i === 0">↑</Button>
                    <Button size="small" @click="moveDown(i)" :disabled="i === columns.length - 1">↓</Button>
                    <Button danger size="small" @click="removeColumn(i)">×</Button>
                  </div>
                </div>
              </div>
            </div>

            <Button type="primary" :loading="saving" block @click="createTable">
              创建表
            </Button>
          </div>
        </Card>

        <!-- 右侧：已存在的表 -->
        <Card class="w-72 shrink-0" size="small" title="已创建的表">
          <div v-if="loadingTables" class="py-4 text-center text-muted-foreground text-sm">
            加载中...
          </div>
          <div v-else-if="existingTables.length === 0" class="py-4 text-center text-muted-foreground text-sm">
            暂无
          </div>
          <div v-else class="space-y-1">
            <div
              v-for="t in existingTables"
              :key="t"
              class="flex items-center justify-between rounded border px-2 py-1.5 hover:bg-muted/50"
            >
              <span class="truncate font-mono text-sm">{{ t }}</span>
              <Button size="small" type="link" @click="goToListDesigner(t)">
                配置列表
              </Button>
            </div>
            <Button size="small" block class="mt-2" @click="loadExistingTables">
              刷新
            </Button>
          </div>
        </Card>
      </div>

      <Card size="small" title="说明">
        <ul class="list-inside list-disc space-y-1 text-muted-foreground text-sm">
          <li>表名必须以 <code>vben_t_</code> 开头，创建后可在列表设计器、表单设计器中使用</li>
          <li>主键：GUID 类型建议默认值填 <code>NEWID()</code>，日期类型可填 <code>GETDATE()</code></li>
          <li>创建成功后，点击右侧「配置列表」可跳转到列表设计器并自动填入该表</li>
        </ul>
      </Card>
    </div>
  </Page>
</template>
