import { describe, expect, it } from "vitest";
import { computeFare, estimateTrip } from "../src/lib/pricing";
import { promoDiscount } from "../src/lib/promo";
import { api, DHANMONDI, GULSHAN, login, loginAdmin } from "./helpers";

describe("pricing", () => {
  it("applies the minimum fare and rounds up to whole taka", () => {
    expect(computeFare("car", 100, 30)).toBe(12000);
    const fare = computeFare("bike", 5_123, 900);
    expect(fare % 100).toBe(0);
    expect(fare).toBe(Math.ceil((2000 + 1200 * 5.123 + 100 * 15) / 100) * 100);
  });

  it("scales with surge", () => {
    const { distanceM, durationS } = estimateTrip(GULSHAN, DHANMONDI, "car");
    expect(computeFare("car", distanceM, durationS, 1.5)).toBeGreaterThan(computeFare("car", distanceM, durationS));
  });

  it("caps percentage discounts and never exceeds the fare", () => {
    const base = { code: "X", description: null, flat_off: null, min_fare: 0, max_uses: null, per_user_limit: 1, used_count: 0, starts_at: null, expires_at: null, is_active: 1 };
    expect(promoDiscount({ ...base, percent_off: 50, max_discount: 5000 }, 20000)).toBe(5000);
    expect(promoDiscount({ ...base, percent_off: null, max_discount: null, flat_off: 99999 }, 8000)).toBe(8000);
    expect(promoDiscount({ ...base, percent_off: 10, max_discount: null, min_fare: 50000 }, 20000)).toBe(0);
  });
});

describe("fare estimate endpoint", () => {
  it("quotes every vehicle class for a trip in Dhaka", async () => {
    const { token } = await login();
    const res = await api("POST", "/v1/fares/estimate", { token, body: { pickup: GULSHAN, dropoff: DHANMONDI } });
    expect(res.status).toBe(200);
    expect(res.body.city).toBe("dhaka");
    expect(res.body.currency).toBe("BDT");
    expect(res.body.options.map((o: any) => o.vehicle_class)).toEqual(["bike", "cng", "car"]);
    const [bike, , car] = res.body.options;
    expect(bike.total).toBeLessThan(car.total);
    expect(car.distance_m).toBeGreaterThan(6000);
  });

  it("rejects trips outside the service area or too short", async () => {
    const { token } = await login();
    const far = await api("POST", "/v1/fares/estimate", { token, body: { pickup: { lat: 51.5, lng: -0.12 }, dropoff: DHANMONDI } });
    expect(far.status).toBe(422);
    expect(far.body.error.code).toBe("out_of_service_area");
    const short = await api("POST", "/v1/fares/estimate", { token, body: { pickup: GULSHAN, dropoff: GULSHAN } });
    expect(short.body.error.code).toBe("trip_too_short");
  });

  it("applies an admin-created promo code", async () => {
    const adminSession = await loginAdmin();
    const created = await api("POST", "/v1/admin/promo-codes", {
      token: adminSession.token,
      body: { code: "cholo50", percent_off: 50, max_discount: 5000 },
    });
    expect(created.status).toBe(201);

    const { token } = await login();
    const res = await api("POST", "/v1/fares/estimate", { token, body: { pickup: GULSHAN, dropoff: DHANMONDI, promo_code: "Cholo50" } });
    expect(res.body.promo_code).toBe("CHOLO50");
    for (const o of res.body.options) {
      expect(o.discount).toBe(Math.min(Math.round(o.fare / 2), 5000));
      expect(o.total).toBe(o.fare - o.discount);
    }

    const bad = await api("POST", "/v1/fares/estimate", { token, body: { pickup: GULSHAN, dropoff: DHANMONDI, promo_code: "NOPE" } });
    expect(bad.body.error.code).toBe("promo_invalid");
  });

  it("lists cities without auth", async () => {
    const res = await api("GET", "/v1/cities");
    expect(res.body.cities[0]).toMatchObject({ id: "dhaka", name: "Dhaka" });
  });
});
