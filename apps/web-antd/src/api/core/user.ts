import type { UserInfo } from '@vben/types';

import { requestClient } from '#/api/request';

/**
 * 获取用户信息
 */
export async function getUserInfoApi() {
  return requestClient.get<UserInfo>('/user/info');
}



/**
 * 获取用户信息  2026.01.20 add by zhanyong begin
 */
export async function getUserInfoApiFromDb() {
  const res = await requestClient.get<UserInfo>('http://localhost:5155/api/User/info');

  console.log("api调用getUserInfoApiFromDb 返回res:",res);


  return res;
}
/**
 * 获取用户信息  2026.01.20 add by zhanyong  end
 */
