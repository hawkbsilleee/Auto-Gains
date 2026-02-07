/// Backend WebSocket URL for Arduino/rep detection.
///
/// - **iOS Simulator / physical device**: Backend runs on your Mac. Use your
///   Mac's IP, e.g. `ws://172.25.18.162:8765`. Find IP: `ifconfig | grep "inet "`.
/// - **Same machine** (Chrome/desktop): `ws://127.0.0.1:8765` works.
///
/// Ensure the backend is running: `python backend/ws_server.py --mock`
/// (or without --mock when Arduino is connected).
///
/// For iOS Simulator: use your Mac's IP (e.g. from `ifconfig | grep "inet "`).
const String kBackendWsUrl = 'ws://127.0.0.1:8765';
