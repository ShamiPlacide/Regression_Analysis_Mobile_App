/// Single source of truth for the API base URL — referenced everywhere,
/// never hard-coded in more than this one place.
///
/// Pick the value that matches WHERE the app runs and WHERE the API runs:
///
///   • Android emulator (Android Studio) reaching an API on the SAME computer:
///       http://10.0.2.2:8000        (10.0.2.2 = the emulator's alias for host localhost)
///
///   • iOS simulator reaching an API on the same Mac:
///       http://127.0.0.1:8000
///
///   • FlutLab.io, a real phone, or Flutter Web:
///       these do NOT run on your computer, so "localhost" cannot reach your
///       local uvicorn. Use the PUBLIC API URL instead — your deployed Render
///       URL (e.g. https://your-service.onrender.com) or an ngrok tunnel URL.
///
/// Change ONLY this constant when you move between those environments.
///
/// Currently pointing at the deployed Render service (works from FlutLab, real
/// devices, and web). For LOCAL testing against your own uvicorn, swap back to
/// http://10.0.2.2:8000 (Android emulator) or http://127.0.0.1:8000 (iOS sim).
const String kApiBaseUrl = "https://electricity-predictor-api.onrender.com";
