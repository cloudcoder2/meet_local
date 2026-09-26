import { afterEach, describe, expect, it, vi } from "vitest";
import { api, login } from "./helpers";

afterEach(() => vi.restoreAllMocks());

function mockNominatim(body: unknown) {
  return vi.spyOn(globalThis, "fetch").mockImplementation(async () => Response.json(body));
}

describe("geo proxy", () => {
  it("searches within the city and caches results", async () => {
    const fetchSpy = mockNominatim([
      { lat: "23.7806", lon: "90.4193", name: "Gulshan 1", display_name: "Gulshan 1, Gulshan, Dhaka, Dhaka Division, 1212, Bangladesh" },
    ]);
    const { token } = await login();
    const res = await api("GET", "/v1/geo/search?q=Gulshan&lat=23.8&lng=90.4", { token });
    expect(res.body.results).toEqual([{ name: "Gulshan 1", address: "Gulshan 1, Gulshan, Dhaka", lat: 23.7806, lng: 90.4193 }]);
    const url = new URL(String(fetchSpy.mock.calls[0][0]));
    expect(url.searchParams.get("countrycodes")).toBe("bd");
    expect(url.searchParams.get("bounded")).toBe("1");

    await api("GET", "/v1/geo/search?q=gulshan&lat=23.8&lng=90.4", { token });
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });

  it("reverse geocodes with a fallback label", async () => {
    mockNominatim({ error: "Unable to geocode" });
    const { token } = await login();
    const res = await api("GET", "/v1/geo/reverse?lat=23.81&lng=90.41", { token });
    expect(res.body.result).toMatchObject({ name: "Pinned location", lat: 23.81, lng: 90.41 });
  });

  it("reports an unavailable geocoder", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response("busy", { status: 503 }));
    const { token } = await login();
    const res = await api("GET", "/v1/geo/search?q=Banani", { token });
    expect(res.status).toBe(502);
  });
});
