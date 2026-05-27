#!/bin/bash
set -e

cd /app

echo "Installing Flutter dependencies..."
flutter pub get

# Generated *.g.dart files are committed/mounted from the host — skip slow
# build_runner on every container start unless explicitly requested.
if [ "${RUN_BUILD_RUNNER:-0}" = "1" ]; then
  echo "Running build_runner (RUN_BUILD_RUNNER=1)..."
  dart run build_runner build --delete-conflicting-outputs || true
fi

echo "Starting Flutter web dev server on :8080..."
echo "(Gateway may return 502 until the dev server is ready — usually 30-90s on first start)"
exec flutter run -d web-server \
  --web-hostname 0.0.0.0 \
  --web-port 8080 \
  --dart-define=API_BASE_URL=/api/v1
