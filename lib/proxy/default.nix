{
  pkgs,
  sandbox,
  allowList,
  ...
}: let
  squidConf = import ./squid.nix {
    inherit pkgs allowList;
  };
  pidDir = "/tmp/claude-sandbox-proxy";
in
  pkgs.writeShellScript "claude-sandbox-proxy" ''
    #!/usr/bin/env bash
    set -euo pipefail

    PID_DIR="${pidDir}"
    mkdir -p "$PID_DIR"

    # Kill stale squid processes from previous runs that weren't cleaned up
    for pidfile in "$PID_DIR"/squid.*.pid; do
      [ -f "$pidfile" ] || continue
      old_pid=$(cat "$pidfile" 2>/dev/null) || continue
      if kill -0 "$old_pid" 2>/dev/null; then
        echo "Cleaning up stale proxy (PID: $old_pid)"
        kill "$old_pid" 2>/dev/null || true
        sleep 1
        kill -9 "$old_pid" 2>/dev/null || true
      fi
      rm -f "$pidfile"
    done

    generate_random_port() {
      echo $((49152 + RANDOM % (65535 - 49152 + 1)))
    }

    PROXY_PID=""
    PROXY_PIDFILE=""
    DYNAMIC_SQUID_CONF=$(mktemp)
    cleanup() {
      rm -f "$DYNAMIC_SQUID_CONF"
      if [ -n "$PROXY_PID" ]; then
        echo "Stopping proxy (PID: $PROXY_PID)..."
        kill "$PROXY_PID" 2>/dev/null || true
        wait "$PROXY_PID" 2>/dev/null || true
      fi
      rm -f "$PROXY_PIDFILE"
    }

    trap cleanup EXIT INT TERM

    CURRENT_PORT=""
    CONNECTED=false
    for attempt in {1..5}; do
      CURRENT_PORT=$(generate_random_port)
      echo "Attempt $attempt: Starting proxy on port $CURRENT_PORT"

      {
        echo "http_port 127.0.0.1:$CURRENT_PORT"
        echo "pid_filename $(mktemp /tmp/squid.pid.XXXXXX)"
        cat ${squidConf}
      } > "$DYNAMIC_SQUID_CONF"

      ${pkgs.squid}/bin/squid -d -1 -N -f "$DYNAMIC_SQUID_CONF" &
      PROXY_PID=$!
      PROXY_PIDFILE="$PID_DIR/squid.$$.pid"
      echo "$PROXY_PID" > "$PROXY_PIDFILE"

      for i in {1..10}; do
        if ${pkgs.curl}/bin/curl -s http://localhost:$CURRENT_PORT/ > /dev/null 2>&1; then
          CONNECTED=true
          break
        fi
        sleep 1
      done

      if [ $CONNECTED = true ]; then
        break
      fi

      if [ $attempt -eq 5 ]; then
        echo "Failed to start proxy after 5 attempts"
        exit 1
      fi
    done

    export HTTP_PROXY="http://localhost:$CURRENT_PORT"
    export HTTPS_PROXY="http://localhost:$CURRENT_PORT"
    export http_proxy="http://localhost:$CURRENT_PORT"
    export https_proxy="http://localhost:$CURRENT_PORT"

    "${sandbox}" "$@"
  ''
