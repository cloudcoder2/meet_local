import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../env";
import { requireAuth } from "../lib/auth";
import { ApiError } from "../lib/errors";
import { CITIES, cityFor } from "../lib/geo";

const NOMINATIM = "https://nominatim.openstreetmap.org";
const CACHE_TTL_S = 60 * 60 * 24 * 7;
const USER_AGENT = "Cholo/1.0 (ride-sharing; https://github.com/cloudcoder2/meet_local)";

export interface GeoResult {
  name: string;
  address: string;
  lat: number;
  lng: number;
}

interface NominatimPlace {
  lat: string;
  lon: string;
  name?: string;
  display_name: string;
}

function toResult(p: NominatimPlace): GeoResult {
  // display_name is long ("Gulshan 1, Gulshan, Dhaka, Dhaka Division, 1212, Bangladesh"); keep the useful head.
  const parts = p.display_name.split(",").map((s) => s.trim());
  const address = parts.filter((s) => s !== "Bangladesh" && !/^\d{4}$/.test(s) && !s.endsWith("Division")).slice(0, 4).join(", ");
  return { name: p.name || parts[0], address, lat: Number(p.lat), lng: Number(p.lon) };
}

async function cached<T>(kv: KVNamespace, key: string, load: () => Promise<T>): Promise<T> {
  const hit = await kv.get<T>(key, "json");
  if (hit) return hit;
  const value = await load();
  await kv.put(key, JSON.stringify(value), { expirationTtl: CACHE_TTL_S });
  return value;
}

async function nominatim<T>(path: string, params: Record<string, string>): Promise<T> {
  const url = `${NOMINATIM}${path}?${new URLSearchParams({ format: "jsonv2", "accept-language": "en", ...params })}`;
  const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
  if (!res.ok) throw new ApiError(502, "geocoder_unavailable", "Address lookup is unavailable right now");
  return res.json<T>();
}

export const geo = new Hono<AppEnv>();
geo.use("*", requireAuth);

/** Address search, biased to the city around `lat`/`lng` (or the default city). */
geo.get("/search", async (c) => {
  const q = z.string().trim().min(2).max(100).parse(c.req.query("q"));
  const lat = Number(c.req.query("lat"));
  const lng = Number(c.req.query("lng"));
  const city = (Number.isFinite(lat) && Number.isFinite(lng) && cityFor({ lat, lng })) || CITIES.find((x) => x.id === c.env.DEFAULT_CITY)!;
  const { minLng, maxLat, maxLng, minLat } = city.bounds;
  const results = await cached(c.env.KV, `geo:s:${city.id}:${q.toLowerCase()}`, async () =>
    (
      await nominatim<NominatimPlace[]>("/search", {
        q,
        countrycodes: "bd",
        viewbox: `${minLng},${maxLat},${maxLng},${minLat}`,
        bounded: "1",
        limit: "8",
      })
    ).map(toResult),
  );
  return c.json({ results });
});

/** Nearest address for a point, rounded so nearby lookups share a cache entry. */
geo.get("/reverse", async (c) => {
  const lat = z.coerce.number().min(-90).max(90).parse(c.req.query("lat"));
  const lng = z.coerce.number().min(-180).max(180).parse(c.req.query("lng"));
  const key = `geo:r:${lat.toFixed(4)},${lng.toFixed(4)}`;
  const result = await cached(c.env.KV, key, async () => {
    const p = await nominatim<NominatimPlace & { error?: string }>("/reverse", { lat: String(lat), lon: String(lng), zoom: "17" });
    return p.error ? null : toResult(p);
  });
  return c.json({ result: result ?? { name: "Pinned location", address: `${lat.toFixed(5)}, ${lng.toFixed(5)}`, lat, lng } });
});
