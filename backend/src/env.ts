import type { DispatchHub } from "./do/dispatch";
import type { RideRoom } from "./do/ride-room";

export interface Env {
  DB: D1Database;
  DISPATCH: DurableObjectNamespace<DispatchHub>;
  RIDE_ROOM: DurableObjectNamespace<RideRoom>;
  KV: KVNamespace;
  MEDIA: R2Bucket;
  /** Per-IP limit on login endpoints. */
  AUTH_LIMITER: RateLimit;
  /** Per-user limit on authenticated API calls. */
  API_LIMITER: RateLimit;
  JWT_SECRET: string;
  APP_ENV: string;
  CURRENCY: string;
  DEFAULT_CITY: string;
  /** Comma-separated phone numbers (E.164) that are granted the admin role on login. */
  ADMIN_PHONES: string;
  /** "true" to approve new drivers immediately (development only). */
  DRIVER_AUTO_APPROVE: string;
}

export interface AuthUser {
  id: string;
  role: "rider" | "driver" | "admin";
}

export type AppEnv = { Bindings: Env; Variables: { user: AuthUser } };
