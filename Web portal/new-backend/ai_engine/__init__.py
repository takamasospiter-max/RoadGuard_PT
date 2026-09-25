"""RoadGuard's in-process AI engine: the AI team's sensor model, plugged into the backend.

Turn it on in `.env`:

    ROADGUARD_AI_ENGINE=ai_engine.sensor_model.PotholeEngine

What happens to each uploaded sensor batch (detection/pipeline.py calls analyze()):

    readings (phone, ~10 Hz, accelerometer + gyroscope + GPS, separate events)
        │  preprocessing.py   pair them up on a 5 Hz clock, m/s² → g, turn to training orientation
        ▼
    2-second windows (10 points)
        │  features.py        the 34 numbers the model was trained on
        ▼
    Random Forest (models/pothole_model_bundle.pkl)  →  pothole probability
        │  sensor_model.py    threshold, time/place of the jolt, hit strength
        ▼
    DetectionResult(s)  →  detection/spots.py groups phones into spots

The model and how it was trained: models/MODEL.md.
"""
