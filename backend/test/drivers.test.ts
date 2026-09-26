import { describe, expect, it } from "vitest";
import { api, login, loginAdmin } from "./helpers";

const vehicle = { vehicle_class: "bike", make: "Bajaj", model: "Pulsar", color: "Black", plate_number: "dhaka-la-1111" };

describe("drivers", () => {
  it("requires a name before registering", async () => {
    const { token } = await login();
    const res = await api("POST", "/v1/drivers", { token, body: { license_number: "DL-1234", vehicle } });
    expect(res.status).toBe(403);
  });

  it("registers a pending driver, returns new tokens and lets an admin approve", async () => {
    const { token, user } = await login();
    await api("PATCH", "/v1/me", { token, body: { name: "Karim" } });
    const res = await api("POST", "/v1/drivers", { token, body: { license_number: "DL-1234", vehicle } });
    expect(res.status).toBe(201);
    expect(res.body.user.role).toBe("driver");
    expect(res.body.driver.status).toBe("pending");
    expect(res.body.driver.city).toBe("dhaka");
    expect(res.body.driver.vehicles[0]).toMatchObject({ plate_number: "DHAKA-LA-1111", is_active: true });

    const again = await api("POST", "/v1/drivers", { token: res.body.access_token, body: { license_number: "DL-1234", vehicle } });
    expect(again.status).toBe(409);

    const adminSession = await loginAdmin();
    const pending = await api("GET", "/v1/admin/drivers", { token: adminSession.token });
    expect(pending.body.drivers.map((d: any) => d.user_id)).toContain(user.id);

    const approved = await api("PATCH", `/v1/admin/drivers/${user.id}`, { token: adminSession.token, body: { status: "approved" } });
    expect(approved.body.driver.status).toBe("approved");
  });

  it("rejects duplicate plates and switches the active vehicle", async () => {
    const { token } = await login();
    await api("PATCH", "/v1/me", { token, body: { name: "Selim" } });
    const reg = await api("POST", "/v1/drivers", {
      token,
      body: { license_number: "DL-5678", vehicle: { ...vehicle, plate_number: "DHAKA-LA-2222" } },
    });
    const driverToken = reg.body.access_token;
    const dup = await api("POST", "/v1/drivers/me/vehicles", { token: driverToken, body: { ...vehicle, plate_number: "DHAKA-LA-2222" } });
    expect(dup.status).toBe(409);

    const added = await api("POST", "/v1/drivers/me/vehicles", {
      token: driverToken,
      body: { vehicle_class: "car", make: "Toyota", model: "Premio", color: "Silver", plate_number: "DHAKA-GA-3333" },
    });
    const car = added.body.driver.vehicles.find((v: any) => v.vehicle_class === "car");
    expect(car.is_active).toBe(false);

    const switched = await api("POST", `/v1/drivers/me/vehicles/${car.id}/activate`, { token: driverToken });
    expect(switched.body.driver.vehicles.filter((v: any) => v.is_active).map((v: any) => v.id)).toEqual([car.id]);
  });

  it("keeps admin routes admin-only", async () => {
    const { token } = await login();
    expect((await api("GET", "/v1/admin/drivers", { token })).status).toBe(403);
  });
});
