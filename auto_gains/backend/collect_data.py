import serial
import time
from pathlib import Path
from datetime import datetime

arduino = serial.Serial(port="/dev/cu.usbmodem1301", baudrate=115200, timeout=1)

time.sleep(2)

# Change this to "shoulders" or "bicep" to save into test_data/shoulders/ or test_data/bicep/
label = "shoulders"

backend_dir = Path(__file__).resolve().parent
desired_dir = backend_dir / "test_data" / label
desired_dir.mkdir(parents=True, exist_ok=True)
filename = f"imu_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
desired_path = desired_dir / filename

outfile = open(desired_path, "w")
print(f"Recording IMU data (label: {label}) -> {desired_path}")
print("Press Ctrl+C to stop.")

try:
    while True:
        line = arduino.readline().decode().strip()
        if not line:
            continue

        # Optional: validate format (3 space-separated ints)
        parts = line.split()
        if len(parts) != 3:
            continue

        outfile.write(line + "\n")
        outfile.flush()  # ensures data is written immediately
        print(line)

except KeyboardInterrupt:
    print("\nStopping recording.")

finally:
    outfile.close()
    arduino.close()
