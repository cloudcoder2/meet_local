# Cholo

Cholo ("let's go") is a ride-sharing app: a Flutter mobile app for riders and drivers,
backed by an API running on Cloudflare Workers, D1, Durable Objects, KV and R2.

- `backend/`: Cloudflare Workers API (TypeScript, Hono)
- `app/`: Flutter app
- [`PLAN.md`](PLAN.md): architecture and build phases

## Backend quick start

```sh
cd backend
npm install
cp .dev.vars.example .dev.vars
npm run db:migrate:local
npm run dev        # http://localhost:8787
npm test
```
