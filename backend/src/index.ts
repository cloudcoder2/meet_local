import { Hono } from "hono";
import { cors } from "hono/cors";
import type { AppEnv } from "./env";
import { handleError, notFound } from "./lib/errors";
import { auth } from "./routes/auth";
import { users } from "./routes/users";

const app = new Hono<AppEnv>();

app.use("*", cors());
app.onError(handleError);
app.notFound((c) => handleError(notFound("Route not found"), c));

app.get("/", (c) => c.json({ name: "cholo-api", status: "ok" }));
app.route("/v1/auth", auth);
app.route("/v1", users);

export default app;
