import { createMiddleware } from "hono/factory";
import { sign, verify } from "hono/jwt";
import type { AppEnv, AuthUser } from "../env";
import { forbidden, unauthorized } from "./errors";

const ACCESS_TTL_S = 60 * 60; // 1 hour
const REFRESH_TTL_S = 60 * 60 * 24 * 30; // 30 days

type TokenType = "access" | "refresh";

export async function issueTokens(user: AuthUser, secret: string) {
  const iat = Math.floor(Date.now() / 1000);
  const accessToken = await sign({ sub: user.id, role: user.role, typ: "access", iat, exp: iat + ACCESS_TTL_S }, secret, "HS256");
  const refreshToken = await sign({ sub: user.id, role: user.role, typ: "refresh", iat, exp: iat + REFRESH_TTL_S }, secret, "HS256");
  return { access_token: accessToken, refresh_token: refreshToken, expires_in: ACCESS_TTL_S };
}

export async function verifyToken(token: string, secret: string, typ: TokenType): Promise<AuthUser> {
  let payload: Record<string, unknown>;
  try {
    payload = (await verify(token, secret, "HS256")) as Record<string, unknown>;
  } catch {
    throw unauthorized("Invalid or expired token");
  }
  if (payload.typ !== typ || typeof payload.sub !== "string") throw unauthorized("Invalid token");
  return { id: payload.sub, role: payload.role as AuthUser["role"] };
}

/** Requires a valid access token in the Authorization header (or `?token=` for WebSockets). */
export const requireAuth = createMiddleware<AppEnv>(async (c, next) => {
  const header = c.req.header("Authorization");
  const token = header?.startsWith("Bearer ") ? header.slice(7) : c.req.query("token");
  if (!token) throw unauthorized();
  c.set("user", await verifyToken(token, c.env.JWT_SECRET, "access"));
  await next();
});

export const requireRole = (...roles: AuthUser["role"][]) =>
  createMiddleware<AppEnv>(async (c, next) => {
    if (!roles.includes(c.get("user").role)) throw forbidden(`Requires role: ${roles.join(" or ")}`);
    await next();
  });
