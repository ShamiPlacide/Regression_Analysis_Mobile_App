"""
Task 2 — FastAPI prediction service for the per capita electricity model.

Serves the Random Forest pipeline trained in Task 1
(`summative/linear_regression/best_model.pkl`, a joblib dict bundle).

Endpoints
---------
  GET / -> health check + loaded-model metadata
  POST /predict -> single prediction from 7 raw feature values
  POST /retrain -> upload a CSV, retrain the pipeline, overwrite best_model.pkl

Run locally:
  uvicorn prediction:app --reload # from inside summative/API/
  uvicorn API.prediction:app --reload # from inside summative/
Then open http://127.0.0.1:8000/docs
"""
from __future__ import annotations

from pathlib import Path
from typing import Optional

import joblib
import numpy as np
import pandas as pd
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestRegressor
from sklearn.impute import SimpleImputer
from sklearn.metrics import mean_squared_error, r2_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import FunctionTransformer, StandardScaler

# ---------------------------------------------------------------------------
# Paths & feature definitions (must match the Task-1 notebook exactly)
# ---------------------------------------------------------------------------
MODEL_PATH = (Path(__file__).resolve().parent.parent
              / "linear_regression" / "best_model.pkl")

TARGET = "per_capita_electricity"
FEATURES = ["gdp", "population", "energy_per_capita", "energy_per_gdp",
            "renewables_share_energy", "fossil_share_energy", "low_carbon_share_energy"]
CORE = ["gdp", "population", "energy_per_capita", "energy_per_gdp"]  # row-dropped if missing
LOG_FEATURES = ["gdp", "population", "energy_per_capita"]            # skewed -> log1p
LIN_FEATURES = ["energy_per_gdp"]
TRIO = ["renewables_share_energy", "fossil_share_energy", "low_carbon_share_energy"]  # imputed
RANDOM_STATE = 42

# In-memory holder so the bundle is loaded ONCE (at startup) and can be swapped by /retrain.
STATE: dict = {"bundle": None}


# ---------------------------------------------------------------------------
# Model loading / prediction (reuses the notebook's logic, not reinvented)
# ---------------------------------------------------------------------------
def load_bundle(path: Path = MODEL_PATH) -> dict:
    """Load the joblib dict bundle {pipeline, model_name, features, ...}."""
    if not Path(path).exists():
        raise FileNotFoundError(f"Model file not found at {path}")
    return joblib.load(path)


def get_bundle() -> dict:
    """Return the in-memory bundle, loading it on first use."""
    if STATE["bundle"] is None:
        STATE["bundle"] = load_bundle()
    return STATE["bundle"]


def predict_per_capita_electricity(raw_features: dict, bundle: Optional[dict] = None) -> float:
    """Predict per-capita electricity (kWh) from a dict of RAW feature values.

    The saved pipeline handles impute + log + scale internally, so we pass raw,
    unscaled values straight through. The energy-mix shares may be None/NaN.
    """
    if bundle is None:
        bundle = get_bundle()
    X = pd.DataFrame([raw_features]).reindex(columns=bundle["features"]).astype(float)
    pred = float(bundle["pipeline"].predict(X)[0])
    return max(pred, 0.0)


def build_pipeline() -> Pipeline:
    """Rebuild the exact preprocessing + model pipeline from Task 1 (used by /retrain)."""
    log_pipe = Pipeline([("imp", SimpleImputer(strategy="median")),
                         ("log", FunctionTransformer(np.log1p, feature_names_out="one-to-one")),
                         ("sc", StandardScaler())])
    lin_pipe = Pipeline([("imp", SimpleImputer(strategy="median")),
                         ("sc", StandardScaler())])
    trio_pipe = Pipeline([("imp", SimpleImputer(strategy="median", add_indicator=True)),
                          ("sc", StandardScaler())])
    pre = ColumnTransformer([("log", log_pipe, LOG_FEATURES),
                             ("lin", lin_pipe, LIN_FEATURES),
                             ("trio", trio_pipe, TRIO)])
    model = RandomForestRegressor(n_estimators=400, random_state=RANDOM_STATE, n_jobs=-1)
    return Pipeline([("pre", pre), ("model", model)])


# ---------------------------------------------------------------------------
# Pydantic request / response schemas
# ---------------------------------------------------------------------------
class PredictionRequest(BaseModel):
    """7 raw features. Ranges are the observed training extremes rounded OUTWARD
    with a small safety margin, so legitimate edge-case countries are not rejected."""
    gdp: float = Field(..., ge=1.0e8, le=3.0e13,
                       description="Total country GDP, current international-$")
    population: float = Field(..., ge=1.0e4, le=2.0e9,
                              description="Country population (persons)")
    energy_per_capita: float = Field(..., ge=50.0, le=3.0e5,
                                     description="Primary energy per person (kWh-equivalent)")
    energy_per_gdp: float = Field(..., ge=0.01, le=15.0,
                                  description="Energy intensity (energy per unit GDP)")
    # Energy-mix shares are optional: the pipeline imputes them if missing.
    renewables_share_energy: Optional[float] = Field(
        None, ge=0, le=100, description="% of primary energy from renewables (nullable)")
    fossil_share_energy: Optional[float] = Field(
        None, ge=0, le=100, description="% of primary energy from fossil sources (nullable)")
    low_carbon_share_energy: Optional[float] = Field(
        None, ge=0, le=100, description="% of primary energy from low-carbon sources (nullable)")

    model_config = {
        "json_schema_extra": {
            "example": {  # Indonesia 2013 (matches the notebook's held-out example)
                "gdp": 2437876929100,
                "population": 255852464,
                "energy_per_capita": 7131.105,
                "energy_per_gdp": 0.748,
                "renewables_share_energy": 4.534,
                "fossil_share_energy": 95.466,
                "low_carbon_share_energy": 4.534,
            }
        }
    }


class PredictionResponse(BaseModel):
    predicted_per_capita_electricity_kwh: float
    model_used: str


class RetrainResponse(BaseModel):
    status: str
    message: str
    n_rows_used: int
    test_rmse: float
    test_r2: float
    model_used: str


# ---------------------------------------------------------------------------
# FastAPI app + CORS
# ---------------------------------------------------------------------------
app = FastAPI(
    title="Per-Capita Electricity Prediction API",
    description="Predicts a country's electricity generated per person (kWh) from its "
                "energy & economic profile. Model: Random Forest (Task 1).",
    version="1.0.0",
)

# ---------------------------------------------------------------------------
# CORS — configured deliberately, NOT with a wildcard. Rationale (for the demo):
#
#   allow_origins   : an explicit allow-list, never ["*"]. A browser will only let
#                     these exact origins call the API from JavaScript, so a random
#                     malicious site cannot invoke it on a visitor's behalf. Replace
#                     the placeholder with the real Flutter/web origin at deploy time.
#   allow_methods   : only ["GET", "POST"] — the only verbs this API exposes. We do
#                     not offer PUT/DELETE/PATCH, so we don't advertise them (least
#                     privilege: don't grant capabilities that don't exist).
#   allow_headers   : only ["Content-Type"] — all we need is to let the browser send
#                     JSON / multipart bodies. No custom or auth headers are used, so
#                     none are allowed.
#   allow_credentials=False : we use no cookies, sessions, or browser auth. Keeping it
#                     False means the browser never attaches ambient credentials to
#                     cross-origin calls, closing a CSRF-style risk. (It is also the
#                     only safe pairing with an explicit, non-wildcard origin list.)
#
# Net effect: the smallest surface that still lets our own front-end talk to the API.
# ---------------------------------------------------------------------------
ALLOWED_ORIGINS = [
    "http://localhost:3000",          # local web/Flutter dev
    "http://127.0.0.1:3000",
    "https://REPLACE_WITH_RENDER_URL",  # <-- fill in the real front-end origin at deploy
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
    allow_credentials=False,
)


@app.on_event("startup")
def _load_model_on_startup() -> None:
    """Load the model bundle once, when the server starts (not per request)."""
    try:
        STATE["bundle"] = load_bundle()
    except FileNotFoundError:
        # Leave as None; endpoints will surface a clear 503 until a model exists.
        STATE["bundle"] = None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/")
def health() -> dict:
    """Health check + which model is loaded."""
    bundle = STATE["bundle"]
    return {
        "status": "ok",
        "model_loaded": bundle is not None,
        "model_used": (bundle or {}).get("model_name"),
        "target": (bundle or {}).get("target", TARGET),
        "expected_features": FEATURES,
    }


@app.post("/predict", response_model=PredictionResponse)
def predict(request: PredictionRequest) -> PredictionResponse:
    """Predict per-capita electricity (kWh) from 7 raw feature values.

    Pydantic validates types & ranges automatically -> malformed input returns 422.
    """
    bundle = STATE["bundle"]
    if bundle is None:
        raise HTTPException(status_code=503, detail="Model not loaded. Train a model first.")
    pred = predict_per_capita_electricity(request.model_dump(), bundle=bundle)
    return PredictionResponse(
        predicted_per_capita_electricity_kwh=round(pred, 2),
        model_used=bundle.get("model_name", "unknown"),
    )


@app.post("/retrain", response_model=RetrainResponse)
async def retrain(file: UploadFile = File(...)) -> RetrainResponse:
    """Retrain the pipeline on an uploaded CSV and overwrite best_model.pkl.

    The CSV must contain the 7 feature columns + the target column
    (`per_capita_electricity`). We apply the same cleaning (drop rows missing CORE
    features / target), refit the exact Task-1 pipeline, evaluate on a held-out split,
    save the new bundle, and hot-swap it into memory.
    """
    if not file.filename.lower().endswith(".csv"):
        raise HTTPException(status_code=422, detail="Please upload a .csv file.")
    try:
        df = pd.read_csv(file.file)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=422, detail=f"Could not parse CSV: {exc}")

    required = FEATURES + [TARGET]
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise HTTPException(
            status_code=422,
            detail=f"CSV is missing required column(s): {missing}. "
                   f"Expected columns: {required}",
        )

    # Same cleaning as Task 1: keep rows with all CORE features + a target value.
    df = df.dropna(subset=CORE + [TARGET])
    if len(df) < 20:
        raise HTTPException(
            status_code=422,
            detail=f"Only {len(df)} valid rows after cleaning; need at least 20 to retrain.",
        )

    X, y = df[FEATURES].copy(), df[TARGET].astype(float).values
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.20, random_state=RANDOM_STATE)

    pipeline = build_pipeline().fit(X_train, y_train)
    preds = pipeline.predict(X_test)
    rmse = float(np.sqrt(mean_squared_error(y_test, preds)))
    r2 = float(r2_score(y_test, preds))

    new_bundle = {
        "pipeline": pipeline,
        "model_name": "Random Forest (retrained)",
        "features": FEATURES,
        "target": TARGET,
        "test_rmse": round(rmse, 2),
        "test_r2": round(r2, 4),
    }
    joblib.dump(new_bundle, MODEL_PATH, compress=3)  # overwrite the saved model
    STATE["bundle"] = new_bundle                     # hot-swap in memory

    return RetrainResponse(
        status="success",
        message=f"Model retrained on {len(df)} rows and saved to {MODEL_PATH.name}.",
        n_rows_used=len(df),
        test_rmse=round(rmse, 2),
        test_r2=round(r2, 4),
        model_used=new_bundle["model_name"],
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("prediction:app", host="0.0.0.0", port=8000, reload=True)
