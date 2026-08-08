#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="AgentsNotch"
DISPLAY_NAME="Agents Notch"
BUNDLE_ID="com.afonsoferreira.AgentsNotch"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$DISPLAY_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
SOCKET_PATH="$HOME/.agentsnotch/agent.sock"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
if [[ -S "$SOCKET_PATH" ]]; then
  rm -f "$SOCKET_PATH"
fi

"$ROOT_DIR/script/stage_app.sh" --configuration debug --arch arm64 --sign -

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in 1 2 3 4 5; do
      if pgrep -x "$APP_NAME" >/dev/null && [[ -S "$SOCKET_PATH" ]]; then
        exit 0
      fi
      sleep 1
    done
    echo "$DISPLAY_NAME did not stay running with its event socket available" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
