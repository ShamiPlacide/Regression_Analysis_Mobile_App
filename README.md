# Regression Analysis Mobile App: Predicting Per-Capita Electricity

## Mission

My mission is to help revolutionise urban development in Rwanda and across Africa by using
technology and sustainable design to build cities that are inclusive, environmentally
friendly, and centred on human well-being. Reliable electricity is the backbone of a
well-planned, connected, liveable city, so I built a machine learning pipeline that predicts
a country's electricity generated per person from its energy and economic profile. The goal
is to let planners quantify infrastructure gaps, for example the gap between Rwanda and a
high-income country, and prioritise investment accordingly.

## What this project does

Given a country's economic and energy indicators, the model predicts `per_capita_electricity`,
the electricity generated per person in kWh. This value is a strong proxy for a country's
infrastructure maturity and development level.

The project has three parts:

1. A regression model trained and compared in a notebook.
2. A FastAPI service that serves predictions and supports retraining, deployed publicly.
3. A single-screen Flutter mobile app that calls the API.

## Live links

- API base URL: https://electricity-predictor-api.onrender.com
- Interactive API docs (Swagger): https://electricity-predictor-api.onrender.com/docs
- Video demo: ADD_YOUR_VIDEO_LINK_HERE

Note: the API is hosted on a free tier that sleeps after about 15 minutes of inactivity, so
the first request can take up to a minute while it wakes up.

## Repository structure

```
Regression_Analysis_Mobile_App/
├── README.md
├── render.yaml                     # Render deployment config
├── requirements.txt                # runtime dependencies for the deployed API
└── summative/
    ├── pyproject.toml              # uv project definition
    ├── uv.lock                     # locked dependency versions
    ├── linear_regression/
    │   ├── multivariate.ipynb      # data prep, EDA, model training and comparison
    │   └── best_model.pkl          # the saved best model (Random Forest pipeline)
    ├── API/
    │   ├── prediction.py           # FastAPI app: /predict, /retrain, health check, CORS
    │   └── DEPLOY_RENDER.md         # deployment notes
    └── FlutterApp/
        ├── pubspec.yaml
        ├── lib/
        │   ├── config.dart         # single API base-URL constant
        │   ├── services/
        │   │   └── prediction_service.dart   # the HTTP call to /predict
        │   └── main.dart           # the single-screen UI and input validation
        └── README.md
```

## Dataset and modelling approach

- Source: the Our World in Data (OWID) energy dataset. I kept it global for volume and
  variety, and focused the interpretation on Rwanda and other African countries.
- Target: `per_capita_electricity` (kWh per person).
- Features: `gdp`, `population`, `energy_per_capita`, `energy_per_gdp`,
  `renewables_share_energy`, `fossil_share_energy`, `low_carbon_share_energy`.
- Leakage: I excluded `electricity_generation` because the target is defined as
  `electricity_generation * 1e9 / population`, so including it would let the model
  reconstruct the answer.

### Missing-data strategy

The missing values in this dataset are structural, not random. They concentrate in older
years and in smaller and African economies, which are exactly the rows I care about, so a
plain `dropna()` would have deleted them and biased the model toward rich countries. My
strategy:

1. Restrict to year 2000 onward, where coverage is densest.
2. Drop rows that are missing the well-covered core features (`gdp`, `population`,
   `energy_per_capita`, `energy_per_gdp`).
3. For the sparse energy-mix shares (about 60 percent missing), impute the median and add a
   missingness-indicator flag instead of dropping the rows. This kept about 920 African rows
   instead of collapsing to around 20.

### Models and results

I trained four scikit-learn models on the same data and compared them on a held-out test set
using RMSE and R2. RMSE is in kWh per person, so it is directly interpretable.

| Model | Test RMSE (kWh) | Test R2 |
|---|---|---|
| Random Forest (selected) | 681.1 | 0.99 |
| Decision Tree | 976.2 | 0.98 |
| Linear Regression (OLS) | 3,617.9 | 0.66 |
| SGD Linear (gradient descent) | 3,679.8 | 0.65 |

I selected the Random Forest because it had the lowest test RMSE. I judged on the test set,
not the training set, to avoid picking an overfit model. The saved model is a single pipeline
that includes imputation, log transform, and scaling, so it predicts directly from raw
feature values.

## How to run

### 1. The notebook (model training)

The notebook runs in Google Colab with no setup, since all libraries are pre-installed and
the dataset downloads itself. Open `summative/linear_regression/multivariate.ipynb` in Colab
and run all cells.

To run it locally instead, this project uses uv:

```bash
cd summative
uv sync
uv run jupyter notebook linear_regression/multivariate.ipynb
```

### 2. The API (locally)

```bash
cd summative/API
pip install -r ../../requirements.txt
uvicorn prediction:app --reload
```

Then open http://127.0.0.1:8000/docs to try it in the browser.

### 3. The API (deployed)

The API is already deployed on Render from `render.yaml`. It builds from `requirements.txt`
and starts with `uvicorn prediction:app`. Deployment notes are in
`summative/API/DEPLOY_RENDER.md`.

### 4. The Flutter app

The app was built on FlutLab.io. To run it:

1. Open the project in FlutLab, or run `flutter create .` inside `summative/FlutterApp` to
   regenerate the platform folders.
2. Make sure `http` is in `pubspec.yaml`, then get packages.
3. Set `kApiBaseUrl` in `lib/config.dart` to the API URL. It is already set to the deployed
   Render URL.
4. Run on an Android emulator or device.

If you build a release APK, add the internet permission to
`android/app/src/main/AndroidManifest.xml` as the first line inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Without it, a release build cannot reach the API. Full app instructions are in
`summative/FlutterApp/README.md`.

## API endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/` | Health check and loaded-model info |
| POST | `/predict` | Predict per-capita electricity from 7 features |
| POST | `/retrain` | Upload a CSV to retrain the model and overwrite the saved file |
| GET | `/docs` | Interactive Swagger documentation |

### Example prediction

Request:

```bash
curl -X POST https://electricity-predictor-api.onrender.com/predict \
  -H "Content-Type: application/json" \
  -d '{
    "gdp": 28466253314,
    "population": 13651025,
    "energy_per_capita": 497.914,
    "energy_per_gdp": 0.239,
    "renewables_share_energy": null,
    "fossil_share_energy": null,
    "low_carbon_share_energy": null
  }'
```

Response:

```json
{"predicted_per_capita_electricity_kwh": 73.3, "model_used": "Random Forest"}
```

The three energy-mix share fields are optional. If a value is unknown, send `null` rather
than 0, because the pipeline imputes missing shares internally. The required fields also have
range checks, so out-of-range or missing values return a clear validation error.

## Tech stack

- Python, pandas, numpy, scikit-learn, matplotlib, seaborn, joblib
- uv for environment and dependency management
- FastAPI, Pydantic, Uvicorn for the API
- Render for deployment
- Flutter and the http package for the mobile app
