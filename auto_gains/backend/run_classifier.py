"""Load saved classifier and predict exercise for every IMU data file in test_data."""

from pathlib import Path

import train_classifier

backend_dir = Path(__file__).resolve().parent
model_path = backend_dir / "classifier_model.joblib"
test_data_dir = backend_dir / "test_data"

# Map test_data subfolder names to classifier labels
FOLDER_TO_LABEL = {
    "shoulders": train_classifier.SHOULDER_PRESS,
    "bicep": train_classifier.BICEP_CURL,
}


def get_true_label(data_path: Path, test_data_dir: Path) -> str | None:
    """Infer true label from path: test_data/shoulders/... -> shoulder_press, test_data/bicep/... -> bicep_curl."""
    try:
        relative = data_path.relative_to(test_data_dir)
        folder = relative.parts[0] if relative.parts else None
        return FOLDER_TO_LABEL.get(folder)
    except (ValueError, IndexError):
        return None


def main():
    model = train_classifier.load_model(model_path)
    pipeline = model["pipeline"]
    window_size = model["window_size"]
    step = model["step"]

    if not test_data_dir.is_dir():
        print(f"No test_data folder at {test_data_dir}. Add .txt files under test_data/shoulders/ or test_data/bicep/.")
        return

    files = sorted(test_data_dir.rglob("*.txt"))
    if not files:
        print(f"No .txt files found under {test_data_dir}.")
        return

    print(f"Classifying {len(files)} file(s) in test_data:\n")

    results = []  # (relative_path, true_label, pred_label)
    skipped = 0

    for data_path in files:
        true_label = get_true_label(data_path, test_data_dir)
        if true_label is None:
            print(f"  {data_path.relative_to(test_data_dir)}: skipped (unknown folder, use shoulders/ or bicep/)")
            skipped += 1
            continue

        data = train_classifier.load_imu_file(str(data_path))
        if len(data) < 10:
            print(f"  {data_path.relative_to(test_data_dir)}: skipped (too few samples)")
            skipped += 1
            continue

        pred_label = train_classifier.classify_exercise(
            pipeline, data, window_size=window_size, step=step
        )
        results.append((data_path.relative_to(test_data_dir), true_label, pred_label))
        correct = "✓" if pred_label == true_label else "✗"
        print(f"  {correct} {data_path.relative_to(test_data_dir)}: true={true_label} -> pred={pred_label}")

    if not results:
        print("\nNo files were classified (all skipped).")
        return

    # Accuracy
    n_correct = sum(1 for _, true, pred in results if true == pred)
    n_total = len(results)
    accuracy = n_correct / n_total if n_total else 0.0

    print("\n" + "=" * 50)
    print("ACCURACY")
    print("=" * 50)
    print(f"  Overall: {n_correct}/{n_total} correct = {accuracy:.1%}")

    # Per-class accuracy (for each true label, how many we got right)
    for label in [train_classifier.BICEP_CURL, train_classifier.SHOULDER_PRESS]:
        class_results = [(true, pred) for _, true, pred in results if true == label]
        if not class_results:
            continue
        class_correct = sum(1 for true, pred in class_results if true == pred)
        class_total = len(class_results)
        class_acc = class_correct / class_total if class_total else 0.0
        print(f"  {label}: {class_correct}/{class_total} = {class_acc:.1%}")

    if skipped:
        print(f"\n  ({skipped} file(s) skipped)")


if __name__ == "__main__":
    main()

