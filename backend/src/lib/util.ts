import type { Context } from "hono";
import type { z } from "zod";
import { badRequest } from "./errors";

export const now = () => Date.now();
export const newId = () => crypto.randomUUID();

export async function parseJson<T extends z.ZodType>(c: Context, schema: T): Promise<z.infer<T>> {
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    throw badRequest("Request body must be valid JSON");
  }
  return schema.parse(body);
}

/** Cryptographically random numeric code of the given length. */
export function randomDigits(length: number): string {
  const bytes = crypto.getRandomValues(new Uint32Array(length));
  return Array.from(bytes, (b) => (b % 10).toString()).join("");
}

/**
 * Normalizes a phone number to E.164. Bangladeshi local formats (01XXXXXXXXX,
 * 8801XXXXXXXXX) are accepted; other numbers must already include a + prefix.
 */
export function normalizePhone(input: string): string | null {
  const raw = input.replace(/[\s\-()]/g, "");
  let phone: string;
  if (/^01[3-9]\d{8}$/.test(raw)) phone = `+88${raw}`;
  else if (/^8801[3-9]\d{8}$/.test(raw)) phone = `+${raw}`;
  else phone = raw;
  return /^\+[1-9]\d{7,14}$/.test(phone) ? phone : null;
}
