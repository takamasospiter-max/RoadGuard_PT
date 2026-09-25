# Intelligent-Pothole-Detection
A system for real-time pothole detection. Jupyter notebooks documenting data collection, EDA, and classification, a realtime iPhone classifier, as well as a paper of our results. 

## Trial model

For a reproducible trial model with route-safe validation, run:

```bash
./.venv/bin/python train_pothole_model.py
```

The trainer keeps each trip in one validation fold, selects a threshold from
out-of-fold predictions, and saves `pothole_rf_model.pkl`. This is intended for
field trials; validate detections against video or manual road inspection before
using it for operational decisions.

## /app: 
  data and files that comprise a realtime iOS classifier built from our classification work
  
##  /data :
  all the data we collected, in CSV format

## /deprecated_notebooks: 
  separate notebooks for data processing, EDA, and classification, prior to their combining 

## /website_visualization:
  a javascript visualization of the route we took when collecting data. 
