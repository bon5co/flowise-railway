#!/bin/sh
# Prepare the Railway volume for Flowise, then hand over to the stock entrypoint.
#
# Railway mounts volumes owned by uid 0, and the upstream image runs as `node` (uid 1000),
# so without this the first write to the data directory fails and the container crash-loops.
set -e

DATA_DIR="${SECRETKEY_PATH:-/data}"

mkdir -p "$DATA_DIR" "${BLOB_STORAGE_PATH:-$DATA_DIR/storage}" "${LOG_PATH:-$DATA_DIR/logs}"

# ext4 volumes come with a root-owned lost+found; Flowise lists this directory.
rm -rf "$DATA_DIR/lost+found" 2>/dev/null || true

chown -R node:node "$DATA_DIR"

echo "[railway-entrypoint] data dir $DATA_DIR ready:"
ls -lan "$DATA_DIR" | head -5

exec su-exec node:node flowise start "$@"
