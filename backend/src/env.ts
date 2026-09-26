export interface Env {
  DB: D1Database;
  KV: KVNamespace;
  MEDIA: R2Bucket;
  JWT_SECRET: string;
  APP_ENV: string;
  CURRENCY: string;
  DEFAULT_CITY: string;
}

export interface AuthUser {
  id: string;
  role: "rider" | "driver" | "admin";
}

export type AppEnv = { Bindings: Env; Variables: { user: AuthUser } };
