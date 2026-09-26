# Cholo

Cholo ("let's go") is a ride-sharing app: a Flutter mobile app for riders and drivers,
backed by an API running on Cloudflare Workers, D1, Durable Objects, KV and R2.

- `backend/`: Cloudflare Workers API (TypeScript, Hono)
- `app/`: Flutter app
- [`PLAN.md`](PLAN.md): architecture and build phases

## Features

- Phone number login with one-time codes
- Riders: map with nearby drivers, address search, saved places, fares for Bike,
  CNG and Car with promo codes, live driver tracking, in-ride chat, start code,
  cash receipt, ratings, trip history
- Drivers: onboarding with vehicle details, online/offline, ride offers with a
  countdown, navigation hand-off, trip controls, earnings with a 7-day chart
- Admin API for approving drivers and managing promo codes

## Backend quick start

```sh
cd backend
npm install
cp .dev.vars.example .dev.vars
npm run db:migrate:local
npm run dev        # http://localhost:8787
npm test
```

## App quick start

```sh
cd app
flutter pub get
flutter run        # talks to the local backend; see app/README.md
```

Deployment steps are in [`backend/README.md`](backend/README.md).
