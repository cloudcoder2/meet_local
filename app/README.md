# Cholo app

Flutter app for Cholo riders and drivers.

## Run

Start the backend first (see `../backend/README.md`), then:

```sh
flutter pub get
flutter run                                   # uses http://10.0.2.2:8787 on Android, localhost elsewhere
flutter run --dart-define=API_URL=https://cholo-api.<your-subdomain>.workers.dev
```

In development the API returns the login code in its response and the app shows it
on the code screen, so no SMS provider is needed.

## Structure

- `lib/core/`: config, theme, formatting
- `lib/data/`: API client (token refresh, error mapping), typed endpoints, models
- `lib/features/`: screens and state, one folder per feature
- `lib/widgets/`: shared widgets

## Checks

```sh
flutter analyze
flutter test
```
