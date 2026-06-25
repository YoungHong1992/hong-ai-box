#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "This integration test must run as root." >&2
  exit 1
fi

export HONGAIBOX_UNATTENDED=1
export HONGAIBOX_DISABLE_SWAP=1

"$ROOT_DIR/maintenance/install.sh"
"$ROOT_DIR/maintenance/install.sh"

test -f /var/lib/hongaibox/maintenance.installed

grep -q 'version=' /var/lib/hongaibox/maintenance.installed

echo "Maintenance idempotency test passed."
