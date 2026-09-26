import { haversine, type LatLng } from "./geo";

export const VEHICLE_CLASSES = ["bike", "cng", "car"] as const;
export type VehicleClass = (typeof VEHICLE_CLASSES)[number];

/** Money is in paisa (1/100 BDT). */
interface Tariff {
  label: string;
  seats: number;
  base: number;
  perKm: number;
  perMin: number;
  minimum: number;
  /** Average urban speed used for duration estimates. */
  speedKmh: number;
}

export const TARIFFS: Record<VehicleClass, Tariff> = {
  bike: { label: "Cholo Bike", seats: 1, base: 2000, perKm: 1200, perMin: 100, minimum: 4000, speedKmh: 22 },
  cng: { label: "Cholo CNG", seats: 3, base: 3000, perKm: 2000, perMin: 200, minimum: 6000, speedKmh: 18 },
  car: { label: "Cholo Car", seats: 4, base: 5000, perKm: 3500, perMin: 300, minimum: 12000, speedKmh: 18 },
};

/** Share of each fare the platform keeps. */
export const COMMISSION_RATE = 0.15;

/** Straight-line distance is inflated to approximate road distance. */
const ROAD_FACTOR = 1.3;

export function estimateTrip(pickup: LatLng, dropoff: LatLng, vehicleClass: VehicleClass) {
  const distanceM = Math.round(haversine(pickup, dropoff) * ROAD_FACTOR);
  const durationS = Math.round((distanceM / 1000 / TARIFFS[vehicleClass].speedKmh) * 3600);
  return { distanceM, durationS };
}

/** Rounds up to a whole taka. */
const roundTaka = (paisa: number) => Math.ceil(paisa / 100) * 100;

export function computeFare(vehicleClass: VehicleClass, distanceM: number, durationS: number, surge = 1) {
  const t = TARIFFS[vehicleClass];
  const raw = t.base + (t.perKm * distanceM) / 1000 + (t.perMin * durationS) / 60;
  return roundTaka(Math.max(t.minimum, raw * surge));
}

export function splitFare(fare: number) {
  const commission = Math.round(fare * COMMISSION_RATE);
  return { commission, driverNet: fare - commission };
}
