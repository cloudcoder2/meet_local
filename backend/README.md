# Cholo API

Cholo's backend runs entirely on Cloudflare:

| Piece | Cloudflare product | Used for |
| --- | --- | --- |
| HTTP API | Workers (Hono) | All `/v1/*` endpoints |
| Database | D1 | Users, drivers, vehicles, rides, payments, ratings, promo codes, saved places |
| Dispatch | Durable Object `DispatchHub` (one per city) | Online drivers, matching, ride offers, driver WebSockets |
| Live trips | Durable Object `RideRoom` (one per ride) | Status updates, driver location and chat over WebSockets |
| Cache | KV | Login codes, per-phone limits, geocoding cache |
| Files | R2 | Profile photos |
| Abuse protection | Rate Limiting bindings | Per-IP login limit, per-user API limit |
| Housekeeping | Cron trigger (every 5 min) | Closes stuck searches and pickups |

## Local development

```sh
npm install
cp .dev.vars.example .dev.vars          # set JWT_SECRET
npm run db:migrate:local
npm run dev                             # http://localhost:8787
```

In `dev` (`APP_ENV` is not `production`) the login endpoint returns the code as
`dev_code`, and new drivers are approved automatically (`DRIVER_AUTO_APPROVE`).

```sh
npm test          # vitest inside the Workers runtime (D1, KV, R2, Durable Objects)
npm run typecheck
```

## Deploying

1. Create the resources and copy their ids into `wrangler.jsonc`:

   ```sh
   npx wrangler login
   npx wrangler d1 create cholo-db          # → d1_databases[0].database_id
   npx wrangler kv namespace create KV      # → kv_namespaces[0].id
   npx wrangler r2 bucket create cholo-media
   ```

2. Set production config in `wrangler.jsonc` `vars`:
   - `APP_ENV`: `production` (hides `dev_code`; wire an SMS provider in `src/routes/auth.ts` first)
   - `DRIVER_AUTO_APPROVE`: `false`, so admins approve drivers
   - `ADMIN_PHONES`: comma-separated E.164 numbers that get the admin role on login

3. Set the signing secret, apply migrations and deploy:

   ```sh
   npx wrangler secret put JWT_SECRET      # a long random string
   npm run db:migrate:remote
   npm run deploy
   ```

4. Point the app at it: `flutter run --dart-define=API_URL=https://cholo-api.<subdomain>.workers.dev`.

## API overview

All bodies are JSON with snake_case keys; money is in paisa (1/100 taka). Errors are
`{"error": {"code", "message"}}`. Authenticated routes take `Authorization: Bearer <access_token>`
(WebSockets use `?token=`).

| Area | Endpoints |
| --- | --- |
| Auth | `POST /v1/auth/otp/request`, `POST /v1/auth/otp/verify`, `POST /v1/auth/refresh` |
| Profile | `GET/PATCH /v1/me`, `PUT /v1/me/avatar`, `GET/POST/DELETE /v1/me/places` |
| Places | `GET /v1/geo/search?q=`, `GET /v1/geo/reverse?lat=&lng=`, `GET /v1/cities` |
| Fares | `POST /v1/fares/estimate` |
| Rides | `POST /v1/rides`, `GET /v1/rides`, `GET /v1/rides/active`, `GET /v1/rides/:id`, `POST /v1/rides/:id/{cancel,accept,decline,arrived,start,complete,rating}`, `GET /v1/rides/:id/ws` |
| Drivers | `POST /v1/drivers`, `GET /v1/drivers/me`, `POST /v1/drivers/me/vehicles`, `POST /v1/drivers/me/{online,offline,location}`, `GET /v1/drivers/me/{status,offer,earnings}`, `GET /v1/drivers/me/ws`, `GET /v1/drivers/nearby` |
| Admin | `GET/PATCH /v1/admin/drivers`, `POST/PATCH /v1/admin/promo-codes` |

### Ride lifecycle

`requested → accepted → arrived → in_progress → completed`, or `cancelled` (rider
before the trip starts, driver before pickup, or the cleanup cron) and `no_driver`
(nobody accepted within 90 seconds). Each ride is offered to the nearest free driver
of the requested class within 5 km, one at a time, for 15 seconds each.

### WebSocket messages

Ride room (`/v1/rides/:id/ws`): server sends `hello` (last driver location and
chat history), `ride_updated`, `driver_location` and `chat`; clients send `chat`,
`ping`, and the driver may send `location`.

Driver dispatch (`/v1/drivers/me/ws`): server sends `status`, `offer` and
`offer_cancelled`; the driver sends `location` (forwarded to the active ride's room)
and `ping`.
