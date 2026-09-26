export interface Env {
  DB: D1Database;
  KV: KVNamespace;
  MEDIA: R2Bucket;
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
