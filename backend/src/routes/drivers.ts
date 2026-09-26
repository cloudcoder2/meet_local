import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../env";
import { issueTokens, requireAuth } from "../lib/auth";
import { dispatchHub, type Offer } from "../do/dispatch";
import { ApiError, conflict, forbidden, notFound } from "../lib/errors";
import { CITIES, cityFor } from "../lib/geo";
import { splitFare } from "../lib/pricing";
import { activeRideFor, type RideRow } from "../lib/rides";
import { latLngSchema, vehicleSchema } from "../lib/schemas";
import { getUser, serializeUser } from "../lib/users";
import { newId, now, parseJson } from "../lib/util";

export interface DriverRow {
  user_id: string;
  license_number: string;
  nid_number: string | null;
  status: "pending" | "approved" | "suspended";
  city: string;
  total_trips: number;
  total_earnings: number;
  created_at: number;
  updated_at: number;
}

export interface VehicleRow {
  id: string;
  driver_id: string;
  vehicle_class: "bike" | "cng" | "car";
  make: string;
  model: string;
  color: string;
  plate_number: string;
  is_active: number;
  created_at: number;
}

export const serializeVehicle = (v: VehicleRow) => ({
  id: v.id,
  vehicle_class: v.vehicle_class,
  make: v.make,
  model: v.model,
  color: v.color,
  plate_number: v.plate_number,
  is_active: !!v.is_active,
});

export async function getDriver(db: D1Database, userId: string) {
  return db.prepare("SELECT * FROM drivers WHERE user_id = ?").bind(userId).first<DriverRow>();
}

export async function getActiveVehicle(db: D1Database, driverId: string) {
  return db.prepare("SELECT * FROM vehicles WHERE driver_id = ? AND is_active = 1").bind(driverId).first<VehicleRow>();
}

export async function driverProfile(db: D1Database, driver: DriverRow) {
  const { results } = await db.prepare("SELECT * FROM vehicles WHERE driver_id = ? ORDER BY created_at").bind(driver.user_id).all<VehicleRow>();
  return {
    status: driver.status,
    city: driver.city,
    license_number: driver.license_number,
    total_trips: driver.total_trips,
    total_earnings: driver.total_earnings,
    vehicles: results.map(serializeVehicle),
  };
}

async function insertVehicle(db: D1Database, driverId: string, v: z.infer<typeof vehicleSchema>, active: boolean) {
  const taken = await db.prepare("SELECT 1 FROM vehicles WHERE plate_number = ?").bind(v.plate_number).first();
  if (taken) throw conflict("A vehicle with this plate number is already registered", "plate_taken");
  const id = newId();
  return db
    .prepare("INSERT INTO vehicles (id, driver_id, vehicle_class, make, model, color, plate_number, is_active, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)")
    .bind(id, driverId, v.vehicle_class, v.make, v.model, v.color, v.plate_number, active ? 1 : 0, now());
}

export const drivers = new Hono<AppEnv>();
drivers.use("*", requireAuth);

/** Registers the current user as a driver with their first vehicle. */
drivers.post("/", async (c) => {
  const body = await parseJson(
    c,
    z.object({
      license_number: z.string().trim().min(4).max(30),
      nid_number: z.string().trim().min(8).max(20).optional(),
      city: z.enum(CITIES.map((x) => x.id) as [string, ...string[]]).optional(),
      vehicle: vehicleSchema,
    }),
  );
  const userId = c.get("user").id;
  if (await getDriver(c.env.DB, userId)) throw conflict("You are already registered as a driver", "already_driver");
  const user = await getUser(c.env.DB, userId);
  if (!user) throw notFound("User not found");
  if (!user.name) throw forbidden("Set your name on your profile before registering as a driver");

  const ts = now();
  const status = c.env.DRIVER_AUTO_APPROVE === "true" ? "approved" : "pending";
  const vehicleInsert = await insertVehicle(c.env.DB, userId, body.vehicle, true);
  await c.env.DB.batch([
    c.env.DB.prepare("INSERT INTO drivers (user_id, license_number, nid_number, status, city, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)").bind(
      userId,
      body.license_number,
      body.nid_number ?? null,
      status,
      body.city ?? c.env.DEFAULT_CITY,
      ts,
      ts,
    ),
    vehicleInsert,
    c.env.DB.prepare("UPDATE users SET role = CASE WHEN role = 'admin' THEN role ELSE 'driver' END, updated_at = ? WHERE id = ?").bind(ts, userId),
  ]);

  const updated = (await getUser(c.env.DB, userId))!;
  const driver = (await getDriver(c.env.DB, userId))!;
  return c.json(
    {
      user: serializeUser(updated),
      driver: await driverProfile(c.env.DB, driver),
      // The role changed, so hand back tokens that carry it.
      ...(await issueTokens({ id: updated.id, role: updated.role }, c.env.JWT_SECRET)),
    },
    201,
  );
});

drivers.get("/me", async (c) => {
  const driver = await getDriver(c.env.DB, c.get("user").id);
  if (!driver) throw notFound("You are not registered as a driver");
  return c.json({ driver: await driverProfile(c.env.DB, driver) });
});

drivers.post("/me/vehicles", async (c) => {
  const body = await parseJson(c, vehicleSchema);
  const driverId = c.get("user").id;
  if (!(await getDriver(c.env.DB, driverId))) throw notFound("You are not registered as a driver");
  await (await insertVehicle(c.env.DB, driverId, body, false)).run();
  const driver = (await getDriver(c.env.DB, driverId))!;
  return c.json({ driver: await driverProfile(c.env.DB, driver) }, 201);
});

/** Makes the given vehicle the one used for new rides. */
drivers.post("/me/vehicles/:id/activate", async (c) => {
  const driverId = c.get("user").id;
  const vehicleId = c.req.param("id");
  const owned = await c.env.DB.prepare("SELECT 1 FROM vehicles WHERE id = ? AND driver_id = ?").bind(vehicleId, driverId).first();
  if (!owned) throw notFound("Vehicle not found");
  await c.env.DB.batch([
    c.env.DB.prepare("UPDATE vehicles SET is_active = 0 WHERE driver_id = ?").bind(driverId),
    c.env.DB.prepare("UPDATE vehicles SET is_active = 1 WHERE id = ?").bind(vehicleId),
  ]);
  const driver = (await getDriver(c.env.DB, driverId))!;
  return c.json({ driver: await driverProfile(c.env.DB, driver) });
});

// ---- presence and offers ------------------------------------------------------

const locationSchema = latLngSchema.extend({ heading: z.number().min(0).max(360).nullable().optional() });

async function requireApprovedDriver(db: D1Database, userId: string) {
  const driver = await getDriver(db, userId);
  if (!driver) throw notFound("You are not registered as a driver");
  if (driver.status !== "approved") throw forbidden(driver.status === "pending" ? "Your driver account is awaiting approval" : "Your driver account is suspended");
  return driver;
}

drivers.post("/me/online", async (c) => {
  const loc = await parseJson(c, locationSchema);
  const driverId = c.get("user").id;
  const driver = await requireApprovedDriver(c.env.DB, driverId);
  const vehicle = await getActiveVehicle(c.env.DB, driverId);
  if (!vehicle) throw forbidden("Activate a vehicle first");
  if (cityFor(loc)?.id !== driver.city) throw new ApiError(422, "out_of_service_area", `You can only go online inside ${driver.city}`);
  const active = await activeRideFor(c.env.DB, driverId);
  await dispatchHub(c.env, driver.city).goOnline({
    driverId,
    vehicleId: vehicle.id,
    vehicleClass: vehicle.vehicle_class,
    lat: loc.lat,
    lng: loc.lng,
    heading: loc.heading,
    rideId: active?.driver_id === driverId ? active.id : null,
  });
  return c.json({ online: true });
});

drivers.post("/me/offline", async (c) => {
  const driver = await requireApprovedDriver(c.env.DB, c.get("user").id);
  const res = await dispatchHub(c.env, driver.city).goOffline(driver.user_id);
  if (!res.ok) throw conflict("Finish your current trip before going offline", "on_trip");
  return c.json({ online: false });
});

drivers.post("/me/location", async (c) => {
  const loc = await parseJson(c, locationSchema);
  const driver = await requireApprovedDriver(c.env.DB, c.get("user").id);
  const ok = await dispatchHub(c.env, driver.city).updateLocation(driver.user_id, loc);
  if (!ok) throw conflict("You are offline; go online first", "offline");
  return c.json({ ok: true });
});

drivers.get("/me/status", async (c) => {
  const driver = await requireApprovedDriver(c.env.DB, c.get("user").id);
  const presence = await dispatchHub(c.env, driver.city).getPresence(driver.user_id);
  return c.json({ online: !!presence, ride_id: presence?.rideId ?? null, location: presence ? { lat: presence.lat, lng: presence.lng } : null });
});

/** The ride currently offered to this driver, with what they need to decide. */
drivers.get("/me/offer", async (c) => {
  const driver = await requireApprovedDriver(c.env.DB, c.get("user").id);
  const offer = await dispatchHub(c.env, driver.city).currentOffer(driver.user_id);
  if (!offer) return c.json({ offer: null });
  return c.json({ offer: await offerDetails(c.env.DB, offer, c.env.CURRENCY) });
});

export async function offerDetails(db: D1Database, offer: Offer, currency: string) {
  const ride = await db
    .prepare(
      `SELECT r.*, u.name AS rider_name, u.rating_sum, u.rating_count FROM rides r JOIN users u ON u.id = r.rider_id WHERE r.id = ?`,
    )
    .bind(offer.rideId)
    .first<RideRow & { rider_name: string | null; rating_sum: number; rating_count: number }>();
  if (!ride) return null;
  return {
    ride_id: ride.id,
    expires_at: offer.expiresAt,
    pickup_distance_m: offer.pickupDistanceM,
    vehicle_class: ride.vehicle_class,
    pickup: { lat: ride.pickup_lat, lng: ride.pickup_lng, address: ride.pickup_address },
    dropoff: { lat: ride.dropoff_lat, lng: ride.dropoff_lng, address: ride.dropoff_address },
    distance_m: ride.distance_m,
    duration_s: ride.duration_s,
    total: ride.estimated_fare - ride.discount,
    driver_earnings: splitFare(ride.estimated_fare - ride.discount).driverNet,
    currency,
    payment_method: ride.payment_method,
    rider: {
      name: ride.rider_name,
      rating: ride.rating_count ? Math.round((ride.rating_sum / ride.rating_count) * 100) / 100 : null,
    },
  };
}

drivers.get("/me/ws", async (c) => {
  if (c.req.header("Upgrade") !== "websocket") throw new ApiError(426, "upgrade_required", "Expected a WebSocket upgrade");
  const driver = await requireApprovedDriver(c.env.DB, c.get("user").id);
  const req = new Request(c.req.raw);
  req.headers.set("X-Driver-Id", driver.user_id);
  return dispatchHub(c.env, driver.city).fetch(req);
});

/** Earnings for today, the last 7 days and the last 30 days, plus a daily breakdown. */
drivers.get("/me/earnings", async (c) => {
  const driver = await requireApprovedDriver(c.env.DB, c.get("user").id);
  const tzOffsetMin = Number(c.req.query("tz_offset_min") ?? 360); // Asia/Dhaka is UTC+6.
  const day = 86_400_000;
  const offset = tzOffsetMin * 60_000;
  const startOfToday = Math.floor((now() + offset) / day) * day - offset;
  const since = startOfToday - 29 * day;
  const { results } = await c.env.DB.prepare(
    `SELECT r.completed_at AS at, p.amount, p.commission, p.driver_net FROM payments p JOIN rides r ON r.id = p.ride_id
     WHERE r.driver_id = ? AND r.completed_at >= ? ORDER BY r.completed_at`,
  )
    .bind(driver.user_id, since)
    .all<{ at: number; amount: number; commission: number; driver_net: number }>();

  const sum = (from: number) => {
    const rows = results.filter((r) => r.at >= from);
    return { trips: rows.length, gross: rows.reduce((a, r) => a + r.amount, 0), commission: rows.reduce((a, r) => a + r.commission, 0), net: rows.reduce((a, r) => a + r.driver_net, 0) };
  };
  const daily = Array.from({ length: 7 }, (_, i) => {
    const from = startOfToday - (6 - i) * day;
    const rows = results.filter((r) => r.at >= from && r.at < from + day);
    return { date: new Date(from + offset).toISOString().slice(0, 10), trips: rows.length, net: rows.reduce((a, r) => a + r.driver_net, 0) };
  });
  return c.json({
    currency: c.env.CURRENCY,
    today: sum(startOfToday),
    week: sum(startOfToday - 6 * day),
    month: sum(since),
    daily,
    lifetime: { trips: driver.total_trips, net: driver.total_earnings },
  });
});

/** Free drivers near a point, for the rider's home map. */
drivers.get("/nearby", async (c) => {
  const q = latLngSchema.parse({ lat: Number(c.req.query("lat")), lng: Number(c.req.query("lng")) });
  const city = cityFor(q);
  if (!city) return c.json({ drivers: [] });
  return c.json({ drivers: await dispatchHub(c.env, city.id).nearby(q) });
});
