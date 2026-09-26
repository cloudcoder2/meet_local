import { ApiError } from "./errors";
import { now } from "./util";

export interface PromoRow {
  code: string;
  description: string | null;
  percent_off: number | null;
  max_discount: number | null;
  flat_off: number | null;
  min_fare: number;
  max_uses: number | null;
  per_user_limit: number;
  used_count: number;
  starts_at: number | null;
  expires_at: number | null;
  is_active: number;
}

const invalid = (message: string) => new ApiError(400, "promo_invalid", message);

export function normalizePromoCode(code: string) {
  return code.trim().toUpperCase();
}

export async function loadPromo(db: D1Database, code: string, userId: string) {
  const promo = await db.prepare("SELECT * FROM promo_codes WHERE code = ?").bind(normalizePromoCode(code)).first<PromoRow>();
  const ts = now();
  if (!promo || !promo.is_active) throw invalid("Promo code not found");
  if (promo.starts_at && ts < promo.starts_at) throw invalid("Promo code is not active yet");
  if (promo.expires_at && ts > promo.expires_at) throw invalid("Promo code has expired");
  if (promo.max_uses !== null && promo.used_count >= promo.max_uses) throw invalid("Promo code has been fully redeemed");
  const { used } = (await db
    .prepare("SELECT COUNT(*) AS used FROM rides WHERE rider_id = ? AND promo_code = ? AND status NOT IN ('cancelled', 'no_driver')")
    .bind(userId, promo.code)
    .first<{ used: number }>())!;
  if (used >= promo.per_user_limit) throw invalid("You have already used this promo code");
  return promo;
}

/** Discount in paisa for `fare`; 0 if the fare is under the promo minimum. */
export function promoDiscount(promo: PromoRow, fare: number) {
  if (fare < promo.min_fare) return 0;
  let discount = 0;
  if (promo.percent_off) {
    discount = Math.round((fare * promo.percent_off) / 100);
    if (promo.max_discount !== null) discount = Math.min(discount, promo.max_discount);
  }
  if (promo.flat_off) discount = Math.max(discount, promo.flat_off);
  return Math.min(discount, fare);
}
