import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../env";
import { issueTokens, verifyToken } from "../lib/auth";
import { ApiError, badRequest, tooMany, unauthorized } from "../lib/errors";
import { findOrCreateUserByPhone, getUser, serializeUser } from "../lib/users";
import { normalizePhone, parseJson, randomDigits } from "../lib/util";

const OTP_TTL_S = 300;
const OTP_MAX_ATTEMPTS = 5;
const OTP_REQUESTS_PER_WINDOW = 5;
const OTP_WINDOW_S = 600;

const phoneSchema = z.string().min(6).max(20);

function requirePhone(input: string) {
  const phone = normalizePhone(input);
  if (!phone) throw badRequest("Invalid phone number", "invalid_phone");
  return phone;
}

export const auth = new Hono<AppEnv>();

auth.post("/otp/request", async (c) => {
  const { phone: rawPhone } = await parseJson(c, z.object({ phone: phoneSchema }));
  const phone = requirePhone(rawPhone);

  const rlKey = `otp_rl:${phone}`;
  const count = Number((await c.env.KV.get(rlKey)) ?? 0);
  if (count >= OTP_REQUESTS_PER_WINDOW) throw tooMany("Too many code requests. Try again later.");
  await c.env.KV.put(rlKey, String(count + 1), { expirationTtl: OTP_WINDOW_S });

  const code = randomDigits(6);
  await c.env.KV.put(`otp:${phone}`, JSON.stringify({ code, attempts: 0 }), { expirationTtl: OTP_TTL_S });
  // TODO(sms): send `code` through an SMS provider in production.

  const isDev = c.env.APP_ENV !== "production";
  return c.json({ phone, expires_in: OTP_TTL_S, ...(isDev ? { dev_code: code } : {}) });
});

auth.post("/otp/verify", async (c) => {
  const body = await parseJson(c, z.object({ phone: phoneSchema, code: z.string().regex(/^\d{6}$/) }));
  const phone = requirePhone(body.phone);
  const key = `otp:${phone}`;
  const stored = await c.env.KV.get<{ code: string; attempts: number }>(key, "json");
  if (!stored) throw new ApiError(400, "otp_expired", "Code expired or not requested");
  if (stored.code !== body.code) {
    const attempts = stored.attempts + 1;
    if (attempts >= OTP_MAX_ATTEMPTS) await c.env.KV.delete(key);
    else await c.env.KV.put(key, JSON.stringify({ ...stored, attempts }), { expirationTtl: OTP_TTL_S });
    throw new ApiError(400, "otp_invalid", "Incorrect code");
  }
  await c.env.KV.delete(key);

  const { user, isNew } = await findOrCreateUserByPhone(c.env.DB, phone);
  const tokens = await issueTokens({ id: user.id, role: user.role }, c.env.JWT_SECRET);
  return c.json({ ...tokens, is_new_user: isNew, user: serializeUser(user) });
});

auth.post("/refresh", async (c) => {
  const { refresh_token } = await parseJson(c, z.object({ refresh_token: z.string().min(1) }));
  const claims = await verifyToken(refresh_token, c.env.JWT_SECRET, "refresh");
  // Re-read the user so role changes (e.g. becoming a driver) are picked up.
  const user = await getUser(c.env.DB, claims.id);
  if (!user) throw unauthorized("User no longer exists");
  return c.json(await issueTokens({ id: user.id, role: user.role }, c.env.JWT_SECRET));
});
