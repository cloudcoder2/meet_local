import type { Env } from "../env";
import type { VehicleClass } from "./pricing";

/** Current surge multiplier for a city and vehicle class. */
export async function getSurge(_env: Env, _city: string, _vehicleClass: VehicleClass): Promise<number> {
  return 1;
}
