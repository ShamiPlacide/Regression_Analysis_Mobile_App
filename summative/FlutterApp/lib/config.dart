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
///
/// Currently pointing at the deployed Render service
/// For LOCAL testing against your own uvicorn, swap back to
/// http://10.0.2.2:8000 (Android emulator) or http://127.0.0.1:8000 (iOS sim).
const String kApiBaseUrl = "https://electricity-predictor-api.onrender.com";
