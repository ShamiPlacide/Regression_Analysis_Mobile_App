# FlutterApp — Per-Capita Electricity Predictor (Task 3)

A single-screen Flutter app that sends 7 energy/economic features to the deployed
FastAPI service and displays the predicted per-capita electricity (kWh/person).

## What's in this folder
Only the source needed to build the app — the generated `android/`, `ios/`, `web/`,
`build/`, and `.dart_tool/` folders are intentionally **not** committed (they are
regenerated automatically; see below).

```
lib/
  config.dart                     # single API base-URL constant (kApiBaseUrl)
  services/prediction_service.dart# the API call (POST /predict) — all networking lives here
  main.dart                       # the UI: 7 inputs, validation, Predict button, result card
pubspec.yaml                      # dependencies (Flutter + http)
```

## API it talks to
Deployed FastAPI service:
`https://electricity-predictor-api.onrender.com` (set in `lib/config.dart`).

## How to run

### Option A — FlutLab.io (what this project was built with)
1. Create/open a Flutter project in FlutLab.
2. Add `http: ^1.2.0` to `pubspec.yaml` dependencies → **Pub Get**.
3. Put these files in place: `lib/config.dart`, `lib/services/prediction_service.dart`,
   `lib/main.dart`.
4. Press **Run** → the app opens in the FlutLab emulator/preview.

### Option B — Local Flutter SDK
```bash
cd summative/FlutterApp
flutter create .        # regenerates android/ios/web/ scaffolding around this source
flutter pub get
flutter run             # pick an emulator or connected device
```

### ⚠️ Required setup after `flutter create .` — Android INTERNET permission
The generated `android/` folder is not committed (see `.gitignore`), and a fresh
Android release build does **not** include network access by default. After
regenerating the platform folders, add this line to
`android/app/src/main/AndroidManifest.xml`, as the first child of `<manifest>`
(above `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Without it, the app builds fine but every API call fails with
"Couldn't reach the API" on a release build. (Debug builds include it
automatically, which is why it can be easy to miss.)

## Using the app
Enter the 4 required fields (GDP, population, energy per capita, energy intensity) and,
optionally, the 3 energy-mix shares (leave blank if unknown). Tap **Predict**.

Example (Indonesia 2013): `gdp=2437876929100`, `population=255852464`,
`energy_per_capita=7131.105`, `energy_per_gdp=0.748`, shares `4.534 / 95.466 / 4.534`
→ ≈ **1,193 kWh per person**.

> **Note:** the API runs on Render's free tier and sleeps after ~15 min idle. The first
> request after it sleeps takes ~50 s while it wakes up; open
> `https://electricity-predictor-api.onrender.com/` once to warm it before testing.

## Changing the API URL
Edit the single constant `kApiBaseUrl` in `lib/config.dart` — it is referenced everywhere.
