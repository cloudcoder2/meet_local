# Cholo — Ride-Sharing App Plan

Cholo ("let's go") is a ride-sharing platform with a Flutter mobile app (rider + driver
modes) and a backend running entirely on Cloudflare. Defaults target Dhaka, Bangladesh
(BDT currency, Bike / CNG / Car vehicle classes), but everything is configurable.

## Architecture

```
Flutter app (rider + driver)                Cloudflare
┌──────────────────────────┐   HTTPS/JSON   ┌──────────────────────────────────────┐
│ Riverpod state           │ ─────────────► │ Worker (Hono router, JWT auth, zod)  │
│ go_router navigation     │                │   ├── D1 (SQLite): users, drivers,   │
│ flutter_map (OSM tiles)  │   WebSocket    │   │    vehicles, rides, ratings,      │
│ geolocator (GPS)         │ ◄────────────► │   │    payments, promo codes          │
│ secure token storage     │                │   ├── Durable Object `DispatchHub`:   │
└──────────────────────────┘                │   │    live driver presence + ride    │
                                            │   │    offers, one per city           │
                                            │   ├── Durable Object `RideRoom`: per- │
                                            │   │    ride WebSocket (status, live   │
                                            │   │    driver location, chat)         │
                                            │   ├── KV: OTP codes, rate limits      │
                                            │   └── R2: avatars, driver documents   │
                                            └──────────────────────────────────────┘
```

### Backend (`backend/`)
- **Runtime:** Cloudflare Workers, TypeScript, Hono, zod validation.
- **Auth:** phone number + OTP (OTP stored in KV with a 5 min TTL; in `dev` mode the OTP
  is returned in the response so no SMS provider is needed). Issues HS256 JWT access
  tokens (signed with the `JWT_SECRET` secret).
- **D1 schema:** `users`, `drivers`, `vehicles`, `rides`, `ride_events`, `ratings`,
  `payments`, `promo_codes`, `saved_places`.
- **Matching:** `DispatchHub` Durable Object keeps online drivers in memory with their
  last location. When a ride is requested, it ranks nearby drivers of the requested
  vehicle class by distance and offers the ride one driver at a time (15 s timeout,
  then next driver). Driver WebSocket connections receive offers in real time.
- **Ride lifecycle:** `requested → accepted → arrived → in_progress → completed`,
  with `cancelled` / `no_driver` exits. Every transition is validated server-side and
  logged to `ride_events`.
- **Realtime:** `RideRoom` Durable Object per ride. Rider and driver connect by
  WebSocket; the driver streams location, both sides get status updates and chat.
- **Pricing:** base fare + per-km + per-minute per vehicle class, minimum fare, surge
  multiplier from supply/demand in `DispatchHub`, promo code discounts.
- **Payments:** cash by default; a `payments` record per ride. Pluggable gateway
  interface for bKash / card later.

### Flutter app (`app/`)
- Single app with rider mode and driver mode (a user can register as a driver).
- **Packages:** `flutter_riverpod`, `go_router`, `dio`, `web_socket_channel`,
  `flutter_map` + `latlong2` (OpenStreetMap, no API key), `geolocator`,
  `flutter_secure_storage`.
- **Rider screens:** phone login → OTP → home map → set pickup/destination → fare
  estimates per vehicle class → searching → driver assigned (live tracking) → trip in
  progress → payment and rating → ride history, profile, saved places.
- **Driver screens:** driver onboarding (vehicle and licence) → go online/offline →
  incoming ride offer (accept/decline with countdown) → navigate to pickup → start
  trip → complete trip → earnings summary.

## Phases

Each phase ends with tests passing and a commit pushed.

- [x] **Phase 1: backend foundation.** Wrangler project, D1 schema and migrations, Hono
  app, JWT auth with phone OTP, user profile endpoints, test setup with
  `@cloudflare/vitest-pool-workers`.
- [x] **Phase 2: drivers and pricing.** Driver onboarding and vehicles, fare estimate
  endpoint, pricing config per vehicle class, promo codes.
- [x] **Phase 3: rides and dispatch.** Ride request/cancel, `DispatchHub` Durable
  Object (presence, matching, offers, timeouts), driver accept/decline, lifecycle
  transitions, ride history.
- [x] **Phase 4: realtime.** `RideRoom` Durable Object WebSockets (live location,
  status, chat), driver WebSocket to `DispatchHub`, ratings and payments on completion,
  driver earnings.
- [ ] **Phase 5: Flutter foundation.** Project, theme and branding, API client,
  auth flow (phone + OTP), secure token storage, router, profile.
- [ ] **Phase 6: Flutter rider flow.** Map home, place selection, fare estimates,
  request and searching, live tracking over WebSocket, trip completion, rating, history.
- [ ] **Phase 7: Flutter driver flow.** Onboarding, online toggle with location
  streaming, offer dialog, trip controls, earnings.
- [ ] **Phase 8: hardening and docs.** Rate limiting, input edge cases, CI workflow
  (backend tests + `flutter analyze` + `flutter test`), deployment guide.

## Running locally

See `backend/README.md` and `app/README.md` (added in their phases).
