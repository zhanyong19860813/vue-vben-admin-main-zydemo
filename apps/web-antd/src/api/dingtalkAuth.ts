import { requestClient } from '#/api/request';
import { backendApi } from '#/api/constants';

export interface DingH5Config {
  corpId: string;
  agentId: string;
  timeStamp: string;
  nonceStr: string;
  url: string;
  signature: string;
}

export interface DingLoginResult {
  accessToken: string;
  user: {
    userId: string;
    username: string;
    employeeId: string;
    name?: string;
    dingUserId?: string;
  };
}

export async function getDingH5Config(url: string) {
  return requestClient.get<{ code: number; data: DingH5Config; message?: string }>(
    backendApi('DingTalkAuth/h5-config'),
    { params: { url } },
  );
}

export async function dingLoginByCode(code: string) {
  return requestClient.post<{ code: number; data: DingLoginResult; message?: string }>(
    backendApi('DingTalkAuth/login-by-code'),
    { code },
  );
}

export async function dingDemoLoginByUserId(userId: string) {
  return requestClient.post<{ code: number; data: DingLoginResult; message?: string }>(
    backendApi('DingTalkAuth/demo-login-by-userid'),
    { userId },
  );
}

