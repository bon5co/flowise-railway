# Railway-tuned Flowise image.
#
# FROM the pinned upstream release. The listing holding the most recent deploys in the
# Flowise category ships the bare `flowiseai/flowise` tag (checked 2026-08-02), and
# Flowise runs TypeORM migrations on boot, so an unpinned tag turns an ordinary redeploy
# into an unscheduled upgrade of the application database.
FROM flowiseai/flowise:3.1.4

USER root

# su-exec so the entrypoint can repair the volume's ownership as root and then hand the
# server back to the `node` user the upstream image runs as (uid 1000).
RUN apk add --no-cache su-exec

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

# --- Where Flowise keeps the state that is NOT in Postgres --------------------------
# Flowise resolves its data directory from $HOME, and the upstream image runs as `node`,
# so the default is /home/node/.flowise -- not /root/.flowise and not /data. That
# directory holds encryption.key (the AES key for every stored credential), the six auth
# secrets (token_hash, express_session, jwt_auth, jwt_refresh, jwt_issuer, jwt_audience),
# uploads and the document-store blobs. Every one of them is regenerated when the
# directory is empty, and nothing in the app reports it: the credential rows stay in
# Postgres and decrypt to `{}` (measured against 3.1.4 on 2026-08-02 -- GET
# /api/v1/credentials/:id returns 200 with an empty plainDataObj, so the UI shows the
# credential and the flow using it fails at request time).
#
# Pointing SECRETKEY_PATH / BLOB_STORAGE_PATH / LOG_PATH at the volume mount is what
# makes those survive; BLOB_STORAGE_PATH also moves the uploads dir, which Flowise
# derives from it.
#
# --- Why these are ENV and not Railway template variables ---------------------------
# templateGenerate keeps a variable's default only when the live value is a Railway
# expression (${{secret(n)}}, ${{svc.VAR}}, ...). A literal is dropped and the variable
# publishes as required-with-no-value, so every literal shipped as a variable is another
# empty box on the deploy form. Baking them here is what leaves the form empty.
#
# DATABASE_TYPE / DATABASE_USER / DATABASE_NAME / DATABASE_PORT -- the paired Postgres
#   service runs stock postgres:17 with only POSTGRES_PASSWORD set, so user and database
#   are both `postgres` on 5432. Constants of this template, not deployer choices.
# DATABASE_SSL=false -- the connection runs over Railway's private network.
# DISABLE_FLOWISE_TELEMETRY -- self-hosted software phoning home about itself is a
#   surprise, not a default.
# NUMBER_OF_PROXIES=1 -- Flowise sits behind exactly one proxy here (Railway's edge), and
#   the rate limiter needs that to read the real client IP instead of the edge's.
#
# PORT is deliberately NOT set: Railway injects it (8080) and the service domain targets the
# same number. Baking a different default here only creates a way for the two to disagree,
# which is a 502 at the edge with a healthy-looking server log.
ENV DATABASE_TYPE=postgres \
    DATABASE_USER=postgres \
    DATABASE_NAME=postgres \
    DATABASE_PORT=5432 \
    DATABASE_SSL=false \
    SECRETKEY_PATH=/data \
    BLOB_STORAGE_PATH=/data/storage \
    LOG_PATH=/data/logs \
    DISABLE_FLOWISE_TELEMETRY=true \
    NUMBER_OF_PROXIES=1

EXPOSE 3000

# The entrypoint creates and chowns the volume before dropping back to `node`, then execs
# the stock `flowise start`. Do NOT set a Railway start command on top of this image: a
# start command REPLACES the entrypoint, so the volume would stay root-owned and the
# server would crash writing its first secret.
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
