"""
Plot accelerometer (x, y, z) data from imu_data.txt.
"""
import os
import matplotlib.pyplot as plt


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_path = os.path.join(script_dir, "imu_data.txt")
    x_vals, y_vals, z_vals = [], [], []

    with open(data_path) as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 3:
                x_vals.append(float(parts[0]))
                y_vals.append(float(parts[1]))
                z_vals.append(float(parts[2]))

    samples = range(len(x_vals))

    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(samples, x_vals, label="X", alpha=0.8)
    ax.plot(samples, y_vals, label="Y", alpha=0.8)
    ax.plot(samples, z_vals, label="Z", alpha=0.8)
    ax.set_xlabel("Sample")
    ax.set_ylabel("Acceleration")
    ax.set_title("Accelerometer (X, Y, Z)")
    ax.legend()
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.show()


if __name__ == "__main__":
    main()
