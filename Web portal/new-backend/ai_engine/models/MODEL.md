# Sensor model: `pothole_model_bundle.pkl`

| | |
|---|---|
| **What** | Random Forest (scikit-learn **1.9.1**, 300 trees, `min_samples_leaf=2`, `max_features="sqrt"`) that says whether a 2-second window of phone motion contains a pothole |
| **From** | The AI team's notebook `ai/Intelligent-Pothole-Detection/Pothole_Detection.ipynb`, cell 17 ("Champion Model Training … Production Packaging"), trained 2026-09-24 |
| **SHA-256** | `2c2e9ec7bdc05113b4058419bf398d207097eae0bb413f003460d00b1810d3bc` (checked before loading; see `ROADGUARD_AI_MODEL_SHA256`) |
| **Version stored with detections** | `rf34-balanced-2026-09-24+2c2e9ec7` |
| **Training data** | Carnegie Mellon's public 2017 iPhone dataset: 5 trips in Pittsburgh, USA (`data/Pothole_Non_Pothole/trip1–5`). 983 windows, **79 with a pothole**. Pothole windows were multiplied synthetically (Borderline-SMOTE) to 904, giving 1,808 training samples |
| **Validation (AI team)** | Trip-grouped cross-validation: ROC-AUC 0.92, PR-AUC 0.48; at the chosen threshold **0.37**: precision 0.43, recall 0.75, F1 0.55 |

## What the model reads

Each window is **10 readings at 5 Hz** (2 seconds). The engine computes 34 features (`ai_engine/features.py`, copied from notebook cells 3 and 19):

- `meanSpeed`, `sdSpeed`: GPS speed in **metres per second**
- max, min, mean and sample standard deviation of:
  - accelerometer X, Y, Z in **g, gravity included** (a phone at rest reads about 1 g)
  - gyroscope X, Y, Z in **rad/s**
  - the totals √(x² + y² + z²) of both
- The model's speed gate: windows averaging under **10 km/h** (2.78 m/s) are skipped

The training phones stood **upright in portrait**: gravity averaged (0.05, −0.97, 0.24) g on the phone's X, Y, Z axes.

## How the phone's data is adapted (`ai_engine/preprocessing.py`)

| Phone (RoadGuard app, notice v2) | Model | Adaptation |
|---|---|---|
| Accelerometer and gyroscope as separate events, ~10 Hz | One row per 0.2 s | Each 0.2 s tick takes each sensor's nearest **actual** reading (no blending: it flattens jolts) |
| m/s² | g | ÷ 9.80665 |
| Phone held any way | Upright portrait | Each window is turned so its gravity points as in training (`ROADGUARD_AI_ALIGN_GRAVITY`) |
| Speed m/s | m/s | none |

## What the engine outputs (`ai_engine/sensor_model.py`)

For each window at or above 0.37:
- **time and place:** the strongest jolt in the window
- **confidence:** the model's probability
- **hit strength** (0–1): the jolt size, 0.1 g → 0 and 0.8 g → 1. This is a provisional formula.

Windows follow a fixed 2-second clock and don't overlap, as in training. Detections less than 2 s apart are merged.

## Measured end to end (2026-09-25)

The five training trips (13.5 km) were replayed through the full engine the way the app uploads data. Results:
- 92 of 96 marked potholes found
- about **2 false alarms per km** per phone, after merging

The model has seen these trips, so this is the *best case*. Real Tanzanian roads and Android phones will do worse until the model is retrained on local data. The crowd rule protects drivers from single-phone false alarms: 3 different phones must agree before drivers are alerted.

## Replacing the model

1. Put the new file here, or point `ROADGUARD_AI_MODEL_PATH` at it.
2. Set `ROADGUARD_AI_MODEL_SHA256` to its checksum: `python -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" <file>`.
3. If the features, window or sampling changed, update `features.py` / `preprocessing.py`, since the engine refuses a bundle whose `feature_columns`, `window_size_points` or `sampling_frequency_hz` don't match.
4. Install the scikit-learn version it was saved with (`requirements.txt`). A mismatch is refused.
5. Update `model_version` in `sensor_model.py`, then run `python manage.py test ai_engine`.

---

# Photo model: `yolo-best.pt`

| | |
|---|---|
| **What** | YOLOv8 object detector (Ultralytics **8.4.159**, AGPL-3.0) with one class, `pothole`. It draws a box around each pothole it sees in a photo |
| **Trained** | 2026-09-22 by the AI team: 30 epochs at image size **320** px |
| **Validation (AI team)** | mAP50 0.55, precision 0.52, recall 0.54 |
| **SHA-256** | `01a4ad3e18deed8bdcf8b2564b0449755b2d52be675b45d764f33142a40d0fc4` (checked before loading; see `ROADGUARD_PHOTO_MODEL_SHA256`) |
| **Version stored with results** | `yolov8-pothole-320+01a4ad3e` |
| **Code** | `ai_engine/photo_model.py` |

## How RoadGuard uses it

With `ROADGUARD_PHOTO_CHECK=True`, each traveller's report photo is checked once the report is submitted (`mobile/reports.py`). The photo is the sanitized JPEG, already turned upright. The result is saved on the photo (`ReportPhoto.ai_*`). The portal shows it next to the photo as `photo_check`, with the potholes outlined.

- It is **advice for the officer only**. It never changes a report's status or severity, and never decides whether drivers are warned.
- Boxes below `ROADGUARD_PHOTO_MIN_CONFIDENCE` (0.25, Ultralytics' default; provisional) are dropped.
- With recall 0.54 the model misses about half of potholes, so "no pothole recognised" is not evidence that there is none.
- It also gives false alarms on photos unlike its training data. On 2026-09-28 it outlined the ceiling and a desk in an indoor test photo, at 66 % and 35 %. So "pothole found" is not proof either.
- A failed check never rejects a report. It is recorded, and `python manage.py check_report_photos --retry-failed` retries it.
- Photos submitted while the check was off: `python manage.py check_report_photos`.

The first check after the server starts takes a few seconds while torch and the model load. After that, one photo takes a fraction of a second on the CPU.

## Replacing the model

1. Put the new file here, or point `ROADGUARD_PHOTO_MODEL_PATH` at it.
2. Set `ROADGUARD_PHOTO_MODEL_SHA256` to its checksum (same command as above). A `.pt` file is a pickle, so a file that doesn't match is never opened.
3. It must still have exactly one class, `pothole`. If it was trained at a different image size, change `IMAGE_SIZE` in `photo_model.py`.
4. Re-check old photos if you want: `python manage.py check_report_photos --all`. Then run `python manage.py test ai_engine`.
