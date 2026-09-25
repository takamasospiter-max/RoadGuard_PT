# AI engine contract

How the pothole-detection AI engine plugs into the RoadGuard backend (`new-backend/`).
The backend handles everything around the model: collecting sensor data from phones, handing it to the model, storing what the model finds, combining the finds of many drivers into monitored spots, rating their severity, and alerting other drivers. **The model only answers one question per batch: "where and when did this phone hit a pothole?"**

```
 phone sensors ──► TelemetryBatch (pending) ──► AI engine ──► Detection(s)
                                                                  │
                                    detection/spots.py: group by location, count phones
                                                                  │
                        Defect (source "device") in the portal ◄──┘ ──► alerts to drivers
```

## 1. The input: sensor batches

While a signed-in driver shares sensor data, the app uploads a **batch** about every 2 seconds. Each batch holds up to 20 readings, taken at a requested 10 Hz:

| Field | Meaning |
|---|---|
| `kind` | `acceleration`: raw accelerometer **with gravity**, in m/s² (app notice v2, from 2026-09-25). `angular_velocity`: gyroscope, in rad/s. Older app versions sent `linear_acceleration` (gravity removed) instead |
| `recordedAt` | When the sample was taken (UTC, ISO 8601) |
| `x`, `y`, `z` | The three axes **in the phone's own frame**. The phone can sit in any orientation, so the model must not assume `z` is vertical (e.g. use the magnitude, or estimate orientation) |
| `latitude`, `longitude` | GPS position at that moment (WGS84) |
| `speedMps` | GPS speed, in m/s |
| `gpsAccuracyMeters` | GPS accuracy radius. It's always ≤ 25 m, because worse fixes are rejected |

The backend guarantees that GPS readings are real (not mocked), accurate to within 25 m, at most 10 s older than the sensor sample, and captured while the driver's consent was active.

**Context.** A pothole hit can straddle two uploads, so every batch comes with `context`: the same trip's readings from the **5 seconds before** the batch. Use it to see the whole jolt, but **report detections only for moments inside the batch's own `readings`**, or the same hit will be reported twice.

## 2. The output: detections

For each pothole found, return:

| Field | Required | Meaning |
|---|---|---|
| `detectedAt` | yes | When the hit happened (UTC). It must lie within the batch's time span, ±2 s |
| `latitude`, `longitude` | yes | Where. It must be within **150 m** of the batch's GPS positions |
| `confidence` | yes | 0–1: how sure the model is. Below `SPOT_MIN_CONFIDENCE` (default 0.5), the detection is stored but doesn't count towards spots |
| `intensity` | recommended | 0–1: how hard the hit was. This drives the spot's **severity** |
| `severity` | optional | `low` / `medium` / `high`, used when `intensity` isn't given (treated as 0.25 / 0.55 / 0.85) |
| `hazardType` | optional | `Pothole`, the default and the only accepted value (road cracks are out of scope) |

Return **no detections** (an empty list) when the batch is smooth road. That's the normal case.

Every detection is stored with the `modelVersion` you report, so results can always be traced back to the model that produced them.

## 3. Two ways to connect

> **Connected (2026-09-25):** the AI team's sensor model runs through Option A as `ai_engine.sensor_model.PotholeEngine`. See `ai_engine/models/MODEL.md` for how the phone's data is adapted to it.

### Option A: in-process Python class

Suits a model written in Python that can run inside the Django server.

```python
# ai_engine/model.py  (anywhere importable by the backend)
from detection.engine import DetectionEngine, DetectionResult

class PotholeEngine(DetectionEngine):
    model_version = 'roadguard-cnn-0.1'

    def __init__(self):
        self.model = load_my_model('weights.pt')      # load once, reused for every batch

    def analyze(self, batch):                         # batch: detection.engine.BatchInput
        # batch.readings / batch.context: lists of Reading(kind, recorded_at, x, y, z,
        #                                   lat, lng, speed_mps, gps_accuracy_m)
        hits = self.model.find_potholes(batch.context + batch.readings)
        return [DetectionResult(detected_at=h.time, latitude=h.lat, longitude=h.lng,
                                confidence=h.p, intensity=h.strength)
                for h in hits if h.time >= batch.readings[0].recorded_at]
```

Then, in `new-backend/.env`:

```
ROADGUARD_AI_ENGINE=ai_engine.model.PotholeEngine
```

and either run `python manage.py process_telemetry --loop 10` alongside the server, or set `ROADGUARD_AI_PROCESS_INLINE=True` to analyse each batch as it arrives. An exception in `analyze()` marks only that batch as `failed` (with the error text), and the next batches carry on.

### Option B: separate service over HTTP

Suits any language or framework, or a model that needs its own GPU machine.

1. Set a long random key in `new-backend/.env`: `ROADGUARD_AI_API_KEY=...`. With no key, these endpoints are switched off.
2. The service sends `Authorization: Api-Key <key>` on every call and loops:

```http
POST /api/v1/ai/batches/claim/
{"limit": 10}

→ 200 {"batches": [{
        "batchId": "978b0193-...", "tripId": "...", "receivedAt": "2026-09-24T16:56:10Z",
        "readings": [{"kind": "linear_acceleration", "recordedAt": "...", "x": 0.2, "y": 0.1, "z": 9.5,
                      "latitude": -6.7924, "longitude": 39.2083, "speedMps": 12.0, "gpsAccuracyMeters": 5.0}, ...],
        "context":  [ ...same shape, the 5 s before... ]
      }]}
```

```http
POST /api/v1/ai/batches/978b0193-.../results/
{"modelVersion": "roadguard-cnn-0.1",
 "detections": [{"detectedAt": "2026-09-24T16:56:09.400Z", "latitude": -6.79238, "longitude": 39.2083,
                 "confidence": 0.85, "intensity": 0.8}]}

→ 200 {"batchId": "978b0193-...", "saved": 1, "status": "done"}
```

If the model fails on a batch, send `{"modelVersion": "...", "error": "what went wrong"}` instead of detections.

| Situation | Reply |
|---|---|
| Missing or wrong key, or the API is switched off | 401 |
| Posting results for a batch that wasn't claimed (or was already answered) | 409 |
| A detection outside the batch's time span or location, or values out of range | 400. Nothing from that post is saved; fix and post again |
| A claimed batch gets no answer within 10 minutes | It's offered again by the next claim |

`GET /api/v1/ai/status/` returns how many batches are pending, processing, done or failed. It's useful as a health check.

## 4. What happens after a detection

`detection/spots.py` takes over. All numbers below are settings in `.env`:

- **Grouping:** detections within `SPOT_RADIUS_M` (15 m) of each other are treated as the same pothole. A detection near an existing open defect joins it, including a traveller's photo report.
- **Tracking:** once `SPOT_MIN_DEVICES_TO_TRACK` (2) **different phones** agree, a defect (source "device", status "New") appears in the portal for officers to monitor.
- **Driver alerts:** once `SPOT_MIN_DEVICES_TO_PUBLISH` (3) different phones agree, the spot is alerted to drivers as "reported by drivers, not yet verified". When an officer marks it Verified, it becomes "confirmed".
- **The spot's numbers:**
  - `confidence` combines the phones' confidences: 1 − Π(1 − best confidence per phone).
  - `severity_score` is the confidence-weighted average `intensity`, which maps to low (< 0.4), medium (< 0.7) or high.
  - The position is the confidence-weighted centre.
- **Expiry:** a crowd-only spot with no new detection for `SPOT_STALE_DAYS` (30) days stops being alerted.
- **Phones are counted by account:** each phone is identified by a keyed hash of the traveller account, so the backend can count distinct phones without storing who they are.

## 5. Testing without the model

```
python manage.py simulate_detections --lat -6.7924 --lng 39.2083 --devices 3 --intensity 0.8
```

This creates flagged, simulated detections from 3 fake phones. The resulting spot shows in the portal but is only alerted to drivers if `ROADGUARD_PUBLISH_SIMULATED=True`, which is for development only.

The automated tests in `detection/tests.py` show both connection options working end to end.
