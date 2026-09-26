import { runInDurableObject } from "cloudflare:test";
import { env, exports } from "cloudflare:workers";

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

export const ADMIN_PHONE = "+8801900000000";

let adminSession: Promise<Awaited<ReturnType<typeof login>>> | undefined;

/** Logs in the admin once per test file; logging in repeatedly would trip the OTP rate limit. */
export const loginAdmin = () => (adminSession ??= login(ADMIN_PHONE));

let plateCounter = 0;

export const GULSHAN = { lat: 23.7925, lng: 90.4078 };
export const DHANMONDI = { lat: 23.7461, lng: 90.3742 };

/** Registers and approves a driver with one vehicle of the given class. */
export async function makeDriver(vehicleClass: "bike" | "cng" | "car" = "car", name = "Karim") {
  const session = await login();
  await api("PATCH", "/v1/me", { token: session.token, body: { name } });
  const reg = await api("POST", "/v1/drivers", {
    token: session.token,
    body: {
      license_number: "DK-0123456",
      vehicle: { vehicle_class: vehicleClass, make: "Toyota", model: "Axio", color: "White", plate_number: `DHAKA-GA-${10_000 + plateCounter++}` },
    },
  });
  if (reg.status !== 201) throw new Error(`driver registration failed: ${JSON.stringify(reg.body)}`);
  const adminSession = await loginAdmin();
  await api("PATCH", `/v1/admin/drivers/${session.user.id}`, { token: adminSession.token, body: { status: "approved" } });
  return { ...session, token: reg.body.access_token as string, user: reg.body.user, vehicle: reg.body.driver.vehicles[0] };
}

export function hub(city = "dhaka") {
  return env.DISPATCH.get(env.DISPATCH.idFromName(city));
}

// runInDurableObject's generics recurse too deeply on the RPC stub type.
const runInDO = runInDurableObject as unknown as (
  stub: unknown,
  fn: (instance: any, state: DurableObjectState) => Promise<void>,
) => Promise<void>;

/** Clears all dispatch state so tests don't see each other's drivers and searches. */
export async function resetHub(city = "dhaka") {
  await runInDO(hub(city), async (instance, state) => {
    instance.drivers.clear();
    instance.searches.clear();
    await state.storage.deleteAlarm();
    await state.storage.deleteAll();
  });
}

/** Moves a hub's clock-based state into the past so the next alarm treats it as expired. */
export async function ageHub(ms: number, city = "dhaka") {
  await runInDO(hub(city), async (instance) => {
    for (const s of instance.searches.values()) {
      s.startedAt -= ms;
      s.nextAttemptAt -= ms;
      if (s.offer) s.offer.expiresAt -= ms;
    }
  });
}

export const place = (p: { lat: number; lng: number }, address: string) => ({ ...p, address });

export async function requestRide(token: string, vehicleClass: "bike" | "cng" | "car" = "car") {
  return api("POST", "/v1/rides", {
    token,
    body: { pickup: place(GULSHAN, "Gulshan 1, Dhaka"), dropoff: place(DHANMONDI, "Dhanmondi 27, Dhaka"), vehicle_class: vehicleClass },
  });
}

/** Opens a WebSocket to the API and collects its JSON messages. */
export async function connect(path: string, token: string) {
  const res = await exports.default.fetch(`https://api.cholo.test${path}${path.includes("?") ? "&" : "?"}token=${token}`, {
    headers: { Upgrade: "websocket" },
  });
  const ws = res.webSocket;
  if (!ws) throw new Error(`WebSocket upgrade failed: ${res.status} ${await res.text()}`);
  ws.accept();
  const messages: any[] = [];
  const waiters: { type: string; resolve: (m: any) => void }[] = [];
  let closed = false;
  ws.addEventListener("message", (e) => {
    const msg = JSON.parse(e.data as string);
    const i = waiters.findIndex((w) => w.type === msg.type);
    if (i >= 0) waiters.splice(i, 1)[0].resolve(msg);
    else messages.push(msg);
  });
  ws.addEventListener("close", () => (closed = true));
  return {
    ws,
    send: (msg: unknown) => ws.send(JSON.stringify(msg)),
    /** Resolves with the next message of `type` (including one already received). */
    next(type: string, timeoutMs = 2000): Promise<any> {
      const i = messages.findIndex((m) => m.type === type);
      if (i >= 0) return Promise.resolve(messages.splice(i, 1)[0]);
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error(`timed out waiting for ${type}`)), timeoutMs);
        waiters.push({ type, resolve: (m) => (clearTimeout(timer), resolve(m)) });
      });
    },
    get closed() {
      return closed;
    },
  };
}

/** Runs `fn` against the city's DispatchHub instance. */
export const runInHub = (fn: (instance: any) => Promise<void> | void, city = "dhaka") => runInDO(hub(city), async (i) => fn(i));
