export interface LatLng {
  lat: number;
  lng: number;
}

const EARTH_RADIUS_M = 6_371_000;
const toRad = (deg: number) => (deg * Math.PI) / 180;

/** Great-circle distance in metres. */
export function haversine(a: LatLng, b: LatLng): number {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}

export interface City {
  id: string;
  name: string;
  bounds: { minLat: number; maxLat: number; minLng: number; maxLng: number };
  center: LatLng;
}

export const CITIES: City[] = [
  { id: "dhaka", name: "Dhaka", bounds: { minLat: 23.6, maxLat: 23.95, minLng: 90.25, maxLng: 90.55 }, center: { lat: 23.8103, lng: 90.4125 } },
  { id: "chattogram", name: "Chattogram", bounds: { minLat: 22.2, maxLat: 22.5, minLng: 91.7, maxLng: 91.95 }, center: { lat: 22.3569, lng: 91.7832 } },
  { id: "sylhet", name: "Sylhet", bounds: { minLat: 24.83, maxLat: 24.97, minLng: 91.8, maxLng: 91.95 }, center: { lat: 24.8949, lng: 91.8687 } },
];

export function cityFor(p: LatLng): City | undefined {
  return CITIES.find((c) => p.lat >= c.bounds.minLat && p.lat <= c.bounds.maxLat && p.lng >= c.bounds.minLng && p.lng <= c.bounds.maxLng);
}
