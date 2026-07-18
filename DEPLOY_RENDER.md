# Deploying the Prediction API to Render

## Prerequisites (do these first)
1. **The model file is committed to the repo** at
   `summative/linear_regression/best_model.pkl`. Render deploys from GitHub, so the
   `.pkl` must be *in the repo* (it's a few MB — fine for Git; no LFS needed).
2. **scikit-learn versions match.** `best_model.pkl` was saved in Google Colab with
   **scikit-learn 1.6.1**, and `requirements.txt` pins `scikit-learn==1.6.1`. Keep these
   equal — a mismatch makes the model fail to unpickle. (If you ever regenerate the
   `.pkl` in a different environment, update the pin to that environment's version.)
3. **Everything is pushed to GitHub** on the branch you'll deploy.

---

## Option A — Blueprint (one click, recommended)
1. Put `render.yaml` at the **repo root** (the folder containing `summative/`). It's
   already written for this layout.
2. Go to **Render → New → Blueprint**, connect your GitHub repo, pick the branch.
3. Render reads `render.yaml`, shows the `electricity-predictor-api` service → **Apply**.
4. Wait for the build/deploy to finish; copy the public URL
   (`https://electricity-predictor-api.onrender.com` or similar).

## Option B — Manual (Dashboard, if you prefer clicking)
**Render → New → Web Service**, connect the repo, then set:

| Field | Value |
|---|---|
| Root Directory | `summative/API` |
| Runtime | Python 3 |
| Build Command | `pip install -r requirements.txt` |
| Start Command | `uvicorn prediction:app --host 0.0.0.0 --port $PORT` |
| Environment variable | `PYTHON_VERSION` = `3.11.9` |
| Instance type | Free |

Create the service and wait for "Live".

---

## Verify the live API
Replace `<URL>` with your Render URL:

```bash
# 1. Health check — should show model_loaded: true, load_error: null
curl <URL>/

# 2. Swagger docs open in a browser:
#    <URL>/docs

# 3. Prediction (Indonesia 2013) — expect ~1189.2
curl -X POST <URL>/predict -H "Content-Type: application/json" -d '{
  "gdp": 2437876929100, "population": 255852464, "energy_per_capita": 7131.105,
  "energy_per_gdp": 0.748, "renewables_share_energy": 4.534,
  "fossil_share_energy": 95.466, "low_carbon_share_energy": 4.534}'
```

If `/` shows `"model_loaded": false`, read `load_error` — it will name the problem
(almost always a scikit-learn version mismatch; fix the pin and redeploy).

---

## Notes
- **Free-tier cold start:** the service sleeps after ~15 min idle; the first request then
  takes ~50 s while it wakes and loads the model. Hit `/` once to warm it up before a demo.
- **Flutter app:** once live, set `kApiBaseUrl` in `FlutterApp/lib/config.dart` to your
  Render URL. A **mobile** build needs no CORS change (CORS is browser-only). If you run
  Flutter **web**, add its origin to `ALLOWED_ORIGINS` in `prediction.py` and redeploy.
- **/retrain** overwrites `best_model.pkl` on the server's disk. On Render's free tier that
  disk is ephemeral (resets on redeploy/restart), so a retrain is not permanent there — fine
  for demoing the endpoint, but the committed `.pkl` remains the source of truth.
