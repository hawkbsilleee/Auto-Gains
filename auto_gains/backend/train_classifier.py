"""
Exercise classifier for IMU accelerometer data.
Distinguishes between shoulder press and bicep curl using PCA and statistical features.
Uses sliding windows to build training samples from labeled sequences.
"""

import numpy as np
from pathlib import Path
import joblib
from sklearn.decomposition import PCA
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline

# Default path for saved model (relative to this file's directory)
DEFAULT_MODEL_PATH = Path(__file__).resolve().parent / "classifier_model.joblib"


# Label constants
SHOULDER_PRESS = "shoulder_press"
BICEP_CURL = "bicep_curl"
EXERCISE_LABELS = [BICEP_CURL, SHOULDER_PRESS]


def load_imu_file(path: str) -> np.ndarray:
    """Load accelerometer data from a text file (space-separated x y z per line)."""
    data = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            values = line.split()
            if len(values) >= 3:
                data.append([float(values[0]), float(values[1]), float(values[2])])
    return np.array(data)


def extract_window_features(window: np.ndarray) -> np.ndarray:
    """
    Extract a feature vector from one window of shape (n_samples, 3).
    Uses PCA (like IMU_Static.ipynb) plus per-axis and magnitude statistics.
    """
    # Per-axis statistics
    mean_x, mean_y, mean_z = window.mean(axis=0)
    std_x, std_y, std_z = window.std(axis=0)
    range_x = window[:, 0].max() - window[:, 0].min()
    range_y = window[:, 1].max() - window[:, 1].min()
    range_z = window[:, 2].max() - window[:, 2].min()

    # Magnitude (L2 norm per sample) statistics
    mag = np.linalg.norm(window, axis=1)
    mag_mean = mag.mean()
    mag_std = mag.std()
    mag_range = mag.max() - mag.min()

    # PCA on this window: variance structure differs by exercise
    pca = PCA(n_components=3)
    pca.fit(window)
    var_ratio_1, var_ratio_2, var_ratio_3 = pca.explained_variance_ratio_
    # First component direction (which axis dominates motion)
    pc1_loadings = np.abs(pca.components_[0])

    features = [
        mean_x, mean_y, mean_z,
        std_x, std_y, std_z,
        range_x, range_y, range_z,
        mag_mean, mag_std, mag_range,
        var_ratio_1, var_ratio_2, var_ratio_3,
        pc1_loadings[0], pc1_loadings[1], pc1_loadings[2],
    ]
    return np.array(features, dtype=np.float64)


def windows_from_sequence(data: np.ndarray, window_size: int, step: int):
    """Yield overlapping windows of shape (window_size, 3)."""
    n = len(data)
    for start in range(0, n - window_size + 1, step):
        yield data[start : start + window_size]


# Subfolder under data_dir where labeled training data lives
TRAINING_DATA_DIR = "training_data"


def get_labeled_imu_files(data_dir: str | Path):
    """
    Find all .txt IMU data files and their labels.
    Returns list of (path, label) where label is SHOULDER_PRESS or BICEP_CURL.

    - Files in data_dir/training_data/shoulders/ -> shoulder_press
    - Files in data_dir/training_data/bicep/ -> bicep_curl
    - Files in data_dir with 'shoulder' or 'bicep' in filename -> label by name
    """
    data_dir = Path(data_dir)
    labeled = []
    training_dir = data_dir / TRAINING_DATA_DIR

    # Subfolders: training_data/shoulders/ and training_data/bicep/
    for subdir, label in [("shoulders", SHOULDER_PRESS), ("bicep", BICEP_CURL)]:
        folder = training_dir / subdir
        if folder.is_dir():
            for path in folder.glob("*.txt"):
                labeled.append((path, label))

    # Root: infer from filename
    for path in data_dir.glob("*.txt"):
        if path in (p for p, _ in labeled):
            continue
        name_lower = path.name.lower()
        if "shoulder" in name_lower:
            labeled.append((path, SHOULDER_PRESS))
        elif "bicep" in name_lower:
            labeled.append((path, BICEP_CURL))

    return labeled


def build_dataset(
    shoulder_path: str,
    bicep_path: str,
    window_size: int = 80,
    step: int = 40,
):
    """
    Build feature matrix X and labels y from the two exercise files.
    Each window is one sample; label is the exercise that sequence came from.
    """
    shoulder_data = load_imu_file(shoulder_path)
    bicep_data = load_imu_file(bicep_path)

    X_list = []
    y_list = []

    for window in windows_from_sequence(shoulder_data, window_size, step):
        feat = extract_window_features(window)
        X_list.append(feat)
        y_list.append(SHOULDER_PRESS)

    for window in windows_from_sequence(bicep_data, window_size, step):
        feat = extract_window_features(window)
        X_list.append(feat)
        y_list.append(BICEP_CURL)

    X = np.array(X_list)
    y = np.array(y_list)
    return X, y


def build_dataset_from_dir(
    data_dir: str | Path,
    window_size: int = 80,
    step: int = 40,
):
    """
    Build feature matrix X and labels y from all labeled IMU .txt files in data_dir.
    Labels are inferred from filename: 'shoulder' -> shoulder_press, 'bicep' -> bicep_curl.
    """
    labeled = get_labeled_imu_files(data_dir)
    if not labeled:
        raise FileNotFoundError(
            f"No labeled IMU files in {data_dir}. "
            f"Put .txt files in {TRAINING_DATA_DIR}/shoulders/ or {TRAINING_DATA_DIR}/bicep/, or use filenames containing 'shoulder' or 'bicep'."
        )

    X_list = []
    y_list = []
    for path, label in labeled:
        data = load_imu_file(str(path))
        for window in windows_from_sequence(data, window_size, step):
            X_list.append(extract_window_features(window))
            y_list.append(label)

    return np.array(X_list), np.array(y_list), labeled


def train_classifier(
    shoulder_path: str,
    bicep_path: str,
    window_size: int = 80,
    step: int = 40,
):
    """
    Train and return a pipeline (scaler + classifier) and the list of feature names.
    """
    X, y = build_dataset(shoulder_path, bicep_path, window_size=window_size, step=step)

    pipeline = Pipeline([
        ("scaler", StandardScaler()),
        ("clf", RandomForestClassifier(n_estimators=100, random_state=42)),
    ])
    pipeline.fit(X, y)

    feature_names = [
        "mean_x", "mean_y", "mean_z",
        "std_x", "std_y", "std_z",
        "range_x", "range_y", "range_z",
        "mag_mean", "mag_std", "mag_range",
        "pca_var_1", "pca_var_2", "pca_var_3",
        "pc1_load_x", "pc1_load_y", "pc1_load_z",
    ]
    return pipeline, feature_names


def train_classifier_from_dir(
    data_dir: str | Path,
    window_size: int = 80,
    step: int = 40,
):
    """
    Train on all labeled IMU files in data_dir (labels from filenames: shoulder/bicep).
    Uses class_weight='balanced' to avoid biasing toward the majority class.
    Returns (pipeline, feature_names, labeled_files).
    """
    X, y, labeled = build_dataset_from_dir(data_dir, window_size=window_size, step=step)

    pipeline = Pipeline([
        ("scaler", StandardScaler()),
        (
            "clf",
            RandomForestClassifier(
                n_estimators=100,
                random_state=42,
                class_weight="balanced",
            ),
        ),
    ])
    pipeline.fit(X, y)

    feature_names = [
        "mean_x", "mean_y", "mean_z",
        "std_x", "std_y", "std_z",
        "range_x", "range_y", "range_z",
        "mag_mean", "mag_std", "mag_range",
        "pca_var_1", "pca_var_2", "pca_var_3",
        "pc1_load_x", "pc1_load_y", "pc1_load_z",
    ]
    return pipeline, feature_names, labeled


def save_model(pipeline: Pipeline, path: str | Path | None = None, window_size: int = 80, step: int = 40) -> Path:
    """
    Save the trained pipeline and window params to disk.
    Returns the path where the model was saved.
    """
    path = Path(path) if path is not None else DEFAULT_MODEL_PATH
    payload = {
        "pipeline": pipeline,
        "window_size": window_size,
        "step": step,
    }
    joblib.dump(payload, path)
    return path


def load_model(path: str | Path | None = None):
    """
    Load the saved pipeline and params. Returns a dict with keys:
    - 'pipeline': the sklearn Pipeline
    - 'window_size': int
    - 'step': int
    """
    path = Path(path) if path is not None else DEFAULT_MODEL_PATH
    if not path.exists():
        raise FileNotFoundError(f"Model not found at {path}. Run train_classifier.py to train and save.")
    return joblib.load(path)


def classify_exercise(pipeline: Pipeline, data: np.ndarray, window_size: int = 80, step: int = 40) -> str:
    """
    Classify a single sequence of accelerometer data (n_samples, 3).
    Uses majority vote over all windows in the sequence.
    """
    if len(data) < window_size:
        # Too short: use whole sequence as one window
        window_size_use = min(window_size, len(data))
        if window_size_use < 10:
            raise ValueError("Data too short to classify (need at least 10 samples).")
        feats = extract_window_features(data[:window_size_use])
        X = np.array([feats])
        return pipeline.predict(X)[0]

    X_list = []
    for window in windows_from_sequence(data, window_size, step):
        X_list.append(extract_window_features(window))
    X = np.array(X_list)
    preds = pipeline.predict(X)
    # Majority vote
    unique, counts = np.unique(preds, return_counts=True)
    return unique[np.argmax(counts)]


def main():
    backend_dir = Path(__file__).resolve().parent
    window_size, step = 80, 40

    labeled = get_labeled_imu_files(backend_dir)
    if not labeled:
        print(f"No labeled IMU files found. Put .txt files in {TRAINING_DATA_DIR}/shoulders/ or {TRAINING_DATA_DIR}/bicep/.")
        return

    print("Training on all labeled IMU files (label from filename):")
    for path, label in labeled:
        print(f"  {path.name} -> {label}")

    pipeline, feature_names, _ = train_classifier_from_dir(
        backend_dir,
        window_size=window_size,
        step=step,
    )

    print("\nClassification results (per file):")
    for path, true_label in labeled:
        data = load_imu_file(str(path))
        pred = classify_exercise(pipeline, data, window_size=window_size, step=step)
        ok = "✓" if pred == true_label else "✗"
        print(f"  {ok} {path.name} (true: {true_label}) -> predicted: {pred}")

    model_path = save_model(pipeline, window_size=window_size, step=step)
    print(f"\nModel saved to: {model_path}")


if __name__ == "__main__":
    main()
