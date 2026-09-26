import { beforeEach, describe, expect, it } from "vitest";
import { api, connect, GULSHAN, login, makeDriver, requestRide, resetHub } from "./helpers";

const near = (dLat: number) => ({ lat: GULSHAN.lat + dLat, lng: GULSHAN.lng });

beforeEach(() => resetHub());

async function startTrip() {
  const driver = await makeDriver("car");
  await api("POST", "/v1/drivers/me/online", { token: driver.token, body: near(0.002) });
  const dispatch = await connect("/v1/drivers/me/ws", driver.token);
  expect(await dispatch.next("status")).toMatchObject({ online: true, ride_id: null });

  const rider = await login();
  const rideId = (await requestRide(rider.token)).body.ride.id;
  return { driver, dispatch, rider, rideId };
}

describe("driver dispatch socket", () => {
  it("pushes offers and cancellations to the driver", async () => {
    const { dispatch, rider, rideId } = await startTrip();
    const offer = await dispatch.next("offer");
    expect(offer.offer.rideId).toBe(rideId);

    await api("POST", `/v1/rides/${rideId}/cancel`, { token: rider.token, body: {} });
    expect((await dispatch.next("offer_cancelled")).rideId).toBe(rideId);
  });

  it("sends a pending offer when the driver connects", async () => {
    const driver = await makeDriver("bike");
    await api("POST", "/v1/drivers/me/online", { token: driver.token, body: near(0.001) });
    const rider = await login();
    const rideId = (await requestRide(rider.token, "bike")).body.ride.id;
    const dispatch = await connect("/v1/drivers/me/ws", driver.token);
    expect((await dispatch.next("offer")).offer.rideId).toBe(rideId);
  });

  it("rejects riders and bad tokens", async () => {
    const rider = await login();
    await expect(connect("/v1/drivers/me/ws", rider.token)).rejects.toThrow(/404/);
    await expect(connect("/v1/drivers/me/ws", "nope")).rejects.toThrow(/401/);
  });
});

describe("ride room", () => {
  it("streams status, driver location and chat to both sides", async () => {
    const { driver, dispatch, rider, rideId } = await startTrip();
    await dispatch.next("offer");

    const riderRoom = await connect(`/v1/rides/${rideId}/ws`, rider.token);
    expect(await riderRoom.next("hello")).toMatchObject({ role: "rider", location: null, chat: [] });

    await api("POST", `/v1/rides/${rideId}/accept`, { token: driver.token });
    expect(await riderRoom.next("ride_updated")).toMatchObject({ ride_id: rideId, status: "accepted" });

    const driverRoom = await connect(`/v1/rides/${rideId}/ws`, driver.token);
    await driverRoom.next("hello");

    // Location sent on the dispatch socket is forwarded to the rider.
    dispatch.send({ type: "location", lat: 23.795, lng: 90.408, heading: 90 });
    expect((await riderRoom.next("driver_location")).location).toMatchObject({ lat: 23.795, lng: 90.408, heading: 90 });

    // Riders can't spoof the driver's location.
    riderRoom.send({ type: "location", lat: 1, lng: 1 });
    expect((await riderRoom.next("error")).message).toMatch(/driver/);

    riderRoom.send({ type: "chat", text: "  I'm at the gate  " });
    const chat = await driverRoom.next("chat");
    expect(chat.message).toMatchObject({ from: "rider", text: "I'm at the gate" });
    await riderRoom.next("chat");

    // A late joiner gets the last location and chat history.
    const again = await connect(`/v1/rides/${rideId}/ws`, rider.token);
    const hello = await again.next("hello");
    expect(hello.location).toMatchObject({ lat: 23.795 });
    expect(hello.chat).toHaveLength(1);
  });

  it("does not let strangers join", async () => {
    const { rideId } = await startTrip();
    const stranger = await login();
    await expect(connect(`/v1/rides/${rideId}/ws`, stranger.token)).rejects.toThrow(/404/);
  });
});

describe("completion, payment and ratings", () => {
  it("records payment, earnings and two-way ratings", async () => {
    const { driver, rider, rideId } = await startTrip();
    await api("POST", `/v1/rides/${rideId}/accept`, { token: driver.token });
    const otp = (await api("GET", `/v1/rides/${rideId}`, { token: rider.token })).body.ride.otp;

    expect((await api("POST", `/v1/rides/${rideId}/rating`, { token: rider.token, body: { stars: 5 } })).body.error.code).toBe("ride_not_completed");

    await api("POST", `/v1/rides/${rideId}/start`, { token: driver.token, body: { otp } });
    const done = await api("POST", `/v1/rides/${rideId}/complete`, { token: driver.token });
    const total = done.body.ride.total;
    expect(done.body.ride.payment).toMatchObject({ amount: total, method: "cash", status: "paid" });
    expect(done.body.ride.payment.driver_net + done.body.ride.payment.commission).toBe(total);

    const riderView = (await api("GET", `/v1/rides/${rideId}`, { token: rider.token })).body.ride;
    expect(riderView.payment).not.toHaveProperty("commission");

    const rated = await api("POST", `/v1/rides/${rideId}/rating`, { token: rider.token, body: { stars: 4, comment: "Safe driver" } });
    expect(rated.body.ride.my_rating).toBe(4);
    expect((await api("POST", `/v1/rides/${rideId}/rating`, { token: rider.token, body: { stars: 1 } })).body.error.code).toBe("already_rated");
    await api("POST", `/v1/rides/${rideId}/rating`, { token: driver.token, body: { stars: 5 } });

    expect((await api("GET", "/v1/me", { token: driver.token })).body.user).toMatchObject({ rating: 4, rating_count: 1 });
    expect((await api("GET", "/v1/me", { token: rider.token })).body.user).toMatchObject({ rating: 5, rating_count: 1 });

    const earnings = (await api("GET", "/v1/drivers/me/earnings", { token: driver.token })).body;
    expect(earnings.today).toMatchObject({ trips: 1, gross: total, net: done.body.ride.payment.driver_net });
    expect(earnings.daily).toHaveLength(7);
    expect(earnings.daily[6].trips).toBe(1);
    expect(earnings.lifetime).toMatchObject({ trips: 1, net: done.body.ride.payment.driver_net });
  });

  it("closes the ride room when the trip ends", async () => {
    const { driver, rider, rideId } = await startTrip();
    await api("POST", `/v1/rides/${rideId}/accept`, { token: driver.token });
    const room = await connect(`/v1/rides/${rideId}/ws`, rider.token);
    await room.next("hello");
    await api("POST", `/v1/rides/${rideId}/cancel`, { token: rider.token, body: {} });
    expect((await room.next("ride_updated")).status).toBe("cancelled");
    await new Promise((r) => setTimeout(r, 50));
    expect(room.closed).toBe(true);
  });
});
