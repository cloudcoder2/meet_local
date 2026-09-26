import { env, exports } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { cleanupStaleRides } from "../src/lib/maintenance";
import { api, GULSHAN, login, makeDriver, requestRide, resetHub } from "./helpers";

beforeEach(() => resetHub());

describe("rate limits", () => {
  it("limits login attempts per IP", async () => {
    const statuses: number[] = [];
    for (let i = 0; i < 12; i++) {
      const res = await exports.default.fetch("https://api.cholo.test/v1/auth/otp/request", {
        method: "POST",
        headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.7" },
        body: JSON.stringify({ phone: `+88017120000${String(i).padStart(2, "0")}` }),
      });
      statuses.push(res.status);
    }
    expect(statuses.slice(0, 10).every((s) => s === 200)).toBe(true);
    expect(statuses.at(-1)).toBe(429);
  });
});

describe("request limits", () => {
  it("rejects oversized JSON bodies", async () => {
    const { token } = await login();
    const res = await exports.default.fetch("https://api.cholo.test/v1/me", {
      method: "PATCH",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ name: "x".repeat(70_000) }),
    });
    expect(res.status).toBe(413);
    expect((await res.json<any>()).error.code).toBe("payload_too_large");
  });

  it("returns JSON 404s for unknown routes", async () => {
    const res = await api("GET", "/v1/nope");
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe("not_found");
  });
});

describe("stale ride cleanup", () => {
  it("closes stuck searches and pickups and frees the driver", async () => {
    const searcher = await login();
    const searchId = (await requestRide(searcher.token, "bike")).body.ride.id;

    const driver = await makeDriver("car");
    await api("POST", "/v1/drivers/me/online", { token: driver.token, body: { lat: GULSHAN.lat + 0.001, lng: GULSHAN.lng } });
    const rider = await login();
    const pickupId = (await requestRide(rider.token, "car")).body.ride.id;
    await api("POST", `/v1/rides/${pickupId}/accept`, { token: driver.token });

    // Nothing is old enough yet.
    expect(await cleanupStaleRides(env)).toBe(0);

    const hourAgo = Date.now() - 3 * 60 * 60_000;
    await env.DB.prepare("UPDATE rides SET requested_at = ?, accepted_at = ? WHERE id IN (?, ?)").bind(hourAgo, hourAgo, searchId, pickupId).run();
    expect(await cleanupStaleRides(env)).toBe(2);

    expect((await api("GET", `/v1/rides/${searchId}`, { token: searcher.token })).body.ride.status).toBe("no_driver");
    const cancelled = (await api("GET", `/v1/rides/${pickupId}`, { token: rider.token })).body.ride;
    expect(cancelled).toMatchObject({ status: "cancelled", cancelled_by: "system" });
    expect((await api("GET", "/v1/drivers/me/status", { token: driver.token })).body.ride_id).toBeNull();
  });
});
