import { Hono } from "hono";
import { z } from "zod";
import { dispatchHub } from "../do/dispatch";
import type { AppEnv, Env } from "../env";
import { requireAuth } from "../lib/auth";
import { ApiError, conflict, forbidden } from "../lib/errors";
import { loadPromo } from "../lib/promo";
import { activeRideFor, getRideFor, logRideEvent, requireViewer, transition, type RideRow, type Viewer } from "../lib/rides";
import { placeSchema, vehicleClassSchema } from "../lib/schemas";
import { getUser, serializeUser } from "../lib/users";
import { newId, now, parseJson, randomDigits } from "../lib/util";
import { getActiveVehicle, getDriver, serializeVehicle, type VehicleRow } from "./drivers";
import { quote, tripCity } from "./fares";

async function serializeRide(env: Env, ride: RideRow, as: Viewer) {
  const base = {
    id: ride.id,
    status: ride.status,
    city: ride.city,
    vehicle_class: ride.vehicle_class,
    pickup: { lat: ride.pickup_lat, lng: ride.pickup_lng, address: ride.pickup_address },
    dropoff: { lat: ride.dropoff_lat, lng: ride.dropoff_lng, address: ride.dropoff_address },
    distance_m: ride.distance_m,
    duration_s: ride.duration_s,
    surge: ride.surge,
    fare: ride.estimated_fare,
    discount: ride.discount,
    total: ride.final_fare ?? ride.estimated_fare - ride.discount,
    currency: env.CURRENCY,
    promo_code: ride.promo_code,
    payment_method: ride.payment_method,
    cancelled_by: ride.cancelled_by,
    cancel_reason: ride.cancel_reason,
    requested_at: ride.requested_at,
    accepted_at: ride.accepted_at,
    started_at: ride.started_at,
    completed_at: ride.completed_at,
    cancelled_at: ride.cancelled_at,
    // Riders read the start code out to the driver, who types it in to start the trip.
    otp: as === "rider" && ["accepted", "arrived"].includes(ride.status) ? ride.otp : null,
  };

  const counterpartId = as === "rider" ? ride.driver_id : ride.rider_id;
  const counterpart = counterpartId ? await getUser(env.DB, counterpartId) : null;
  const person = counterpart ? (({ id, name, phone, avatar_url, rating, rating_count }) => ({ id, name, phone, avatar_url, rating, rating_count }))(serializeUser(counterpart)) : null;

  let vehicle = null;
  if (ride.vehicle_id) {
    const v = await env.DB.prepare("SELECT * FROM vehicles WHERE id = ?").bind(ride.vehicle_id).first<VehicleRow>();
    vehicle = v ? serializeVehicle(v) : null;
  }

  return { ...base, viewer: as, driver: as === "rider" ? person : null, rider: as === "driver" ? person : null, vehicle };
}

export const rides = new Hono<AppEnv>();
rides.use("*", requireAuth);

rides.post("/", async (c) => {
  const body = await parseJson(
    c,
    z.object({
      pickup: placeSchema,
      dropoff: placeSchema,
      vehicle_class: vehicleClassSchema,
      promo_code: z.string().max(30).optional(),
      payment_method: z.enum(["cash", "wallet", "card", "bkash"]).default("cash"),
    }),
  );
  const riderId = c.get("user").id;
  if (body.payment_method !== "cash") throw new ApiError(422, "payment_method_unavailable", "Only cash payments are supported right now");
  if (await activeRideFor(c.env.DB, riderId)) throw conflict("You already have an active ride", "ride_in_progress");

  const city = tripCity(body.pickup, body.dropoff);
  const promo = body.promo_code ? await loadPromo(c.env.DB, body.promo_code, riderId) : null;
  const q = await quote(c.env, body.pickup, body.dropoff, body.vehicle_class, city.id, promo);

  const id = newId();
  const ts = now();
  const ride = await c.env.DB.prepare(
    `INSERT INTO rides (id, rider_id, vehicle_class, city, status, pickup_lat, pickup_lng, pickup_address, dropoff_lat, dropoff_lng,
       dropoff_address, distance_m, duration_s, surge, estimated_fare, discount, promo_code, payment_method, otp, requested_at)
     VALUES (?, ?, ?, ?, 'requested', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *`,
  )
    .bind(
      id,
      riderId,
      body.vehicle_class,
      city.id,
      body.pickup.lat,
      body.pickup.lng,
      body.pickup.address,
      body.dropoff.lat,
      body.dropoff.lng,
      body.dropoff.address,
      q.distance_m,
      q.duration_s,
      q.surge,
      q.fare,
      q.discount,
      promo?.code ?? null,
      body.payment_method,
      randomDigits(4),
      ts,
    )
    .first<RideRow>();
  await logRideEvent(c.env.DB, id, "requested", riderId);
  await dispatchHub(c.env, city.id).requestRide({ rideId: id, riderId, pickup: body.pickup, vehicleClass: body.vehicle_class });
  return c.json({ ride: await serializeRide(c.env, ride!, "rider") }, 201);
});

rides.get("/", async (c) => {
  const role = c.req.query("role") === "driver" ? "driver" : "rider";
  const limit = Math.min(Number(c.req.query("limit") ?? 20) || 20, 50);
  const before = Number(c.req.query("before") ?? Number.MAX_SAFE_INTEGER);
  const col = role === "driver" ? "driver_id" : "rider_id";
  const { results } = await c.env.DB.prepare(`SELECT * FROM rides WHERE ${col} = ? AND requested_at < ? ORDER BY requested_at DESC LIMIT ?`)
    .bind(c.get("user").id, before, limit)
    .all<RideRow>();
  const items = await Promise.all(results.map((r) => serializeRide(c.env, r, role)));
  return c.json({ rides: items, next_before: results.length === limit ? results[results.length - 1].requested_at : null });
});

rides.get("/active", async (c) => {
  const userId = c.get("user").id;
  const ride = await activeRideFor(c.env.DB, userId);
  return c.json({ ride: ride ? await serializeRide(c.env, ride, ride.rider_id === userId ? "rider" : "driver") : null });
});

rides.get("/:id", async (c) => {
  const { ride, as } = await getRideFor(c.env.DB, c.req.param("id"), c.get("user").id);
  return c.json({ ride: await serializeRide(c.env, ride, as) });
});

rides.post("/:id/cancel", async (c) => {
  const { reason } = await parseJson(c, z.object({ reason: z.string().trim().max(200).optional() }));
  const userId = c.get("user").id;
  const { ride, as } = await getRideFor(c.env.DB, c.req.param("id"), userId);
  const from = as === "rider" ? (["requested", "accepted", "arrived"] as const) : (["accepted", "arrived"] as const);
  const updated = await transition(c.env, ride, [...from], "cancelled", userId, {
    cancelled_by: as,
    cancel_reason: reason ?? null,
    cancelled_at: now(),
  });
  const hub = dispatchHub(c.env, ride.city);
  if (ride.status === "requested") await hub.cancelSearch(ride.id);
  if (ride.driver_id) await hub.releaseDriver(ride.driver_id, ride.id);
  return c.json({ ride: await serializeRide(c.env, updated, as) });
});

// ---- driver actions ---------------------------------------------------------

rides.post("/:id/accept", async (c) => {
  const driverId = c.get("user").id;
  const driver = await getDriver(c.env.DB, driverId);
  if (!driver || driver.status !== "approved") throw forbidden("Only approved drivers can accept rides");
  const vehicle = await getActiveVehicle(c.env.DB, driverId);
  if (!vehicle) throw forbidden("Activate a vehicle first");

  const rideId = c.req.param("id");
  const ride = await c.env.DB.prepare("SELECT * FROM rides WHERE id = ?").bind(rideId).first<RideRow>();
  if (!ride || ride.status !== "requested") throw new ApiError(409, "offer_unavailable", "This ride is no longer available");

  const hub = dispatchHub(c.env, ride.city);
  const result = await hub.acceptOffer(rideId, driverId);
  if (!result.ok) throw new ApiError(409, "offer_unavailable", result.reason === "expired" ? "The offer expired" : "This ride was not offered to you");

  try {
    const updated = await transition(c.env, ride, ["requested"], "accepted", driverId, {
      driver_id: driverId,
      vehicle_id: vehicle.id,
      accepted_at: now(),
    });
    return c.json({ ride: await serializeRide(c.env, updated, "driver") });
  } catch (err) {
    // The rider cancelled between the offer being accepted and the ride updating.
    await hub.releaseDriver(driverId, rideId);
    throw err;
  }
});

rides.post("/:id/decline", async (c) => {
  const driverId = c.get("user").id;
  const ride = await c.env.DB.prepare("SELECT id, city FROM rides WHERE id = ?").bind(c.req.param("id")).first<{ id: string; city: string }>();
  if (!ride) throw new ApiError(404, "not_found", "Ride not found");
  const ok = await dispatchHub(c.env, ride.city).declineOffer(ride.id, driverId);
  if (!ok) throw new ApiError(409, "offer_unavailable", "This ride was not offered to you");
  await logRideEvent(c.env.DB, ride.id, "declined", driverId);
  return c.body(null, 204);
});

rides.post("/:id/arrived", async (c) => {
  const userId = c.get("user").id;
  const { ride, as } = await getRideFor(c.env.DB, c.req.param("id"), userId);
  requireViewer(as, "driver");
  const updated = await transition(c.env, ride, ["accepted"], "arrived", userId);
  return c.json({ ride: await serializeRide(c.env, updated, as) });
});

rides.post("/:id/start", async (c) => {
  const { otp } = await parseJson(c, z.object({ otp: z.string().regex(/^\d{4}$/) }));
  const userId = c.get("user").id;
  const { ride, as } = await getRideFor(c.env.DB, c.req.param("id"), userId);
  requireViewer(as, "driver");
  if (ride.status === "accepted" || ride.status === "arrived") {
    if (otp !== ride.otp) throw new ApiError(400, "otp_invalid", "Incorrect ride code");
  }
  const updated = await transition(c.env, ride, ["accepted", "arrived"], "in_progress", userId, { started_at: now() });
  return c.json({ ride: await serializeRide(c.env, updated, as) });
});

rides.post("/:id/complete", async (c) => {
  const userId = c.get("user").id;
  const { ride, as } = await getRideFor(c.env.DB, c.req.param("id"), userId);
  requireViewer(as, "driver");
  // Upfront pricing: the rider pays the quoted total.
  const total = ride.estimated_fare - ride.discount;
  const updated = await transition(c.env, ride, ["in_progress"], "completed", userId, { final_fare: total, completed_at: now() });
  await c.env.DB.batch([
    c.env.DB.prepare("UPDATE drivers SET total_trips = total_trips + 1, updated_at = ? WHERE user_id = ?").bind(now(), userId),
    ...(ride.promo_code ? [c.env.DB.prepare("UPDATE promo_codes SET used_count = used_count + 1 WHERE code = ?").bind(ride.promo_code)] : []),
  ]);
  await dispatchHub(c.env, ride.city).releaseDriver(userId, ride.id);
  return c.json({ ride: await serializeRide(c.env, updated, as) });
});
