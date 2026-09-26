import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import { cors } from "hono/cors";
import type { AppEnv, Env } from "./env";
import { ApiError, handleError, notFound } from "./lib/errors";
import { cleanupStaleRides } from "./lib/maintenance";
import { admin } from "./routes/admin";
import { auth } from "./routes/auth";
import { drivers } from "./routes/drivers";
import { fares } from "./routes/fares";
import { geo } from "./routes/geo";
import { rides } from "./routes/rides";
import { users } from "./routes/users";

const app = new Hono<AppEnv>();

const jsonLimit = bodyLimit({
  maxSize: 64 * 1024,
  onError: (c) => handleError(new ApiError(413, "payload_too_large", "Request body is too large"), c),
});

app.use("*", cors());
// JSON bodies are small; the avatar upload enforces its own 2 MB limit.
app.use("*", async (c, next) => (c.req.path === "/v1/me/avatar" ? next() : jsonLimit(c, next)));
app.onError(handleError);
app.notFound((c) => handleError(notFound("Route not found"), c));

app.get("/", (c) => c.json({ name: "cholo-api", status: "ok" }));
app.route("/v1/auth", auth);
app.route("/v1", users);
app.route("/v1", fares);
app.route("/v1/drivers", drivers);
app.route("/v1/rides", rides);
app.route("/v1/geo", geo);
app.route("/v1/admin", admin);

export { DispatchHub } from "./do/dispatch";
export { RideRoom } from "./do/ride-room";
export default {
  fetch: app.fetch,
  async scheduled(_controller, env, ctx) {
    ctx.waitUntil(cleanupStaleRides(env));
  },
} satisfies ExportedHandler<Env>;
