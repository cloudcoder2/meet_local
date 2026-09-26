import type { Env } from "../env";
import { ApiError, conflict, forbidden, notFound } from "./errors";
import { publishRideUpdate } from "./realtime";
import { now } from "./util";

export const RIDE_STATUSES = ["requested", "accepted", "arrived", "in_progress", "completed", "cancelled", "no_driver"] as const;
export type RideStatus = (typeof RIDE_STATUSES)[number];
export const ACTIVE_STATUSES: RideStatus[] = ["requested", "accepted", "arrived", "in_progress"];

export interface RideRow {
  id: string;
  rider_id: string;
  driver_id: string | null;
  vehicle_id: string | null;
  vehicle_class: "bike" | "cng" | "car";
  city: string;
  status: RideStatus;
  pickup_lat: number;
  pickup_lng: number;
  pickup_address: string;
  dropoff_lat: number;
  dropoff_lng: number;
  dropoff_address: string;
  distance_m: number;
  duration_s: number;
  surge: number;
  estimated_fare: number;
  discount: number;
  final_fare: number | null;
  promo_code: string | null;
  payment_method: "cash" | "wallet" | "card" | "bkash";
  otp: string;
  cancelled_by: string | null;
  cancel_reason: string | null;
  requested_at: number;
  accepted_at: number | null;
  started_at: number | null;
  completed_at: number | null;
  cancelled_at: number | null;
}

export async function getRide(db: D1Database, id: string) {
  return db.prepare("SELECT * FROM rides WHERE id = ?").bind(id).first<RideRow>();
}

export type Viewer = "rider" | "driver";

/** Loads a ride and checks the user takes part in it. */
export async function getRideFor(db: D1Database, id: string, userId: string): Promise<{ ride: RideRow; as: Viewer }> {
  const ride = await getRide(db, id);
  if (!ride) throw notFound("Ride not found");
  if (ride.rider_id === userId) return { ride, as: "rider" };
  if (ride.driver_id === userId) return { ride, as: "driver" };
  throw notFound("Ride not found");
}

export async function activeRideFor(db: D1Database, userId: string) {
  return db
    .prepare(
      `SELECT * FROM rides WHERE (rider_id = ?1 OR driver_id = ?1) AND status IN ('requested', 'accepted', 'arrived', 'in_progress')
       ORDER BY requested_at DESC LIMIT 1`,
    )
    .bind(userId)
    .first<RideRow>();
}

export async function logRideEvent(db: D1Database, rideId: string, type: string, actorId: string | null, data?: unknown) {
  await db
    .prepare("INSERT INTO ride_events (ride_id, type, actor_id, data, created_at) VALUES (?, ?, ?, ?, ?)")
    .bind(rideId, type, actorId, data === undefined ? null : JSON.stringify(data), now())
    .run();
}

/**
 * Moves a ride from one of `from` to `to`, setting extra columns. The update is
 * conditional on the current status, so concurrent transitions can't both win.
 */
export async function transition(
  env: Env,
  ride: RideRow,
  from: RideStatus[],
  to: RideStatus,
  actorId: string,
  fields: Record<string, string | number | null> = {},
  eventData?: unknown,
) {
  if (!from.includes(ride.status)) {
    throw new ApiError(409, "invalid_transition", `Ride is ${ride.status}; cannot move to ${to}`);
  }
  const cols = Object.keys(fields);
  const set = ["status = ?", ...cols.map((c) => `${c} = ?`)].join(", ");
  const placeholders = from.map(() => "?").join(", ");
  const updated = await env.DB.prepare(`UPDATE rides SET ${set} WHERE id = ? AND status IN (${placeholders}) RETURNING *`)
    .bind(to, ...cols.map((c) => fields[c]), ride.id, ...from)
    .first<RideRow>();
  if (!updated) throw conflict("Ride changed while updating; refresh and try again", "invalid_transition");
  await logRideEvent(env.DB, ride.id, to, actorId, eventData);
  await publishRideUpdate(env, ride.id, to);
  return updated;
}

export function requireViewer(as: Viewer, expected: Viewer) {
  if (as !== expected) throw forbidden(`Only the ${expected} can do this`);
}
