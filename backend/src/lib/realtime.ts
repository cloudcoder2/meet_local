import { rideRoom } from "../do/ride-room";
import type { Env } from "../env";

/** Tells the ride's connected clients its status changed; they refetch the ride for details. */
export async function publishRideUpdate(env: Env, rideId: string, status: string): Promise<void> {
  try {
    await rideRoom(env, rideId).rideUpdated(rideId, status);
  } catch (err) {
    // Realtime is best effort; clients also poll the ride.
    console.error("publishRideUpdate failed", err);
  }
}
