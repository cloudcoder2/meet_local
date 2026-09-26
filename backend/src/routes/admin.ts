import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../env";
import { requireAuth, requireRole } from "../lib/auth";
import { conflict, notFound } from "../lib/errors";
import { normalizePromoCode } from "../lib/promo";
import { now, parseJson } from "../lib/util";
import { driverProfile, getDriver } from "./drivers";

export const admin = new Hono<AppEnv>();
admin.use("*", requireAuth, requireRole("admin"));

admin.get("/drivers", async (c) => {
  const status = c.req.query("status") ?? "pending";
  const { results } = await c.env.DB.prepare(
    "SELECT d.user_id, d.status, d.city, d.license_number, d.created_at, u.name, u.phone FROM drivers d JOIN users u ON u.id = d.user_id WHERE d.status = ? ORDER BY d.created_at LIMIT 100",
  )
    .bind(status)
    .all();
  return c.json({ drivers: results });
});

admin.patch("/drivers/:id", async (c) => {
  const { status } = await parseJson(c, z.object({ status: z.enum(["pending", "approved", "suspended"]) }));
  const id = c.req.param("id");
  const res = await c.env.DB.prepare("UPDATE drivers SET status = ?, updated_at = ? WHERE user_id = ?").bind(status, now(), id).run();
  if (!res.meta.changes) throw notFound("Driver not found");
  return c.json({ driver: await driverProfile(c.env.DB, (await getDriver(c.env.DB, id))!) });
});

admin.post("/promo-codes", async (c) => {
  const body = await parseJson(
    c,
    z
      .object({
        code: z.string().trim().min(3).max(30).regex(/^[A-Za-z0-9_-]+$/),
        description: z.string().max(200).optional(),
        percent_off: z.number().int().min(1).max(100).optional(),
        max_discount: z.number().int().positive().optional(),
        flat_off: z.number().int().positive().optional(),
        min_fare: z.number().int().min(0).default(0),
        max_uses: z.number().int().positive().optional(),
        per_user_limit: z.number().int().positive().default(1),
        starts_at: z.number().int().optional(),
        expires_at: z.number().int().optional(),
      })
      .refine((p) => p.percent_off || p.flat_off, "Either percent_off or flat_off is required"),
  );
  const code = normalizePromoCode(body.code);
  const res = await c.env.DB.prepare(
    `INSERT INTO promo_codes (code, description, percent_off, max_discount, flat_off, min_fare, max_uses, per_user_limit, starts_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(code) DO NOTHING`,
  )
    .bind(
      code,
      body.description ?? null,
      body.percent_off ?? null,
      body.max_discount ?? null,
      body.flat_off ?? null,
      body.min_fare,
      body.max_uses ?? null,
      body.per_user_limit,
      body.starts_at ?? null,
      body.expires_at ?? null,
    )
    .run();
  if (!res.meta.changes) throw conflict("Promo code already exists");
  return c.json({ promo_code: await c.env.DB.prepare("SELECT * FROM promo_codes WHERE code = ?").bind(code).first() }, 201);
});

admin.patch("/promo-codes/:code", async (c) => {
  const { is_active } = await parseJson(c, z.object({ is_active: z.boolean() }));
  const res = await c.env.DB.prepare("UPDATE promo_codes SET is_active = ? WHERE code = ?")
    .bind(is_active ? 1 : 0, normalizePromoCode(c.req.param("code")))
    .run();
  if (!res.meta.changes) throw notFound("Promo code not found");
  return c.json({ ok: true });
});
