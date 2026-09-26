import { newId, now } from "./util";

export interface UserRow {
  id: string;
  phone: string;
  name: string | null;
  email: string | null;
  avatar_key: string | null;
  role: "rider" | "driver" | "admin";
  rating_sum: number;
  rating_count: number;
  created_at: number;
  updated_at: number;
}

export function serializeUser(u: UserRow) {
  return {
    id: u.id,
    phone: u.phone,
    name: u.name,
    email: u.email,
    avatar_url: u.avatar_key ? `/v1/users/${u.id}/avatar` : null,
    role: u.role,
    rating: u.rating_count ? Math.round((u.rating_sum / u.rating_count) * 100) / 100 : null,
    rating_count: u.rating_count,
    created_at: u.created_at,
  };
}

export async function getUser(db: D1Database, id: string) {
  return db.prepare("SELECT * FROM users WHERE id = ?").bind(id).first<UserRow>();
}

/** Returns the user for `phone`, creating one if it doesn't exist yet. */
export async function findOrCreateUserByPhone(db: D1Database, phone: string) {
  const existing = await db.prepare("SELECT * FROM users WHERE phone = ?").bind(phone).first<UserRow>();
  if (existing) return { user: existing, isNew: false };
  const ts = now();
  const user = await db
    .prepare("INSERT INTO users (id, phone, created_at, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(phone) DO UPDATE SET phone = excluded.phone RETURNING *")
    .bind(newId(), phone, ts, ts)
    .first<UserRow>();
  return { user: user!, isNew: true };
}
