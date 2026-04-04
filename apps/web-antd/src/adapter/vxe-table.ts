import type { VxeTableGridOptions } from '@vben/plugins/vxe-table';

import { h } from 'vue';

import { setupVbenVxeTable, useVbenVxeGrid } from '@vben/plugins/vxe-table';

import { Button, Image } from 'ant-design-vue';

import { fillHrefTemplate } from '#/components/QueryTable/queryTableGridEnhance';

import { useVbenForm } from './form';

setupVbenVxeTable({
  configVxeTable: (vxeUI) => {
    vxeUI.setConfig({
      grid: {
        align: 'center',
        border: false,
        columnConfig: {
          resizable: true,
        },
        minHeight: 180,
        formConfig: {
          // 全局禁用vxe-table的表单配置，使用formOptions
          enabled: false,
        },
        proxyConfig: {
          autoLoad: true,
          response: {
            result: 'items',
            total: 'total',
            list: 'items',
          },
          showActiveMsg: true,
          showResponseMsg: false,
        },
        round: true,
        showOverflow: true,
        size: 'small',
      } as VxeTableGridOptions,
    });

    // 表格配置项可以用 cellRender: { name: 'CellImage' },
    vxeUI.renderer.add('CellImage', {
      renderTableDefault(renderOpts, params) {
        const { props } = renderOpts;
        const { column, row } = params;
        return h(Image, { src: row[column.field], ...props });
      },
    });

    // 表格配置项可以用 cellRender: { name: 'CellLink' },
    vxeUI.renderer.add('CellLink', {
      renderTableDefault(renderOpts) {
        const { props } = renderOpts;
        return h(
          Button,
          { size: 'small', type: 'link' },
          { default: () => props?.text },
        );
      },
    });

    /** 列表 schema：cellRender: { name: 'SchemaHyperlink', props: { hrefTemplate, openInNewTab } } */
    vxeUI.renderer.add('SchemaHyperlink', {
      renderTableDefault(renderOpts, params) {
        const { props } = renderOpts;
        const { column, row } = params;
        const template = (props?.hrefTemplate as string) || '';
        const href = fillHrefTemplate(template, row as Record<string, any>);
        const text = row[column.field as string];
        const label = text === undefined || text === null ? '' : String(text);
        if (!href) {
          return h('span', label);
        }
        return h('a', {
          href,
          target: props?.openInNewTab ? '_blank' : '_self',
          rel: props?.openInNewTab ? 'noopener noreferrer' : undefined,
          class: 'text-primary hover:underline',
        }, label);
      },
    });

    /**
     * 主列为空时用 fallback 字段显示（如请假单号 HD_ID 老数据为空，老系统「记录编号」界面常对应 FID）
     * schema：cellRender: { name: 'CellFieldFallback', props: { fallbackField: 'FID' } }
     */
    vxeUI.renderer.add('CellFieldFallback', {
      renderTableDefault(renderOpts, params) {
        const { props } = renderOpts;
        const { column, row } = params;
        const field = String(column?.field ?? '');
        const primary = field ? (row as any)?.[field] : undefined;
        const empty =
          primary === null ||
          primary === undefined ||
          (typeof primary === 'string' && primary.trim() === '');
        const fb = String(props?.fallbackField ?? '').trim();
        const v = empty && fb ? (row as any)?.[fb] : primary;
        const text = v === undefined || v === null ? '' : String(v);
        return h('span', text);
      },
    });

    // 这里可以自行扩展 vxe-table 的全局配置，比如自定义格式化
    // vxeUI.formats.add
  },
  useVbenForm,
});

export { useVbenVxeGrid };

export type * from '@vben/plugins/vxe-table';
