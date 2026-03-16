/**
 * 操作日志 - 前端上报菜单/按钮点击
 */
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

/** 记录操作日志（静默失败，不影响业务） */
export async function recordOperationLog(params: {
  actionType: 'menu_click' | 'button_click';
  target?: string;
  description?: string;
  requestParams?: string;
}): Promise<void> {
  try {
    await requestClient.post(backendApi('OperationLog/Record'), {
      actionType: params.actionType,
      target: params.target,
      description: params.description,
      requestParams: params.requestParams,
    });
  } catch {
    // 静默失败，如未登录、网络错误等
  }
}
