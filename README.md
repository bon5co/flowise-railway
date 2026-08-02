# flowise-railway

Railway-tuned [Flowise](https://github.com/FlowiseAI/Flowise) image: state that is not in
Postgres kept on the volume, pinned release, empty deploy form.

Image: `ghcr.io/bon5co/flowise-railway:latest` (amd64). Base: `flowiseai/flowise:3.1.4`.

Used by the Railway template **Flowise 3.1.4 | Visual AI Agent Builder, Credentials Survive
Redeploys**.

## What this changes, and why

### 1. The data directory is on the volume — the whole one

Flowise resolves its data directory from `$HOME`, and the upstream image runs as the `node`
user, so the default is **`/home/node/.flowise`**. That directory holds:

- `encryption.key` — the AES key for every credential (OpenAI/Anthropic/Pinecone/... keys)
- the six auth secrets — `token_hash`, `express_session`, `jwt_auth`, `jwt_refresh`,
  `jwt_issuer`, `jwt_audience`
- `storage/` and `storage/uploads/` — document-store files and chat uploads

Each is regenerated when the directory comes up empty, and **nothing reports it**. Measured
against `flowiseai/flowise:3.1.4` on 2026-08-02, with Postgres kept and the container
replaced:

```
# credential created, key intact
GET /api/v1/credentials/:id  ->  200  plainDataObj {"openAIApiKey":"_FLOWISE_BLANK_..."}
# same Postgres, container replaced, data dir not persisted
GET /api/v1/credentials/:id  ->  200  plainDataObj {}          <- silently empty
POST with the previous session cookie -> 401                   <- auth secrets rotated
```

The credential row survives in Postgres and still shows in the UI; the secret inside it is
gone, and the flow that uses it fails at request time rather than at deploy time.

`SECRETKEY_PATH`, `BLOB_STORAGE_PATH` and `LOG_PATH` are pointed at `/data` (the template's
volume mount) so all of it persists. Same test against this image, container replaced:
credential decrypts, old session cookie still authenticates.

### 2. The volume is made writable before the server starts

Railway mounts volumes owned by uid 0; upstream runs as `node` (uid 1000). The entrypoint
creates the subdirectories, removes `lost+found`, chowns the mount as root and then execs
`flowise start` through `su-exec` as `node`.

A Railway **start command replaces the entrypoint** — do not set one on this image, or the
volume stays root-owned.

### 3. Pinned to 3.1.4

Flowise runs TypeORM migrations on boot. The bare `flowiseai/flowise` tag that competing
Railway listings use turns an ordinary redeploy into an unscheduled upgrade of the
application database.

### 4. Literal settings are baked in, so the deploy form stays empty

`templateGenerate` keeps a template variable's default only when the live value is a Railway
*expression*; literals are dropped and the variable publishes as required-with-no-value.
Every constant of this template (`DATABASE_TYPE`, `DATABASE_USER`, `DATABASE_NAME`,
`DATABASE_PORT`, `DATABASE_SSL`, the three paths, `DISABLE_FLOWISE_TELEMETRY`,
`NUMBER_OF_PROXIES`, `PORT`) is therefore an `ENV` here rather than a variable.

## Variables the template still sets

| Variable | Value | Why |
| --- | --- | --- |
| `DATABASE_HOST` | `${{postgres.RAILWAY_PRIVATE_DOMAIN}}` | per-project |
| `DATABASE_PASSWORD` | `${{postgres.POSTGRES_PASSWORD}}` | per-project |
| `FLOWISE_SECRETKEY_OVERWRITE` | `${{secret(48)}}` | pins the credential key to the project, so it survives even if the volume is replaced. Changing it later makes every stored credential undecryptable. |
| `APP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | password-reset/invite links, and it flips session cookies to `Secure` (the image sets no `NODE_ENV`, so without it Flowise falls back to non-secure cookies) |

## Note on who owns the instance

Flowise 3.x has an account system: the first person to register becomes the owner and
`ensureOneOrganizationOnly` rejects every later registration with *"You can only have one
organization"*. `FLOWISE_USERNAME` / `FLOWISE_PASSWORD` **no longer exist** — grep 3.1.4 and
there are zero references, though several Railway listings still ask deployers for them.
Register your account as soon as the deploy goes live; until you do, the sign-up page is open
to whoever finds the URL.
