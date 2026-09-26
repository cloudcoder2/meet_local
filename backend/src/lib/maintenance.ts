import { dispatchHub } from "../do/dispatch";
import type { Env } from "../env";
import { publishRideUpdate } from "./realtime";
import { now } from "./util";

/** Rides still searching after this long are closed (the dispatcher normally does it in 90 s). */
const STALE_SEARCH_MS = 10 * 60_000;
/** Accepted or arrived rides that never started within this window are cancelled. */
const STALE_PICKUP_MS = 2 * 60 * 60_000;

/**
 * Safety net run by the cron trigger: closes rides left behind if a Durable
 * Object was reset or a client vanished mid-ride, so nobody stays stuck with an
 * "active" ride that blocks new requests.
 */
export async function cleanupStaleRides(env: Env) {
  const ts = now();
  const searching = await env.DB.prepare(
    "UPDATE rides SET status = 'no_driver', cancelled_at = ? WHERE status = 'requested' AND requested_at < ? RETURNING id, status",
  )
    .bind(ts, ts - STALE_SEARCH_MS)
    .all<{ id: string; status: string }>();
  const pickups = await env.DB.prepare(
    `UPDATE rides SET status = 'cancelled', cancelled_by = 'system', cancel_reason = 'Pickup timed out', cancelled_at = ?
     WHERE status IN ('accepted', 'arrived') AND accepted_at < ? RETURNING id, status, driver_id, city`,
  )
    .bind(ts, ts - STALE_PICKUP_MS)
    .all<{ id: string; status: string; driver_id: string; city: string }>();
  for (const r of pickups.results) await dispatchHub(env, r.city).releaseDriver(r.driver_id, r.id);
  const closed = [...searching.results, ...pickups.results];
  for (const r of closed) {
    await env.DB.prepare("INSERT INTO ride_events (ride_id, type, data, created_at) VALUES (?, ?, ?, ?)")
      .bind(r.id, r.status, JSON.stringify({ reason: "stale" }), ts)
      .run();
    await publishRideUpdate(env, r.id, r.status);
  }
  return closed.length;
}
