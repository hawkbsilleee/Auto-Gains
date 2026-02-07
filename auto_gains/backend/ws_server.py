"""
WebSocket server that bridges Arduino serial IMU data to Flutter.

Reads raw accelerometer samples from Arduino, feeds them through
StreamingPipeline for rep detection, and broadcasts results over WebSocket.

Usage:
    python ws_server.py                           # Real Arduino
    python ws_server.py --mock                    # Replay imu_data.txt
    python ws_server.py --port /dev/cu.usbmodem1401  # Custom serial port
"""

import asyncio
import json
import threading
import argparse
import time
from pathlib import Path

import numpy as np
import serial
import websockets

from imu_dynamic import StreamingPipeline

# Auto-detect: collect this many samples (~4 sec at 100Hz) then run classifier
AUTO_DETECT_SAMPLES = 200
try:
    import train_classifier
    _classifier_model = None
    _classifier_lock = threading.Lock()
except ImportError:
    train_classifier = None


DEFAULT_SERIAL_PORT = "/dev/cu.usbmodem21301"
DEFAULT_BAUD_RATE = 115200
DEFAULT_WS_HOST = "0.0.0.0"
DEFAULT_WS_PORT = 8765


def _load_classifier():
    """Load classifier model once (thread-safe). Returns (pipeline, window_size, step) or (None, None, None)."""
    global _classifier_model
    if train_classifier is None:
        return None, None, None
    with _classifier_lock:
        if _classifier_model is None:
            backend_dir = Path(__file__).resolve().parent
            model_path = backend_dir / "classifier_model.joblib"
            if not model_path.exists():
                print("[classifier] Model not found at", model_path)
                return None, None, None
            try:
                _classifier_model = train_classifier.load_model(model_path)
                print("[classifier] Loaded model from", model_path)
            except Exception as e:
                print("[classifier] Failed to load model:", e)
                return None, None, None
        m = _classifier_model
        return m["pipeline"], m["window_size"], m["step"]


class RepServer:
    def __init__(self, serial_port, baud_rate, ws_host, ws_port, mock=False):
        self.serial_port = serial_port
        self.baud_rate = baud_rate
        self.ws_host = ws_host
        self.ws_port = ws_port
        self.mock = mock

        self.clients = set()
        self.pipeline = None
        self.sample_idx = 0
        self.sample_queue = None
        self.running = False
        # Auto-detect: when not None, collect samples here instead of running rep pipeline
        self.auto_detect_buffer = None

    def _serial_reader(self, loop):
        """Blocking serial read loop running in a background thread."""
        try:
            arduino = serial.Serial(
                port=self.serial_port,
                baudrate=self.baud_rate,
                timeout=1,
            )
            time.sleep(2)  # Arduino reset delay
            print(f"[serial] Connected to {self.serial_port}")
        except serial.SerialException as e:
            print(f"[serial] ERROR: Could not open {self.serial_port}: {e}")
            return

        sample_count = 0
        try:
            while self.running:
                try:
                    line = arduino.readline().decode().strip()
                    if not line:
                        continue
                    parts = line.split()
                    if len(parts) != 3:
                        continue
                    ax, ay, az = int(parts[0]), int(parts[1]), int(parts[2])
                    sample_count += 1
                    if sample_count == 1:
                        print(f"[serial] First sample received: ax={ax} ay={ay} az={az}")
                    elif sample_count % 500 == 0:
                        print(f"[serial] Data stream alive: {sample_count} samples received from Arduino")
                    loop.call_soon_threadsafe(
                        self.sample_queue.put_nowait, (ax, ay, az)
                    )
                except (ValueError, UnicodeDecodeError):
                    continue
                except serial.SerialException:
                    print("[serial] Connection lost")
                    break
        finally:
            arduino.close()
            print("[serial] Port closed")

    def _mock_reader(self, loop):
        """Replay imu_data.txt with realistic timing for testing without Arduino."""
        data_path = Path(__file__).parent / "imu_data.txt"
        if not data_path.exists():
            print(f"[mock] ERROR: {data_path} not found")
            return

        samples = []
        with open(data_path) as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) == 3:
                    samples.append((int(parts[0]), int(parts[1]), int(parts[2])))

        print(f"[mock] Loaded {len(samples)} samples from {data_path}")
        print("[mock] Waiting for a client to connect...")

        # Wait until at least one client connects
        while self.running and not self.clients:
            time.sleep(0.1)

        if not self.running:
            return

        print("[mock] Client connected, starting replay...")
        for i, sample in enumerate(samples):
            if not self.running:
                break
            if i == 0:
                print(f"[mock] First sample sent: {sample}")
            elif (i + 1) % 500 == 0:
                print(f"[mock] Replay progress: {i + 1}/{len(samples)} samples")
            loop.call_soon_threadsafe(self.sample_queue.put_nowait, sample)
            time.sleep(0.15)  # ~100Hz, matching typical Arduino rate

        print("[mock] Replay complete")

    def _reset_pipeline(self):
        """Create a fresh pipeline for a new workout session."""
        self.pipeline = StreamingPipeline(
            amplitude_threshold=21.0,
            min_samples_between_reps=20,
            baseline_window=50,
            pca_warmup=30,
            smooth_alpha=0.15,
        )
        self.sample_idx = 0

    async def _process_samples(self):
        """Async loop: pull samples from queue, run pipeline or collect for classifier, broadcast."""
        while self.running:
            try:
                ax, ay, az = await asyncio.wait_for(
                    self.sample_queue.get(), timeout=1.0
                )
            except asyncio.TimeoutError:
                continue

            # Auto-detect: collect samples for classifier in parallel with rep pipeline
            if self.auto_detect_buffer is not None:
                self.auto_detect_buffer.append([float(ax), float(ay), float(az)])
                if len(self.auto_detect_buffer) >= AUTO_DETECT_SAMPLES:
                    buffer = self.auto_detect_buffer
                    self.auto_detect_buffer = None
                    # Do NOT reset pipeline — reps during detection are preserved
                    rep_count = (
                        self.pipeline.counter.rep_count
                        if self.pipeline is not None and hasattr(self.pipeline, "counter")
                        else 0
                    )
                    pipeline, window_size, step = _load_classifier()
                    if pipeline is not None and len(buffer) >= 10:
                        try:
                            data = np.array(buffer, dtype=np.float64)
                            pred = train_classifier.classify_exercise(
                                pipeline, data, window_size=window_size, step=step
                            )
                            msg = json.dumps({
                                "type": "exercise_detected",
                                "exercise": pred,
                                "rep_count": rep_count,
                            })
                            print(f"[backend] Auto-detect result: {pred}, rep_count={rep_count}")
                            await self._broadcast(msg)
                        except Exception as e:
                            print("[backend] Classifier error:", e)
                            await self._broadcast(json.dumps({
                                "type": "exercise_detected",
                                "exercise": "bicep_curl",
                                "rep_count": rep_count,
                                "error": str(e),
                            }))
                    else:
                        await self._broadcast(json.dumps({
                            "type": "exercise_detected",
                            "exercise": "bicep_curl",
                            "rep_count": rep_count,
                        }))

            if self.pipeline is None:
                continue

            result = self.pipeline.process_sample(ax, ay, az, self.sample_idx)
            self.sample_idx += 1

            # Debug: confirm backend is processing data (every 500 samples)
            if self.sample_idx % 500 == 0:
                print(f"[backend] Processing stream: sample_idx={self.sample_idx}, rep_count={result['rep_count']}")

            if result["rep_detected"]:
                message = json.dumps({
                    "type": "rep",
                    "rep_count": result["rep_count"],
                    "amplitude": round(result["amplitude"], 2),
                })
                print(f"[backend] REP detected (amplitude={result['amplitude']:.2f}), broadcasting to {len(self.clients)} client(s)")
                await self._broadcast(message)

            # Stream speed/tempo data every 3 samples (~33Hz at 100Hz input)
            if self.sample_idx % 3 == 0:
                speed_msg = json.dumps({
                    "type": "speed",
                    "speed_deviation": round(result.get("speed_deviation", 0.0), 3),
                    "phase": result.get("phase", "concentric"),
                    "active": result.get("is_active", False),
                })
                await self._broadcast(speed_msg)

            # Set boundary detection
            if result.get("set_boundary", False):
                boundary_msg = json.dumps({
                    "type": "set_boundary",
                    "rep_count": result["rep_count"],
                })
                print(f"[backend] Set boundary detected at sample {self.sample_idx}, rep_count={result['rep_count']}")
                await self._broadcast(boundary_msg)

            # Periodic status heartbeat every 50 samples
            if self.sample_idx % 50 == 0:
                status = json.dumps({
                    "type": "status",
                    "sample_idx": self.sample_idx,
                    "rep_count": result["rep_count"],
                })
                await self._broadcast(status)

    async def _broadcast(self, message):
        """Send message to all connected clients."""
        if not self.clients:
            return
        disconnected = set()
        for ws in self.clients:
            try:
                await ws.send(message)
            except websockets.exceptions.ConnectionClosed:
                disconnected.add(ws)
        self.clients -= disconnected

    async def _handle_client(self, websocket):
        """Handle a new WebSocket client connection."""
        self.clients.add(websocket)
        print(f"[ws] Client connected ({len(self.clients)} total)")

        # Reset pipeline for new session
        self._reset_pipeline()

        await websocket.send(json.dumps({
            "type": "connected",
            "message": "Pipeline reset for new session",
        }))

        try:
            async for message in websocket:
                try:
                    data = json.loads(message)
                    if data.get("action") == "reset":
                        self._reset_pipeline()
                        self.auto_detect_buffer = None
                        await websocket.send(json.dumps({
                            "type": "reset_ack",
                        }))
                    elif data.get("action") == "start_auto_detect":
                        self.auto_detect_buffer = []
                        print("[backend] Auto-detect started, collecting samples...")
                        await websocket.send(json.dumps({
                            "type": "auto_detect_started",
                            "samples_needed": AUTO_DETECT_SAMPLES,
                        }))
                except json.JSONDecodeError:
                    pass
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            self.clients.discard(websocket)
            print(f"[ws] Client disconnected ({len(self.clients)} total)")

    async def start(self):
        """Start the WebSocket server and serial/mock reader."""
        self.running = True
        self.sample_queue = asyncio.Queue(maxsize=1000)
        loop = asyncio.get_event_loop()

        # Start data reader in background thread
        reader_fn = self._mock_reader if self.mock else self._serial_reader
        reader_thread = threading.Thread(
            target=reader_fn, args=(loop,), daemon=True
        )
        reader_thread.start()

        # Start sample processing
        asyncio.create_task(self._process_samples())

        # Start WebSocket server
        mode_label = "MOCK" if self.mock else f"SERIAL ({self.serial_port})"
        print(f"[ws] Server starting on ws://{self.ws_host}:{self.ws_port}")
        print(f"[ws] Data source: {mode_label}")

        async with websockets.serve(
            self._handle_client, self.ws_host, self.ws_port
        ):
            await asyncio.Future()  # Run forever


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Auto Gains Rep Server")
    parser.add_argument(
        "--port", default=DEFAULT_SERIAL_PORT, help="Arduino serial port"
    )
    parser.add_argument(
        "--baud", type=int, default=DEFAULT_BAUD_RATE, help="Baud rate"
    )
    parser.add_argument(
        "--ws-host", default=DEFAULT_WS_HOST, help="WebSocket bind host"
    )
    parser.add_argument(
        "--ws-port", type=int, default=DEFAULT_WS_PORT, help="WebSocket port"
    )
    parser.add_argument(
        "--mock", action="store_true", help="Replay imu_data.txt instead of real Arduino"
    )
    args = parser.parse_args()

    server = RepServer(args.port, args.baud, args.ws_host, args.ws_port, args.mock)
    try:
        asyncio.run(server.start())
    except KeyboardInterrupt:
        print("\nShutting down.")
