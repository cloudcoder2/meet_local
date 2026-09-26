import { runDurableObjectAlarm } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { ageHub, api, GULSHAN, hub, login, makeDriver, requestRide, resetHub } from "./helpers";

const near = (dLat: number) => ({ lat: GULSHAN.lat + dLat, lng: GULSHAN.lng });

beforeEach(() => resetHub());

describe("ride lifecycle", () => {
  it("runs a full trip from request to completion", async () => {
    const driver = await makeDriver("car", "Karim");
    expect((await api("POST", "/v1/drivers/me/online", { token: driver.token, body: near(0.005) })).status).toBe(200);

    const rider = await login();
    await api("PATCH", "/v1/me", { token: rider.token, body: { name: "Nadia" } });
    const created = await requestRide(rider.token);
    expect(created.status).toBe(201);
    const rideId = created.body.ride.id;
    expect(created.body.ride).toMatchObject({ status: "requested", vehicle_class: "car", driver: null, otp: null });

    const offer = await api("GET", "/v1/drivers/me/offer", { token: driver.token });
    expect(offer.body.offer).toMatchObject({ ride_id: rideId, rider: { name: "Nadia" }, total: created.body.ride.total });
    expect(offer.body.offer.driver_earnings).toBeLessThan(offer.body.offer.total);

    const accepted = await api("POST", `/v1/rides/${rideId}/accept`, { token: driver.token });
    expect(accepted.status).toBe(200);
    expect(accepted.body.ride.rider.name).toBe("Nadia");
    expect(accepted.body.ride.otp).toBeNull();

    const riderView = await api("GET", `/v1/rides/${rideId}`, { token: rider.token });
    expect(riderView.body.ride).toMatchObject({ status: "accepted", driver: { name: "Karim" }, vehicle: { vehicle_class: "car" } });
    const otp = riderView.body.ride.otp;
    expect(otp).toMatch(/^\d{4}$/);

    expect((await api("GET", "/v1/drivers/me/status", { token: driver.token })).body).toMatchObject({ online: true, ride_id: rideId });
    expect((await api("POST", "/v1/drivers/me/offline", { token: driver.token })).status).toBe(409);

    expect((await api("POST", `/v1/rides/${rideId}/arrived`, { token: driver.token })).body.ride.status).toBe("arrived");
    const wrong = otp === "0000" ? "1111" : "0000";
    expect((await api("POST", `/v1/rides/${rideId}/start`, { token: driver.token, body: { otp: wrong } })).body.error.code).toBe("otp_invalid");
    expect((await api("POST", `/v1/rides/${rideId}/start`, { token: driver.token, body: { otp } })).body.ride.status).toBe("in_progress");

    const done = await api("POST", `/v1/rides/${rideId}/complete`, { token: driver.token });
    expect(done.body.ride).toMatchObject({ status: "completed", total: created.body.ride.total });

    expect((await api("GET", "/v1/rides/active", { token: rider.token })).body.ride).toBeNull();
    expect((await api("GET", "/v1/rides", { token: rider.token })).body.rides.map((r: any) => r.id)).toEqual([rideId]);
    expect((await api("GET", "/v1/rides?role=driver", { token: driver.token })).body.rides[0].id).toBe(rideId);
    expect((await api("GET", "/v1/drivers/me", { token: driver.token })).body.driver.total_trips).toBe(1);

    // The driver is free again and can go offline.
    expect((await api("GET", "/v1/drivers/me/status", { token: driver.token })).body.ride_id).toBeNull();
    expect((await api("POST", "/v1/drivers/me/offline", { token: driver.token })).status).toBe(200);
  });

  it("stops other users from seeing or driving the ride", async () => {
    const driver = await makeDriver();
    await api("POST", "/v1/drivers/me/online", { token: driver.token, body: near(0.001) });
    const rider = await login();
    const rideId = (await requestRide(rider.token)).body.ride.id;
    const stranger = await login();
    expect((await api("GET", `/v1/rides/${rideId}`, { token: stranger.token })).status).toBe(404);
    expect((await api("POST", `/v1/rides/${rideId}/accept`, { token: rider.token })).status).toBe(403);

    const other = await makeDriver();
    expect((await api("POST", `/v1/rides/${rideId}/accept`, { token: other.token })).body.error.code).toBe("offer_unavailable");
    await api("POST", `/v1/rides/${rideId}/accept`, { token: driver.token });
    expect((await api("POST", `/v1/rides/${rideId}/arrived`, { token: rider.token })).status).toBe(403);
  });

  it("blocks a second active ride", async () => {
    const rider = await login();
    expect((await requestRide(rider.token)).status).toBe(201);
    expect((await requestRide(rider.token)).body.error.code).toBe("ride_in_progress");
  });

  it("lets the rider cancel a search and request again", async () => {
    const driver = await makeDriver();
    await api("POST", "/v1/drivers/me/online", { token: driver.token, body: near(0.001) });
    const rider = await login();
    const rideId = (await requestRide(rider.token)).body.ride.id;
    expect((await api("GET", "/v1/drivers/me/offer", { token: driver.token })).body.offer.ride_id).toBe(rideId);

    const cancelled = await api("POST", `/v1/rides/${rideId}/cancel`, { token: rider.token, body: { reason: "Changed plans" } });
    expect(cancelled.body.ride).toMatchObject({ status: "cancelled", cancelled_by: "rider", cancel_reason: "Changed plans" });
    expect((await api("GET", "/v1/drivers/me/offer", { token: driver.token })).body.offer).toBeNull();
    expect((await requestRide(rider.token)).status).toBe(201);
  });

  it("frees the driver when the ride is cancelled after acceptance", async () => {
    const driver = await makeDriver();
    await api("POST", "/v1/drivers/me/online", { token: driver.token, body: near(0.001) });
    const rider = await login();
    const rideId = (await requestRide(rider.token)).body.ride.id;
    await api("POST", `/v1/rides/${rideId}/accept`, { token: driver.token });
    const res = await api("POST", `/v1/rides/${rideId}/cancel`, { token: driver.token, body: {} });
    expect(res.body.ride.cancelled_by).toBe("driver");
    expect((await api("GET", "/v1/drivers/me/status", { token: driver.token })).body.ride_id).toBeNull();
  });
});

describe("dispatch", () => {
  it("offers the nearest driver of the right class, then the next one on decline", async () => {
    const far = await makeDriver("car");
    const close = await makeDriver("car");
    const bike = await makeDriver("bike");
    await api("POST", "/v1/drivers/me/online", { token: far.token, body: near(0.02) });
    await api("POST", "/v1/drivers/me/online", { token: close.token, body: near(0.002) });
    await api("POST", "/v1/drivers/me/online", { token: bike.token, body: near(0.0001) });

    const rider = await login();
    const rideId = (await requestRide(rider.token, "car")).body.ride.id;
    expect((await api("GET", "/v1/drivers/me/offer", { token: close.token })).body.offer.ride_id).toBe(rideId);
    expect((await api("GET", "/v1/drivers/me/offer", { token: far.token })).body.offer).toBeNull();
    expect((await api("GET", "/v1/drivers/me/offer", { token: bike.token })).body.offer).toBeNull();

    expect((await api("POST", `/v1/rides/${rideId}/decline`, { token: close.token })).status).toBe(204);
    expect((await api("GET", "/v1/drivers/me/offer", { token: far.token })).body.offer.ride_id).toBe(rideId);
  });

  it("moves on when an offer times out", async () => {
    const a = await makeDriver("cng");
    const b = await makeDriver("cng");
    await api("POST", "/v1/drivers/me/online", { token: a.token, body: near(0.001) });
    await api("POST", "/v1/drivers/me/online", { token: b.token, body: near(0.003) });
    const rider = await login();
    const rideId = (await requestRide(rider.token, "cng")).body.ride.id;
    expect((await api("GET", "/v1/drivers/me/offer", { token: a.token })).body.offer.ride_id).toBe(rideId);

    await ageHub(16_000);
    expect(await runDurableObjectAlarm(hub())).toBe(true);
    expect((await api("GET", "/v1/drivers/me/offer", { token: a.token })).body.offer).toBeNull();
    expect((await api("GET", "/v1/drivers/me/offer", { token: b.token })).body.offer.ride_id).toBe(rideId);
    expect((await api("POST", `/v1/rides/${rideId}/accept`, { token: a.token })).status).toBe(409);
  });

  it("gives up with no_driver after the search timeout", async () => {
    const rider = await login();
    const rideId = (await requestRide(rider.token, "bike")).body.ride.id;
    await ageHub(91_000);
    await runDurableObjectAlarm(hub());
    expect((await api("GET", `/v1/rides/${rideId}`, { token: rider.token })).body.ride.status).toBe("no_driver");
    expect((await requestRide(rider.token, "bike")).status).toBe(201);
  });

  it("offers a waiting ride to a driver who comes online later", async () => {
    const rider = await login();
    const rideId = (await requestRide(rider.token)).body.ride.id;
    const driver = await makeDriver();
    await api("POST", "/v1/drivers/me/online", { token: driver.token, body: near(0.001) });
    expect((await api("GET", "/v1/drivers/me/offer", { token: driver.token })).body.offer.ride_id).toBe(rideId);
  });

  it("shows free nearby drivers without exposing their ids", async () => {
    const driver = await makeDriver("bike");
    await api("POST", "/v1/drivers/me/online", { token: driver.token, body: near(0.001) });
    const rider = await login();
    const res = await api("GET", `/v1/drivers/nearby?lat=${GULSHAN.lat}&lng=${GULSHAN.lng}`, { token: rider.token });
    expect(res.body.drivers).toHaveLength(1);
    expect(res.body.drivers[0]).toMatchObject({ vehicle_class: "bike" });
    expect(res.body.drivers[0]).not.toHaveProperty("driverId");
  });

  it("refuses to put pending drivers online", async () => {
    const { token } = await login();
    await api("PATCH", "/v1/me", { token, body: { name: "Pending" } });
    const reg = await api("POST", "/v1/drivers", {
      token,
      body: { license_number: "DL-9999", vehicle: { vehicle_class: "bike", make: "Honda", model: "CB", color: "Red", plate_number: "DHAKA-HA-9999" } },
    });
    const res = await api("POST", "/v1/drivers/me/online", { token: reg.body.access_token, body: GULSHAN });
    expect(res.status).toBe(403);
  });

  it("surges when demand outstrips supply", async () => {
    for (let i = 0; i < 4; i++) {
      const rider = await login();
      await requestRide(rider.token, "bike");
    }
    expect(await hub().surge("bike")).toBeGreaterThan(1);
    expect(await hub().surge("car")).toBe(1);
  });
});
