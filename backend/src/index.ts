import { Hono } from "hono";
import { cors } from "hono/cors";
import type { AppEnv } from "./env";
import { handleError, notFound } from "./lib/errors";
import { admin } from "./routes/admin";
import { auth } from "./routes/auth";
import { drivers } from "./routes/drivers";
import { fares } from "./routes/fares";
import { users } from "./routes/users";

const app = new Hono<AppEnv>();

app.use("*", cors());
app.onError(handleError);
app.notFound((c) => handleError(notFound("Route not found"), c));

app.get("/", (c) => c.json({ name: "cholo-api", status: "ok" }));
app.route("/v1/auth", auth);
app.route("/v1", users);
app.route("/v1", fares);
app.route("/v1/drivers", drivers);
app.route("/v1/admin", admin);

export default app;
