import dayjs from 'dayjs';
import timezone from 'dayjs/plugin/timezone';
import utc from 'dayjs/plugin/utc';

dayjs.extend(utc);
dayjs.extend(timezone);

type FormatDate = Date | dayjs.Dayjs | number | string;

type Format =
  | 'HH'
  | 'HH:mm'
  | 'HH:mm:ss'
  | 'YYYY'
  | 'YYYY-MM'
  | 'YYYY-MM-DD'
  | 'YYYY-MM-DD HH'
  | 'YYYY-MM-DD HH:mm'
  | 'YYYY-MM-DD HH:mm:ss'
  | (string & {});

export function formatDate(time?: FormatDate, format: Format = 'YYYY-MM-DD') {
  try {
    const date = dayjs.isDayjs(time) ? time : dayjs(time);
    if (!date.isValid()) {
      throw new Error('Invalid date');
    }
    return date.tz().format(format);
  } catch (error) {
    console.error(`Error formatting date: ${error}`);
    return String(time ?? '');
  }
}

export function formatDateTime(time?: FormatDate) {
  return formatDate(time, 'YYYY-MM-DD HH:mm:ss');
}

export function isDate(value: any): value is Date {
  return value instanceof Date;
}

export function isDayjsObject(value: any): value is dayjs.Dayjs {
  return dayjs.isDayjs(value);
}

/**
 * 获取当前时区
 * @returns 当前时区
 */
export const getSystemTimezone = () => {
  return dayjs.tz.guess();
};

/**
 * 自定义设置的时区
 */
let currentTimezone = getSystemTimezone();

/**
 * 设置默认时区
 * @param timezone
 */
export const setCurrentTimezone = (timezone?: string) => {
  currentTimezone = timezone || getSystemTimezone();
  dayjs.tz.setDefault(currentTimezone);
};

/**
 * 获取设置的时区
 * @returns 设置的时区
 */
export const getCurrentTimezone = () => {
  return currentTimezone;
};

/** Ant Design Vue 日期类控件绑定值须为 dayjs（字符串会触发 date.locale is not a function） */
const ANTD_DATE_PICKER_COMPONENTS = new Set([
  'DatePicker',
  'RangePicker',
  'TimePicker',
]);

/**
 * 将表格/接口回填的字符串、时间戳、Date 转为 dayjs；已是 dayjs 则原样返回
 */
export function parseToDayjs(value: unknown): dayjs.Dayjs | undefined {
  if (value === null || value === undefined || value === '') {
    return undefined;
  }
  if (isDayjsObject(value)) {
    return value;
  }
  const d = dayjs(value as string | number | Date);
  return d.isValid() ? d : undefined;
}

export interface CoerceAntdDateSchemaItem {
  fieldName?: string;
  /** 表单设计器里一般为组件名字符串，如 DatePicker */
  component?: unknown;
}

/**
 * 按 schema 组件类型，把 DatePicker / RangePicker / TimePicker 的值规范为 dayjs
 */
export function coerceAntdDatePickerFormValues(
  values: Record<string, any>,
  schema: CoerceAntdDateSchemaItem[] | undefined | null,
): Record<string, any> {
  if (!values || typeof values !== 'object' || !schema?.length) {
    return values;
  }
  const next = { ...values };
  for (const item of schema) {
    const name = item.fieldName;
    const comp = item.component;
    const compName = typeof comp === 'string' ? comp : '';
    if (!name || !compName || !ANTD_DATE_PICKER_COMPONENTS.has(compName)) {
      continue;
    }
    if (!Object.prototype.hasOwnProperty.call(next, name)) {
      continue;
    }
    const raw = next[name];
    if (raw === undefined) {
      continue;
    }
    if (raw === null) {
      continue;
    }
    if (compName === 'RangePicker') {
      if (Array.isArray(raw)) {
        next[name] = raw.map((cell) => {
          const d = parseToDayjs(cell);
          return d !== undefined ? d : cell;
        });
      } else {
        const d = parseToDayjs(raw);
        if (d !== undefined) {
          next[name] = d;
        }
      }
    } else {
      const d = parseToDayjs(raw);
      if (d !== undefined) {
        next[name] = d;
      }
    }
  }
  return next;
}
