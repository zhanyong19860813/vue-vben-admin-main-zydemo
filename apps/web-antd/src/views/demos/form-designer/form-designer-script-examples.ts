/**
 * 表单设计器 · 「打开时脚本」「保存前脚本」内置示例（仅注释 + 安全可运行的 console，避免误向接口多写字段）
 */

export const FORM_DESIGNER_ON_OPEN_SCRIPT_EXAMPLE = `/**
 * 【打开时脚本】何时执行：弹窗打开后，表单 schema 与编辑行 initialValues 已写入之后。
 *
 * 典型场景（建议放这里）：
 * 1) 新增时设置默认值（单据日期、状态=草稿、默认部门）
 * 2) 编辑时根据主键补充详情（主表已有字段不够时，二次拉接口回填）
 * 3) 进入页面后按模式禁用/隐藏某些字段（例如编辑时不允许改编码）
 * 4) 上表单+下页签模式下，按主表字段触发一次预加载（例如先回填汇率）
 *
 * 入参 params：
 *   - mode: 'add' | 'edit'
 *   - initialValues: 列表传入的编辑行（新增时通常为空对象）
 *   - backendApi: 拼后端路径，如 params.backendApi('FormLookup/Employee')
 * 工具：
 *   - formApi.setValues({ 字段名: 值 })  给控件赋值
 *   - request(url, { method: 'GET'|'POST', data })  调接口；若脚本 return Promise，运行时会 await
 */

// —— 场景 1（可直接运行）：确认脚本已执行，打开浏览器 F12 → Console 可见
console.info('[打开时脚本] mode =', params.mode, 'initialKeys =', Object.keys(params.initialValues || {}));

// —— 场景 2：新增时设置默认值（把字段名改成你的）
if (params.mode === 'add') {
  formApi.setValues({
    // bill_date: new Date().toISOString().slice(0, 10),
    // status: '草稿',
  });
}

// —— 场景 3：编辑时按已有编码补拉详情并回填（可直接运行，需按你的接口改）
return (async () => {
  if (params.mode !== 'edit') return;
  const code = params.initialValues?.code;
  if (!code) return;
  try {
    const url = params.backendApi('FormLookup/Employee') + '?value=' + encodeURIComponent(String(code));
    const res = await request(url, { method: 'GET' });
    const row = res && typeof res === 'object' && 'data' in res ? res.data : res;
    if (row && typeof row === 'object') {
      formApi.setValues({
        // empName: row.name,
        // deptName: row.longdeptname,
      });
    }
  } catch (e) {
    console.warn('[打开时脚本] 详情回填失败:', e);
  }
})();
`;

export const FORM_DESIGNER_BEFORE_SUBMIT_SCRIPT_EXAMPLE = `/**
 * 【保存前脚本】何时执行：用户点「保存」、通过表单校验之后，发 datasave 请求之前。
 *
 * 典型场景（建议放这里）：
 * 1) 业务校验（主表字段组合合法性）
 * 2) 主从校验（至少一条明细、明细金额合计与主表一致）
 * 3) 提交前清洗（trim/空串转 null/补审计字段）
 * 4) 多页签按 tableName 做针对性校验（tabConfigs + tabTables）
 *
 * 入参：
 *   - params.formValues: 当前表单值（已 toRaw 前的快照由运行器传入）
 *   - params.tabTables: 仅当布局为「上表单+下页签表格」时有值，形如 { [页签key]: 行对象数组 }，可 JSON.stringify 后写入某表单字段再提交
 *   - params.tabConfigs: 页签配置数组（含 key/tab/tableName/primaryKey/foreignKeyField/mainKeyField）
 *   - formApi: 如需最新值可再取（一般直接用 params.formValues）
 * 返回（任选其一）：
 *   - { valid: false, message: '...' }  → 阻止保存并提示
 *   - { formValues: { ... } }           → 用新对象作为提交体（可 trim、补字段）
 *   - 不 return                         → 按原 formValues 提交
 */

const v = params.formValues;
const tabTables = params.tabTables || {};
const tabConfigs = params.tabConfigs || [];

// —— 场景 1（可直接运行）：保存前打印关键信息（不修改、不拦截）
console.info('[保存前脚本] 字段:', Object.keys(v || {}));
console.info('[保存前脚本] 页签:', tabConfigs.map((x) => ({ key: x.key, tab: x.tab, tableName: x.tableName })));

// —— 场景 2：主表业务校验（示例：单据编码不能为空）
if (v && Object.prototype.hasOwnProperty.call(v, 'code') && String(v.code ?? '').trim() === '') {
  return { valid: false, message: '单据编码(code)不能为空' };
}

// —— 场景 3：主从校验（示例：任一明细页签至少 1 行）
for (const t of tabConfigs) {
  const rows = tabTables[t.key] || [];
  if (rows.length === 0) {
    return { valid: false, message: '页签「' + (t.tab || t.key) + '」至少需要一条明细' };
  }
}

// —— 场景 4：提交前清洗（trim）
return {
  formValues: {
    ...v,
    code: String(v?.code ?? '').trim(),
    name: String(v?.name ?? '').trim(),
  },
};
`;
