import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../env";
import { requireAuth } from "../lib/auth";
import { ApiError } from "../lib/errors";
import { cityFor, CITIES, type LatLng } from "../lib/geo";
import { computeFare, estimateTrip, TARIFFS, VEHICLE_CLASSES, type VehicleClass } from "../lib/pricing";
import { loadPromo, promoDiscount, type PromoRow } from "../lib/promo";
import { latLngSchema } from "../lib/schemas";
import { getSurge } from "../lib/surge";
import { parseJson } from "../lib/util";
import type { Env } from "../env";

const MIN_TRIP_M = 200;
const MAX_TRIP_M = 100_000;

/** Validates the trip and returns its city; throws if it is outside the service area. */
export function tripCity(pickup: LatLng, dropoff: LatLng) {
  const city = cityFor(pickup);
  if (!city) throw new ApiError(422, "out_of_service_area", "Cholo is not available at this pickup location yet");
  if (!cityFor(dropoff)) throw new ApiError(422, "out_of_service_area", "Drop-off is outside the service area");
  return city;
}

export async function quote(env: Env, pickup: LatLng, dropoff: LatLng, vehicleClass: VehicleClass, city: string, promo: PromoRow | null) {
  const { distanceM, durationS } = estimateTrip(pickup, dropoff, vehicleClass);
  if (distanceM < MIN_TRIP_M) throw new ApiError(422, "trip_too_short", "Pickup and drop-off are too close");
  if (distanceM > MAX_TRIP_M) throw new ApiError(422, "trip_too_long", "Trip is too long");
  const surge = await getSurge(env, city, vehicleClass);
  const fare = computeFare(vehicleClass, distanceM, durationS, surge);
  const discount = promo ? promoDiscount(promo, fare) : 0;
  return { vehicle_class: vehicleClass, distance_m: distanceM, duration_s: durationS, surge, fare, discount, total: fare - discount };
}

export const fares = new Hono<AppEnv>();

fares.get("/cities", (c) => c.json({ cities: CITIES.map(({ id, name, center }) => ({ id, name, center })) }));

fares.post("/fares/estimate", requireAuth, async (c) => {
  const body = await parseJson(c, z.object({ pickup: latLngSchema, dropoff: latLngSchema, promo_code: z.string().max(30).optional() }));
  const city = tripCity(body.pickup, body.dropoff);
  const promo = body.promo_code ? await loadPromo(c.env.DB, body.promo_code, c.get("user").id) : null;
  const options = await Promise.all(
    VEHICLE_CLASSES.map(async (vc) => ({
      ...(await quote(c.env, body.pickup, body.dropoff, vc, city.id, promo)),
      label: TARIFFS[vc].label,
      seats: TARIFFS[vc].seats,
    })),
  );
  return c.json({ city: city.id, currency: c.env.CURRENCY, promo_code: promo?.code ?? null, options });
});
