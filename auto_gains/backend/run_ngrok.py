#!/usr/bin/env python3
"""
Expose the WebSocket server (port 8765) via ngrok so a phone can connect.

Run from the backend directory:
    python run_ngrok.py

Then set the app's backend URL to the ngrok wss:// URL (see terminal output).
"""
import ssl
import sys

# Use certifi's CA bundle so HTTPS (e.g. pyngrok downloading the binary) works on Mac
import certifi
ssl._create_default_https_context = lambda: ssl.create_default_context(cafile=certifi.where())

from pyngrok import ngrok

PORT = 8765
if len(sys.argv) > 1:
    try:
        PORT = int(sys.argv[1])
    except ValueError:
        pass

print(f"Starting ngrok tunnel for port {PORT} (WebSocket)...")
public_url = ngrok.connect(PORT, "http")
# ngrok HTTP tunnel supports WebSocket upgrade; use wss:// for the app
ws_url = str(public_url).replace("https://", "wss://").replace("http://", "ws://")
print(f"Tunnel: {public_url}")
print(f"WebSocket URL for app: {ws_url}")
print("Update lib/config/backend_config.dart with this URL, then run the app.")
try:
    ngrok.run()
except KeyboardInterrupt:
    ngrok.kill()
    print("Tunnel closed.")
