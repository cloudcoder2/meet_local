import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../env";
import { issueTokens, requireAuth } from "../lib/auth";
import { conflict, forbidden, notFound } from "../lib/errors";
import { CITIES } from "../lib/geo";
import { vehicleSchema } from "../lib/schemas";
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
