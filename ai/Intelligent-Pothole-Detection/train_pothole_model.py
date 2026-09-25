"""Train and validate a sensor-based pothole detector.

This trainer keeps complete trips together during validation so that the
reported score better represents performance on a new route.
"""

from pathlib import Path
import pickle

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.model_selection import GroupKFold, cross_val_predict


ROOT = Path(__file__).resolve().parent
DATA_DIR = ROOT / "data" / "Pothole_Non_Pothole"
MODEL_PATH = ROOT / "pothole_rf_model.pkl"

FEATURES = [
    "maxAccelX", "maxAccelY", "maxAccelZ",
    "maxGyroX", "maxGyroY", "maxGyroZ",
    "minAccelX", "minAccelY", "minAccelZ",
    "minGyroX", "minGyroY", "minGyroZ",
    "meanAccelX", "meanAccelY", "meanAccelZ",
    "meanGyroX", "meanGyroY", "meanGyroZ",
    "sdAccelX", "sdAccelY", "sdAccelZ",
    "sdGyroX", "sdGyroY", "sdGyroZ",
]


def load_intervals() -> pd.DataFrame:
    frames = []
    for trip in range(1, 6):
        path = DATA_DIR / f"trip{trip}_intervals.csv"
        frame = pd.read_csv(path).drop(columns=["Unnamed: 0"], errors="ignore")
        frame = frame.dropna(subset=FEATURES + ["pothole"]).copy()
        frame["trip"] = trip
        frames.append(frame)
    return pd.concat(frames, ignore_index=True)


def choose_threshold(y_true: pd.Series, scores: np.ndarray) -> float:
    """Choose the threshold with the best F1, preferring useful recall."""
    candidates = np.arange(0.10, 0.81, 0.01)
    results = []
    for threshold in candidates:
        predicted = scores >= threshold
        results.append(
            (
                f1_score(y_true, predicted, zero_division=0),
                recall_score(y_true, predicted, zero_division=0),
                threshold,
            )
        )
    # F1 is the primary objective; recall breaks ties in favour of detection.
    return max(results)[2]


def main() -> None:
    data = load_intervals()
    x = data[FEATURES]
    y = data["pothole"].astype(int)
    groups = data["trip"]

    model = RandomForestClassifier(
        n_estimators=600,
        class_weight="balanced",
        min_samples_leaf=2,
        max_features="sqrt",
        random_state=42,
        n_jobs=-1,
    )

    # Out-of-fold predictions are made on trips never used for fitting.
    cv = GroupKFold(n_splits=data["trip"].nunique())
    scores = cross_val_predict(
        model, x, y, groups=groups, cv=cv, method="predict_proba", n_jobs=1
    )[:, 1]
    threshold = choose_threshold(y, scores)
    predicted = (scores >= threshold).astype(int)

    print(f"Intervals: {len(data)}; pothole intervals: {int(y.sum())}")
    print(f"Trip-grouped OOF average precision: {average_precision_score(y, scores):.3f}")
    print(f"Selected threshold: {threshold:.2f}")
    print(f"OOF accuracy: {accuracy_score(y, predicted):.3f}")
    print(classification_report(y, predicted, target_names=["normal", "pothole"]))
    print("Confusion matrix:")
    print(confusion_matrix(y, predicted))

    model.fit(x, y)
    artifact = {
        "classifier": model,
        "features": FEATURES,
        "threshold": float(threshold),
        "window_seconds": 2,
        "sampling_points_per_second": 5,
    }
    with MODEL_PATH.open("wb") as file:
        pickle.dump(artifact, file, protocol=pickle.HIGHEST_PROTOCOL)
    print(f"Saved model to {MODEL_PATH}")


if __name__ == "__main__":
    main()
