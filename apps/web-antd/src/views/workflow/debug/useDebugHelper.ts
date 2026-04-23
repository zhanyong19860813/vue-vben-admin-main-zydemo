import { ref } from 'vue';

export interface UseDebugHelperOptions {
  maxEvents?: number;
  enabled?: boolean;
}

function toText(v: unknown): string {
  if (v === null) return 'null';
  if (v === undefined) return '∅';
  if (typeof v === 'string') return v;
  if (typeof v === 'number' || typeof v === 'boolean' || typeof v === 'bigint') {
    return String(v);
  }
  try {
    return JSON.stringify(v);
  } catch {
    return String(v);
  }
}

export function formatDebugLine(label: string, payload: Record<string, unknown>): string {
  const parts = Object.entries(payload).map(([k, v]) => `${k}=${toText(v)}`);
  return `${label} ${parts.join(', ')}`;
}

export function useDebugHelper(options?: UseDebugHelperOptions) {
  const maxEvents = Math.max(1, options?.maxEvents ?? 10);
  const enabled = options?.enabled ?? true;
  const events = ref<string[]>([]);

  function push(msg: string) {
    if (!enabled) return;
    const ts = new Date().toLocaleTimeString();
    events.value = [`[${ts}] ${msg}`, ...events.value].slice(0, maxEvents);
  }

  function clear() {
    events.value = [];
  }

  return {
    events,
    push,
    clear,
  };
}

