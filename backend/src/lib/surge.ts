import { dispatchHub } from "../do/dispatch";
import type { Env } from "../env";
import type { VehicleClass } from "./pricing";

/** Current surge multiplier for a city and vehicle class. */
export async function getSurge(env: Env, city: string, vehicleClass: VehicleClass): Promise<number> {
  return dispatchHub(env, city).surge(vehicleClass);
}
