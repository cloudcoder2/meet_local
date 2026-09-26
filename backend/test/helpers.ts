import { exports } from "cloudflare:workers";

export interface ApiResult<T = any> {
  status: number;
  body: T;
}

export async function api<T = any>(method: string, path: string, opts: { token?: string; body?: unknown } = {}): Promise<ApiResult<T>> {
  const headers: Record<string, string> = {};
  if (opts.token) headers.Authorization = `Bearer ${opts.token}`;
  if (opts.body !== undefined) headers["Content-Type"] = "application/json";
  const res = await exports.default.fetch(`https://api.cholo.test${path}`, {
    method,
    headers,
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

let phoneCounter = 0;

/** Logs in a fresh user through the OTP flow and returns their tokens and profile. */
export async function login(phone?: string) {
  phone ??= `+88017${String(10_000_000 + phoneCounter++).slice(-8)}`;
  const req = await api("POST", "/v1/auth/otp/request", { body: { phone } });
  const res = await api("POST", "/v1/auth/otp/verify", { body: { phone, code: req.body.dev_code } });
  if (res.status !== 200) throw new Error(`login failed: ${JSON.stringify(res.body)}`);
  return { token: res.body.access_token as string, refresh: res.body.refresh_token as string, user: res.body.user };
}
