import { DurableObject } from "cloudflare:workers";
import type { Env } from "../env";
import { haversine, type LatLng } from "../lib/geo";
import type { VehicleClass } from "../lib/pricing";
import { publishRideUpdate } from "../lib/realtime";
import { rideRoom } from "./ride-room";

/** How long a driver has to answer an offer. */
export const OFFER_TIMEOUT_MS = 15_000;
/** How long a ride keeps searching before it becomes `no_driver`. */
export const SEARCH_TIMEOUT_MS = 90_000;
/** Retry interval while no candidate driver is available. */
const RETRY_MS = 5_000;
/** Drivers who haven't reported a location for this long are treated as offline. */
export const PRESENCE_TTL_MS = 120_000;
/** Maximum pickup distance for an offer. */
export const MATCH_RADIUS_M = 5_000;

export interface DriverPresence {
  driverId: string;
  vehicleId: string;
  vehicleClass: VehicleClass;
  lat: number;
  lng: number;
  heading: number | null;
  updatedAt: number;
  /** Ride the driver is currently serving, if any. */
  rideId: string | null;
}

interface Search {
  rideId: string;
  riderId: string;
  pickup: LatLng;
  vehicleClass: VehicleClass;
  startedAt: number;
  declined: string[];
  offer: { driverId: string; expiresAt: number } | null;
  nextAttemptAt: number;
}

export interface Offer {
  rideId: string;
  expiresAt: number;
  pickupDistanceM: number;
}

export type AcceptResult = { ok: true } | { ok: false; reason: "no_offer" | "expired" };

/** Messages pushed to drivers over their dispatch WebSocket. */
export type DriverMessage = { type: "offer"; offer: Offer } | { type: "offer_cancelled"; rideId: string };

/**
 * One instance per city. Tracks which drivers are online and where, and runs the
 * matching loop that offers each requested ride to the nearest free driver in turn.
 */
export class DispatchHub extends DurableObject<Env> {
  private drivers = new Map<string, DriverPresence>();
  private searches = new Map<string, Search>();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      const drivers = await ctx.storage.get<DriverPresence[]>("drivers");
      const searches = await ctx.storage.get<Search[]>("searches");
      for (const d of drivers ?? []) this.drivers.set(d.driverId, d);
      for (const s of searches ?? []) this.searches.set(s.rideId, s);
    });
  }

  // ---- presence ------------------------------------------------------------

  async goOnline(p: Omit<DriverPresence, "updatedAt" | "rideId" | "heading"> & { heading?: number | null; rideId?: string | null }) {
    const existing = this.drivers.get(p.driverId);
    this.drivers.set(p.driverId, {
      ...p,
      heading: p.heading ?? null,
      rideId: p.rideId ?? existing?.rideId ?? null,
      updatedAt: Date.now(),
    });
    await this.persist();
    // A new driver may unblock rides that are waiting for a candidate.
    await this.dispatchWaiting();
  }

  async goOffline(driverId: string) {
    const d = this.drivers.get(driverId);
    if (d?.rideId) return { ok: false as const, reason: "on_trip" as const };
    this.drivers.delete(driverId);
    // Anything offered to this driver moves on to the next candidate.
    for (const s of this.searches.values()) {
      if (s.offer?.driverId === driverId) this.rejectOffer(s, driverId);
    }
    await this.persist();
    await this.dispatchWaiting();
    return { ok: true as const };
  }

  /** Returns false if the driver is not online (and so must call goOnline first). */
  async updateLocation(driverId: string, loc: LatLng & { heading?: number | null }) {
    const d = this.drivers.get(driverId);
    if (!d) return false;
    d.lat = loc.lat;
    d.lng = loc.lng;
    d.heading = loc.heading ?? d.heading;
    d.updatedAt = Date.now();
    await this.persist();
    return true;
  }

  async getPresence(driverId: string) {
    const d = this.drivers.get(driverId);
    return d && this.isFresh(d) ? d : null;
  }

  /** Free drivers near a point, for the rider's map. Driver ids are not exposed. */
  async nearby(point: LatLng, limit = 20) {
    return [...this.drivers.values()]
      .filter((d) => this.isFresh(d) && !d.rideId)
      .map((d) => ({ lat: d.lat, lng: d.lng, heading: d.heading, vehicle_class: d.vehicleClass, distance_m: Math.round(haversine(point, d)) }))
      .filter((d) => d.distance_m <= MATCH_RADIUS_M)
      .sort((a, b) => a.distance_m - b.distance_m)
      .slice(0, limit);
  }

  /** Surge multiplier from open requests versus free drivers of a class. */
  async surge(vehicleClass: VehicleClass) {
    const demand = [...this.searches.values()].filter((s) => s.vehicleClass === vehicleClass).length;
    const supply = [...this.drivers.values()].filter((d) => d.vehicleClass === vehicleClass && !d.rideId && this.isFresh(d)).length;
    if (demand <= supply || demand < 3) return 1;
    const ratio = supply === 0 ? 3 : demand / supply;
    return Math.min(2, Math.round((1 + (ratio - 1) * 0.25) * 10) / 10);
  }

  // ---- matching ------------------------------------------------------------

  async requestRide(r: { rideId: string; riderId: string; pickup: LatLng; vehicleClass: VehicleClass }) {
    if (this.searches.has(r.rideId)) return;
    const ts = Date.now();
    const search: Search = { ...r, startedAt: ts, declined: [], offer: null, nextAttemptAt: ts };
    this.searches.set(r.rideId, search);
    this.tryOffer(search);
    await this.persist();
    await this.scheduleAlarm();
  }

  /** The ride currently offered to a driver, if any. */
  async currentOffer(driverId: string): Promise<Offer | null> {
    for (const s of this.searches.values()) {
      if (s.offer?.driverId === driverId && s.offer.expiresAt > Date.now()) {
        const d = this.drivers.get(driverId);
        return { rideId: s.rideId, expiresAt: s.offer.expiresAt, pickupDistanceM: d ? Math.round(haversine(d, s.pickup)) : 0 };
      }
    }
    return null;
  }

  async acceptOffer(rideId: string, driverId: string): Promise<AcceptResult> {
    const s = this.searches.get(rideId);
    if (!s || s.offer?.driverId !== driverId) return { ok: false, reason: "no_offer" };
    if (s.offer.expiresAt <= Date.now()) return { ok: false, reason: "expired" };
    this.searches.delete(rideId);
    const d = this.drivers.get(driverId);
    if (d) d.rideId = rideId;
    await this.persist();
    await this.scheduleAlarm();
    return { ok: true };
  }

  async declineOffer(rideId: string, driverId: string) {
    const s = this.searches.get(rideId);
    if (!s || s.offer?.driverId !== driverId) return false;
    this.rejectOffer(s, driverId);
    this.tryOffer(s);
    await this.persist();
    await this.scheduleAlarm();
    return true;
  }

  /** Stops searching for a ride (e.g. the rider cancelled). */
  async cancelSearch(rideId: string) {
    const s = this.searches.get(rideId);
    if (!s) return;
    this.searches.delete(rideId);
    await this.persist();
    await this.scheduleAlarm();
    if (s.offer) this.pushToDriver(s.offer.driverId, { type: "offer_cancelled", rideId });
  }

  /** Marks a driver free again after a ride ends or is cancelled. */
  async releaseDriver(driverId: string, rideId: string) {
    const d = this.drivers.get(driverId);
    if (d?.rideId === rideId) {
      d.rideId = null;
      d.updatedAt = Date.now();
      await this.persist();
      await this.dispatchWaiting();
    }
  }

  async alarm() {
    const ts = Date.now();
    for (const s of [...this.searches.values()]) {
      if (s.offer && s.offer.expiresAt <= ts) this.rejectOffer(s, s.offer.driverId);
      if (!s.offer && ts - s.startedAt >= SEARCH_TIMEOUT_MS) {
        this.searches.delete(s.rideId);
        await this.markNoDriver(s.rideId);
        continue;
      }
      if (!s.offer && ts >= s.nextAttemptAt) this.tryOffer(s);
    }
    await this.persist();
    await this.scheduleAlarm();
  }

  // ---- internals -----------------------------------------------------------

  private isFresh(d: DriverPresence) {
    return d.rideId !== null || Date.now() - d.updatedAt < PRESENCE_TTL_MS;
  }

  private rejectOffer(s: Search, driverId: string) {
    s.declined.push(driverId);
    s.offer = null;
    s.nextAttemptAt = Date.now();
  }

  private tryOffer(s: Search) {
    const ts = Date.now();
    const offered = new Set([...this.searches.values()].flatMap((x) => (x.offer ? [x.offer.driverId] : [])));
    const candidate = [...this.drivers.values()]
      .filter((d) => d.vehicleClass === s.vehicleClass && !d.rideId && this.isFresh(d) && !offered.has(d.driverId) && !s.declined.includes(d.driverId))
      .map((d) => ({ d, dist: haversine(d, s.pickup) }))
      .filter((x) => x.dist <= MATCH_RADIUS_M)
      .sort((a, b) => a.dist - b.dist)[0];
    if (!candidate) {
      s.nextAttemptAt = ts + RETRY_MS;
      return;
    }
    s.offer = { driverId: candidate.d.driverId, expiresAt: ts + OFFER_TIMEOUT_MS };
    this.pushToDriver(candidate.d.driverId, {
      type: "offer",
      offer: { rideId: s.rideId, expiresAt: s.offer.expiresAt, pickupDistanceM: Math.round(candidate.dist) },
    });
  }

  private async dispatchWaiting() {
    let changed = false;
    for (const s of this.searches.values()) {
      if (!s.offer) {
        this.tryOffer(s);
        changed ||= !!s.offer;
      }
    }
    if (changed) {
      await this.persist();
      await this.scheduleAlarm();
    }
  }

  private async markNoDriver(rideId: string) {
    const ts = Date.now();
    const res = await this.env.DB.prepare("UPDATE rides SET status = 'no_driver', cancelled_at = ? WHERE id = ? AND status = 'requested'").bind(ts, rideId).run();
    if (res.meta.changes) {
      await this.env.DB.prepare("INSERT INTO ride_events (ride_id, type, created_at) VALUES (?, 'no_driver', ?)").bind(rideId, ts).run();
      await publishRideUpdate(this.env, rideId, "no_driver");
    }
  }

  // ---- driver WebSockets ---------------------------------------------------

  /** Accepts a driver's dispatch socket (the Worker has already authenticated them). */
  async fetch(request: Request) {
    if (request.headers.get("Upgrade") !== "websocket") return new Response("Expected WebSocket", { status: 426 });
    const driverId = request.headers.get("X-Driver-Id")!;
    // One socket per driver: a reconnect replaces the old one.
    for (const old of this.ctx.getWebSockets(driverId)) old.close(1000, "replaced");
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1], [driverId]);
    const offer = await this.currentOffer(driverId);
    const d = this.drivers.get(driverId);
    this.sendTo(pair[1], { type: "status", online: !!d && this.isFresh(d), ride_id: d?.rideId ?? null });
    if (offer) this.sendTo(pair[1], { type: "offer", offer });
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  async webSocketMessage(ws: WebSocket, raw: string | ArrayBuffer) {
    const [driverId] = this.ctx.getTags(ws);
    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(typeof raw === "string" ? raw : new TextDecoder().decode(raw));
    } catch {
      return this.sendTo(ws, { type: "error", message: "Invalid JSON" });
    }
    if (msg.type === "ping") return this.sendTo(ws, { type: "pong" });
    if (msg.type !== "location") return this.sendTo(ws, { type: "error", message: "Unknown message type" });
    const { lat, lng, heading } = msg;
    if (typeof lat !== "number" || typeof lng !== "number" || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      return this.sendTo(ws, { type: "error", message: "lat and lng are required" });
    }
    const loc = { lat, lng, heading: typeof heading === "number" ? heading : null };
    if (!(await this.updateLocation(driverId, loc))) return this.sendTo(ws, { type: "error", message: "You are offline; go online first" });
    // Riders follow the driver through the ride's room.
    const rideId = this.drivers.get(driverId)?.rideId;
    if (rideId) await rideRoom(this.env, rideId).driverLocation(loc);
  }

  async webSocketClose(ws: WebSocket, code: number) {
    try {
      ws.close(code === 1005 ? 1000 : code, "closing");
    } catch {
      // Already closed.
    }
  }

  private pushToDriver(driverId: string, msg: DriverMessage) {
    for (const ws of this.ctx.getWebSockets(driverId)) this.sendTo(ws, msg);
  }

  private sendTo(ws: WebSocket, msg: DriverMessage | { type: "status"; online: boolean; ride_id: string | null } | { type: "pong" } | { type: "error"; message: string }) {
    try {
      ws.send(JSON.stringify(msg));
    } catch {
      // Socket went away.
    }
  }

  private async scheduleAlarm() {
    let next = Infinity;
    for (const s of this.searches.values()) {
      next = Math.min(next, s.offer ? s.offer.expiresAt : Math.min(s.nextAttemptAt, s.startedAt + SEARCH_TIMEOUT_MS));
    }
    if (next === Infinity) await this.ctx.storage.deleteAlarm();
    else await this.ctx.storage.setAlarm(Math.max(next, Date.now() + 100));
  }

  private async persist() {
    // Drop stale presence so storage doesn't grow without bound.
    for (const [id, d] of this.drivers) if (!this.isFresh(d)) this.drivers.delete(id);
    await this.ctx.storage.put({ drivers: [...this.drivers.values()], searches: [...this.searches.values()] });
  }
}

export function dispatchHub(env: Env, city: string) {
  return env.DISPATCH.get(env.DISPATCH.idFromName(city));
}
