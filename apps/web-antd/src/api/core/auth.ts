import { baseRequestClient, requestClient } from '#/api/request';

export namespace AuthApi {
  /** 登录接口参数 */
  export interface LoginParams {
    password?: string;
    username?: string;
  }

  /** 登录接口返回值 */
  export interface LoginResult {
    accessToken: string;
  }

  export interface RefreshTokenResult {
    data: string;
    status: number;
  }

   /** 登录接口参数 */
  export interface LoginParamsFromDb {
    password?: string;
    username?: string;
    employee_id?: string;
  }

}

/**
 * 登录
 */
export async function loginApi(data: AuthApi.LoginParams) {
  return requestClient.post<AuthApi.LoginResult>('/auth/login', data);
}


 

/**
 * 登录请求后台登录接口 add by zhanyong begin
 */
// export async function loginApiFromDb(data: AuthApi.LoginParamsFromDb) {

//   console.log("api调用loginApiFromDb 参数:",data);
//   const res = await requestClient.post('http://localhost:5155/api/Auth/jwtlogin', data);

//   console.log("api调用loginApiFromDb 返回res:",res);
//    return {
//     accessToken: res.accessToken,
//   };
// }

export async function loginApiFromDb(data: AuthApi.LoginParamsFromDb) {
   console.log("api调用loginApiFromDb 参数:",data);
  const res = await requestClient.post('http://localhost:5155/api/Auth/jwtlogin', data);
  console.log("api调用loginApiFromDb 返回res:",res);
  return {
    accessToken: res.accessToken,
  };
}


export async function refreshTokenApiFormDb() {
  return baseRequestClient.post<AuthApi.RefreshTokenResult>('/auth/refresh', {
    withCredentials: true,
  });
}


/**
 * 登录请求后台登录接口 add by zhanyong end 
 */


/**
 * 刷新accessToken
 */
export async function refreshTokenApi() {
  return baseRequestClient.post<AuthApi.RefreshTokenResult>('/auth/refresh', {
    withCredentials: true,
  });
}

/**
 * 退出登录
 */
export async function logoutApi() {
  return baseRequestClient.post('/auth/logout', {
    withCredentials: true,
  });
}

/**
 * 获取用户权限码
 */
export async function getAccessCodesApi() {
  return requestClient.get<string[]>('/auth/codes');
}
