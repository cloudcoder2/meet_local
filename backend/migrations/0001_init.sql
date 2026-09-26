-- Cholo core schema. Timestamps are unix epoch milliseconds; money is stored in the
-- smallest currency unit (paisa for BDT) as integers.

CREATE TABLE users (
  id           TEXT PRIMARY KEY,
  phone        TEXT NOT NULL UNIQUE,
  name         TEXT,
  email        TEXT,
  avatar_key   TEXT,
  role         TEXT NOT NULL DEFAULT 'rider' CHECK (role IN ('rider', 'driver', 'admin')),
  rating_sum   INTEGER NOT NULL DEFAULT 0,
  rating_count INTEGER NOT NULL DEFAULT 0,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
);

CREATE TABLE drivers (
  user_id          TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  license_number   TEXT NOT NULL,
  nid_number       TEXT,
  status           TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'suspended')),
  city             TEXT NOT NULL,
  total_trips      INTEGER NOT NULL DEFAULT 0,
  total_earnings   INTEGER NOT NULL DEFAULT 0,
  created_at       INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL
);

CREATE TABLE vehicles (
  id            TEXT PRIMARY KEY,
  driver_id     TEXT NOT NULL REFERENCES drivers(user_id) ON DELETE CASCADE,
  vehicle_class TEXT NOT NULL CHECK (vehicle_class IN ('bike', 'cng', 'car')),
  make          TEXT NOT NULL,
  model         TEXT NOT NULL,
  color         TEXT NOT NULL,
  plate_number  TEXT NOT NULL UNIQUE,
  is_active     INTEGER NOT NULL DEFAULT 1,
  created_at    INTEGER NOT NULL
);
CREATE INDEX idx_vehicles_driver ON vehicles(driver_id);

CREATE TABLE rides (
  id               TEXT PRIMARY KEY,
  rider_id         TEXT NOT NULL REFERENCES users(id),
  driver_id        TEXT REFERENCES users(id),
  vehicle_id       TEXT REFERENCES vehicles(id),
  vehicle_class    TEXT NOT NULL CHECK (vehicle_class IN ('bike', 'cng', 'car')),
  city             TEXT NOT NULL,
  status           TEXT NOT NULL CHECK (status IN (
                     'requested', 'accepted', 'arriving', 'in_progress',
                     'completed', 'cancelled', 'no_driver')),
  pickup_lat       REAL NOT NULL,
  pickup_lng       REAL NOT NULL,
  pickup_address   TEXT NOT NULL,
  dropoff_lat      REAL NOT NULL,
  dropoff_lng      REAL NOT NULL,
  dropoff_address  TEXT NOT NULL,
  distance_m       INTEGER NOT NULL,
  duration_s       INTEGER NOT NULL,
  surge            REAL NOT NULL DEFAULT 1.0,
  estimated_fare   INTEGER NOT NULL,
  discount         INTEGER NOT NULL DEFAULT 0,
  final_fare       INTEGER,
  promo_code       TEXT,
  payment_method   TEXT NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('cash', 'wallet', 'card', 'bkash')),
  otp              TEXT NOT NULL,
  cancelled_by     TEXT,
  cancel_reason    TEXT,
  requested_at     INTEGER NOT NULL,
  accepted_at      INTEGER,
  started_at       INTEGER,
  completed_at     INTEGER,
  cancelled_at     INTEGER
);
CREATE INDEX idx_rides_rider ON rides(rider_id, requested_at DESC);
CREATE INDEX idx_rides_driver ON rides(driver_id, requested_at DESC);
CREATE INDEX idx_rides_status ON rides(status);

CREATE TABLE ride_events (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  ride_id    TEXT NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  type       TEXT NOT NULL,
  actor_id   TEXT,
  data       TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_ride_events_ride ON ride_events(ride_id, id);

CREATE TABLE ratings (
  ride_id    TEXT NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  rater_id   TEXT NOT NULL REFERENCES users(id),
  ratee_id   TEXT NOT NULL REFERENCES users(id),
  stars      INTEGER NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment    TEXT,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (ride_id, rater_id)
);

CREATE TABLE payments (
  id          TEXT PRIMARY KEY,
  ride_id     TEXT NOT NULL UNIQUE REFERENCES rides(id),
  amount      INTEGER NOT NULL,
  method      TEXT NOT NULL,
  status      TEXT NOT NULL CHECK (status IN ('pending', 'paid', 'failed', 'refunded')),
  commission  INTEGER NOT NULL DEFAULT 0,
  driver_net  INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);

CREATE TABLE promo_codes (
  code            TEXT PRIMARY KEY,
  description     TEXT,
  percent_off     INTEGER CHECK (percent_off BETWEEN 0 AND 100),
  max_discount    INTEGER,
  flat_off        INTEGER,
  min_fare        INTEGER NOT NULL DEFAULT 0,
  max_uses        INTEGER,
  per_user_limit  INTEGER NOT NULL DEFAULT 1,
  used_count      INTEGER NOT NULL DEFAULT 0,
  starts_at       INTEGER,
  expires_at      INTEGER,
  is_active       INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE saved_places (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label      TEXT NOT NULL,
  address    TEXT NOT NULL,
  lat        REAL NOT NULL,
  lng        REAL NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_saved_places_user ON saved_places(user_id);
