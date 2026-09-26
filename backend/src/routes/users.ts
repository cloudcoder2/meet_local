import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../env";
import { requireAuth } from "../lib/auth";
import { badRequest, notFound } from "../lib/errors";
import { getUser, serializeUser } from "../lib/users";
import { newId, now, parseJson } from "../lib/util";

const MAX_AVATAR_BYTES = 2 * 1024 * 1024;
const AVATAR_TYPES = ["image/jpeg", "image/png", "image/webp"];

export const users = new Hono<AppEnv>();

users.get("/users/:id/avatar", async (c) => {
  const user = await getUser(c.env.DB, c.req.param("id"));
  if (!user?.avatar_key) throw notFound();
  const obj = await c.env.MEDIA.get(user.avatar_key);
  if (!obj) throw notFound();
  return new Response(obj.body, {
    headers: {
      "Content-Type": obj.httpMetadata?.contentType ?? "application/octet-stream",
      "Cache-Control": "public, max-age=300",
    },
  });
});

users.use("/me", requireAuth);
users.use("/me/*", requireAuth);

users.get("/me", async (c) => {
  const user = await getUser(c.env.DB, c.get("user").id);
  if (!user) throw notFound("User not found");
  return c.json({ user: serializeUser(user) });
});

users.patch("/me", async (c) => {
  const body = await parseJson(
    c,
    z.object({
      name: z.string().trim().min(1).max(80).optional(),
      email: z.email().max(254).nullable().optional(),
    }),
  );
  const id = c.get("user").id;
  const user = await c.env.DB.prepare(
    "UPDATE users SET name = COALESCE(?, name), email = CASE WHEN ? THEN ? ELSE email END, updated_at = ? WHERE id = ? RETURNING *",
  )
    .bind(body.name ?? null, body.email !== undefined ? 1 : 0, body.email ?? null, now(), id)
    .first();
  if (!user) throw notFound("User not found");
  return c.json({ user: serializeUser(user as never) });
});

users.put("/me/avatar", async (c) => {
  const type = c.req.header("Content-Type")?.split(";")[0] ?? "";
  if (!AVATAR_TYPES.includes(type)) throw badRequest("Avatar must be JPEG, PNG or WebP");
  const data = await c.req.arrayBuffer();
  if (data.byteLength === 0 || data.byteLength > MAX_AVATAR_BYTES) throw badRequest("Avatar must be between 1 byte and 2 MB");
  const id = c.get("user").id;
  const key = `avatars/${id}/${newId()}`;
  await c.env.MEDIA.put(key, data, { httpMetadata: { contentType: type } });
  const old = await getUser(c.env.DB, id);
  await c.env.DB.prepare("UPDATE users SET avatar_key = ?, updated_at = ? WHERE id = ?").bind(key, now(), id).run();
  if (old?.avatar_key) await c.env.MEDIA.delete(old.avatar_key);
  return c.json({ user: serializeUser((await getUser(c.env.DB, id))!) });
});

const placeSchema = z.object({
  label: z.string().trim().min(1).max(40),
  address: z.string().trim().min(1).max(200),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
});

users.get("/me/places", async (c) => {
  const { results } = await c.env.DB.prepare(
    "SELECT id, label, address, lat, lng, created_at FROM saved_places WHERE user_id = ? ORDER BY created_at",
  )
    .bind(c.get("user").id)
    .all();
  return c.json({ places: results });
});

users.post("/me/places", async (c) => {
  const body = await parseJson(c, placeSchema);
  const userId = c.get("user").id;
  const { count } = (await c.env.DB.prepare("SELECT COUNT(*) AS count FROM saved_places WHERE user_id = ?").bind(userId).first<{ count: number }>())!;
  if (count >= 20) throw badRequest("You can save up to 20 places");
  const place = { id: newId(), ...body, created_at: now() };
  await c.env.DB.prepare("INSERT INTO saved_places (id, user_id, label, address, lat, lng, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)")
    .bind(place.id, userId, place.label, place.address, place.lat, place.lng, place.created_at)
    .run();
  return c.json({ place }, 201);
});

users.delete("/me/places/:id", async (c) => {
  const res = await c.env.DB.prepare("DELETE FROM saved_places WHERE id = ? AND user_id = ?").bind(c.req.param("id"), c.get("user").id).run();
  if (!res.meta.changes) throw notFound("Place not found");
  return c.body(null, 204);
});
