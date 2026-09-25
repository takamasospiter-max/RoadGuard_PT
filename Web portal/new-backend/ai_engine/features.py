"""The 34 numbers the sensor model reads for each 2-second window.

This is a line-by-line copy of the AI team's feature code in
`ai/Intelligent-Pothole-Detection/Pothole_Detection.ipynb`:
cell 3 (`build_dataset`, used for training) and cell 19
(`predict_pothole_stream`, used for live prediction). If the model is
retrained with different features, this file must change with it; the
tests in ai_engine/tests.py check it still reproduces the notebook.

Inputs for one window of 10 points (5 Hz), exactly as in training:
- speed:  metres per second
- accel:  accelerometer X/Y/Z in g (1 g = 9.80665 m/s²), gravity included
- gyro:   gyroscope X/Y/Z in radians per second
"""

import numpy as np

# The order the model expects: the same list as the bundle's `feature_columns`
# (and the classifier's `feature_names_in_`); checked when the model loads.
FEATURE_COLUMNS = [
    'meanSpeed', 'sdSpeed',
    'maxAccelX', 'minAccelX', 'meanAccelX', 'sdAccelX',
    'maxAccelY', 'minAccelY', 'meanAccelY', 'sdAccelY',
    'maxAccelZ', 'minAccelZ', 'meanAccelZ', 'sdAccelZ',
    'maxGyroX', 'minGyroX', 'meanGyroX', 'sdGyroX',
    'maxGyroY', 'minGyroY', 'meanGyroY', 'sdGyroY',
    'maxGyroZ', 'minGyroZ', 'meanGyroZ', 'sdGyroZ',
    'maxAccelMag', 'minAccelMag', 'meanAccelMag', 'sdAccelMag',
    'maxGyroMag', 'minGyroMag', 'meanGyroMag', 'sdGyroMag',
]


def _stats(values):
    """max, min, mean and standard deviation, in that order.

    ddof=1: the *sample* standard deviation, which is what pandas'
    `.std()` computes in the notebook (numpy's default would be ddof=0).
    """
    return [values.max(), values.min(), values.mean(), values.std(ddof=1)]


def window_features(speed, accel, gyro):
    """The 34 features of one window, in FEATURE_COLUMNS order.

    speed: shape (n,); accel, gyro: shape (n, 3). n is 10 for the model.
    """
    speed = np.asarray(speed, dtype=float)
    accel = np.asarray(accel, dtype=float)
    gyro = np.asarray(gyro, dtype=float)
    # "Orientation-invariant" totals: the length of each 3-D vector.
    accel_mag = np.sqrt((accel ** 2).sum(axis=1))
    gyro_mag = np.sqrt((gyro ** 2).sum(axis=1))

    row = [speed.mean(), speed.std(ddof=1) if len(speed) > 1 else 0.0]
    for signal in (accel[:, 0], accel[:, 1], accel[:, 2],
                   gyro[:, 0], gyro[:, 1], gyro[:, 2],
                   accel_mag, gyro_mag):
        row.extend(_stats(signal))
    return np.array(row)
