#!/usr/bin/env bash
set -euo pipefail

# Defina na Vercel a mesma versão do Flutter que você usa localmente
: "${FLUTTER_VERSION:=3.24.0}"

FLUTTER_HOME="$HOME/flutter"

if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  echo "Instalando Flutter ${FLUTTER_VERSION}..."
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz
  tar -xJf /tmp/flutter.tar.xz -C "$HOME"
fi

export PATH="$FLUTTER_HOME/bin:$PATH"

flutter --version
flutter config --enable-web
flutter pub get
flutter build web --release