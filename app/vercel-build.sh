#!/usr/bin/env bash
set -euo pipefail

: "${FLUTTER_VERSION:=3.41.7}"

FLUTTER_HOME="$HOME/flutter"

if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  echo "Instalando Flutter ${FLUTTER_VERSION}..."
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz
  tar -xJf /tmp/flutter.tar.xz -C "$HOME"
fi

git config --global --add safe.directory "$FLUTTER_HOME"

export PATH="$FLUTTER_HOME/bin:$PATH"
export CI=true

flutter config --no-analytics
flutter config --no-cli-animations
flutter config --enable-web

flutter --version
flutter pub get
flutter build web --release