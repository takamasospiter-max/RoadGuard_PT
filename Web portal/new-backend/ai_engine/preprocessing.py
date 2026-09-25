"""Turn the phone's raw readings into what the model was trained on.

The phone and the training data differ in three ways; this file bridges them:

1. Timing. The app records the accelerometer and the gyroscope as separate
   events at about 10 Hz each, at slightly different moments. The training
   data has one row per 0.2 s (5 Hz) with both sensors. So both are put on a
   shared 5 Hz clock by taking, for each tick, the sensor's *actual reading*
   nearest to it. Readings are deliberately not blended (interpolated): the
   training rows were real instantaneous readings, and blending flattens the
   short, sharp peak of a pothole jolt, which the model relies on (in testing,
   interpolation turned a 0.86 pothole into 0.12). The clock is anchored to the
   epoch (ticks at whole multiples of 0.2 s), so consecutive batches of the
   same trip land on the same ticks and windows line up across uploads.
2. Units. The app sends m/s²; training used g (1 g = 9.80665 m/s²).
3. Phone orientation. Training phones stood upright in portrait, so gravity
   pulled mostly along −Y. Drivers hold phones any way, so each window can be
   turned (rotated) until its gravity points the same way as in training.
   Totals (magnitudes) are unaffected; the per-axis numbers become comparable.
   Turning around the vertical is unknown and left as it is.
"""

import math
from dataclasses import dataclass

import numpy as np

STANDARD_GRAVITY = 9.80665   # m/s² in 1 g
SAMPLE_SECONDS = 0.2         # 5 Hz, as in the training data
# A tick is only filled in if the sensor has a reading at most this far from it
# (half a tick); otherwise there's a gap (e.g. the app was paused), which
# breaks any window containing it.
MAX_OFFSET_SECONDS = SAMPLE_SECONDS / 2 + 1e-3
# Average direction of gravity in the 5 training trips (unit vector, phone axes):
# upright portrait, tilted back about 14°. Measured from
# ai/Intelligent-Pothole-Detection/data/Pothole_Non_Pothole/trip1-5_sensors.csv.
TRAINING_GRAVITY_DIRECTION = np.array([0.0520, -0.9698, 0.2383])
GYRO_KIND = 'angular_velocity'


@dataclass
class Timeline:
    """One trip stretch on the shared 5 Hz clock (all arrays have one row per tick)."""
    ticks: np.ndarray    # integer tick numbers: time = tick × 0.2 s since the epoch
    times: np.ndarray    # seconds since the epoch (UTC)
    accel: np.ndarray    # (n, 3) in g
    gyro: np.ndarray     # (n, 3) in rad/s
    speed: np.ndarray    # m/s, from the GPS fix attached to the nearest reading
    lat: np.ndarray
    lng: np.ndarray
    valid: np.ndarray    # False where a sensor had no reading within half a tick


def _series(readings, kind):
    """Times (s) and x/y/z values of one sensor, sorted by time, duplicates dropped."""
    rows = sorted((r.recorded_at.timestamp(), r.x, r.y, r.z) for r in readings if r.kind == kind)
    if not rows:
        return np.empty(0), np.empty((0, 3))
    data = np.array(rows)
    # Strictly increasing times for the nearest-reading search; keep the first of equal ones.
    keep = np.concatenate(([True], np.diff(data[:, 0]) > 0))
    return data[keep, 0], data[keep, 1:]


def _nearest(times, grid):
    """For each tick: the index of the reading nearest in time (ties → the earlier one)."""
    after = np.clip(np.searchsorted(times, grid), 0, len(times) - 1)
    before = np.clip(after - 1, 0, len(times) - 1)
    use_before = np.abs(times[before] - grid) <= np.abs(times[after] - grid)
    return np.where(use_before, before, after)


def build_timeline(readings, accel_kind):
    """Resample readings to the 5 Hz clock, or None if there isn't enough data.

    accel_kind: which accelerometer readings to use ("acceleration" = raw,
    gravity included, like the training data; or "linear_acceleration").
    """
    t_acc, acc = _series(readings, accel_kind)
    t_gyr, gyr = _series(readings, GYRO_KIND)
    if len(t_acc) < 2 or len(t_gyr) < 2:
        return None

    # Only the stretch where both sensors have data.
    first = math.ceil((max(t_acc[0], t_gyr[0]) - MAX_OFFSET_SECONDS) / SAMPLE_SECONDS)
    last = math.floor((min(t_acc[-1], t_gyr[-1]) + MAX_OFFSET_SECONDS) / SAMPLE_SECONDS)
    if last < first:
        return None
    ticks = np.arange(first, last + 1)
    grid = ticks * SAMPLE_SECONDS

    i_acc, i_gyr = _nearest(t_acc, grid), _nearest(t_gyr, grid)
    accel = acc[i_acc] / STANDARD_GRAVITY
    gyro = gyr[i_gyr]
    valid = ((np.abs(t_acc[i_acc] - grid) <= MAX_OFFSET_SECONDS)
             & (np.abs(t_gyr[i_gyr] - grid) <= MAX_OFFSET_SECONDS))

    # GPS: every reading carries the fix taken with it; use the nearest one in time.
    gps = np.array(sorted((r.recorded_at.timestamp(), r.speed_mps, r.lat, r.lng) for r in readings))
    nearest = _nearest(gps[:, 0], grid)

    return Timeline(ticks=ticks, times=grid, accel=accel, gyro=gyro,
                    speed=gps[nearest, 1], lat=gps[nearest, 2], lng=gps[nearest, 3], valid=valid)


def rotation_between(a, b):
    """The 3×3 rotation that turns direction `a` into direction `b` (Rodrigues' formula)."""
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    axis = np.cross(a, b)
    sin, cos = np.linalg.norm(axis), float(np.dot(a, b))
    if sin < 1e-9:
        if cos > 0:
            return np.eye(3)  # already pointing the same way
        # Opposite directions: half a turn around any axis at right angles to `a`.
        helper = np.array([1.0, 0, 0]) if abs(a[0]) < 0.9 else np.array([0, 1.0, 0])
        perpendicular = np.cross(a, helper)
        perpendicular /= np.linalg.norm(perpendicular)
        return 2 * np.outer(perpendicular, perpendicular) - np.eye(3)
    k = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return np.eye(3) + k + k @ k * ((1 - cos) / sin ** 2)


def align_to_training(accel, gyro):
    """Turn one window so its gravity points like in training; returns (accel, gyro).

    Gravity is estimated as the window's average acceleration. If that is
    too small to tell a direction (e.g. gravity-removed readings), the window
    is returned unchanged.
    """
    gravity = accel.mean(axis=0)
    if np.linalg.norm(gravity) < 0.5:   # less than half a g: no reliable direction
        return accel, gyro
    turn = rotation_between(gravity, TRAINING_GRAVITY_DIRECTION)
    # Rows are vectors, so apply the rotation from the right (v' = R·v).
    return accel @ turn.T, gyro @ turn.T
