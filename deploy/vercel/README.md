# Deploy Buzz on Vercel

This is an experimental, evaluation-oriented deployment of the Buzz relay as a
Vercel container Function.

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Fdak-engineering%2Fbuzz&project-name=buzz&repository-name=buzz-vercel&stores=%5B%7B%22type%22%3A%22integration%22%2C%22protocol%22%3A%22storage%22%2C%22productSlug%22%3A%22neon%22%2C%22integrationSlug%22%3A%22neon%22%2C%22allowConnectExistingProduct%22%3Atrue%7D%2C%7B%22type%22%3A%22integration%22%2C%22protocol%22%3A%22storage%22%2C%22productSlug%22%3A%22upstash-kv%22%2C%22integrationSlug%22%3A%22upstash%22%2C%22allowConnectExistingProduct%22%3Atrue%7D%5D&env=BUZZ_S3_ACCESS_KEY%2CBUZZ_S3_SECRET_KEY%2CBUZZ_S3_BUCKET%2CBUZZ_RELAY_PRIVATE_KEY%2CBUZZ_GIT_HOOK_HMAC_SECRET&envDescription=Tigris+S3-compatible+bucket+credentials+plus+two+stable+32-byte+hex+secrets.+Generate+each+Buzz+secret+with%3A+openssl+rand+-hex+32&envLink=https%3A%2F%2Fgithub.com%2Fdak-engineering%2Fbuzz%2Fblob%2Fmain%2Fdeploy%2Fvercel%2FREADME.md%23required-values)

The deploy flow:

1. clones this repository into your Git provider;
2. creates a Vercel project;
3. provisions or connects Neon Postgres and Upstash Redis through the Vercel
   Marketplace;
4. asks for object-storage credentials and two stable Buzz secrets; and
5. auto-detects the additive root `Dockerfile.vercel` and builds it as a
   Vercel container Function.

Neon injects `DATABASE_URL`, while Upstash injects `KV_URL`. A small
deployment-only entrypoint translates those Marketplace and Vercel variables
into Buzz's existing `BUZZ_*` configuration before starting the unchanged
relay binary. It also supplies the assigned bind port, public relay/media URLs,
and the Vercel deployment defaults for migrations and huddle audio.

## Required values

Vercel Blob is not used. Buzz's media store and Git object store both use the
S3 API, and the Git store additionally requires linearizable conditional
writes (`If-Match`, `If-None-Match`, and HTTP 412 behavior). Vercel Blob exposes
a different API, so supporting it would require a new storage backend rather
than deployment configuration.

[Tigris](https://vercel.com/marketplace/tigris) is the closest Vercel-integrated
fit: it is S3-compatible, but it is currently a third-party Marketplace
integration rather than a native store that a Deploy Button can provision.
Create a Tigris bucket and access key first, then enter:

| Variable | Value |
| --- | --- |
| `BUZZ_S3_ACCESS_KEY` | Tigris access key (`tid_...`) |
| `BUZZ_S3_SECRET_KEY` | Tigris secret key (`tsec_...`) |
| `BUZZ_S3_BUCKET` | Existing bucket name |
| `BUZZ_RELAY_PRIVATE_KEY` | Stable Nostr relay key: `openssl rand -hex 32` |
| `BUZZ_GIT_HOOK_HMAC_SECRET` | Stable hook secret: `openssl rand -hex 32` |

The Vercel entrypoint supplies Tigris's standard endpoint
(`https://t3.storage.dev`) and signing region (`auto`). Explicit canonical
`BUZZ_*` values always take precedence, so another conforming S3 provider can
be used without application changes.

The relay runs its Git object-store conformance probe before accepting traffic.
This is deliberate: if Tigris or another S3-compatible provider does not
provide the conditional-write semantics Buzz needs, startup fails instead of
risking Git ref corruption. AWS S3 or another backend that passes the same
probe can be configured with the existing `BUZZ_S3_*` variables.

## Deployment adapter

Vercel requires containerized HTTP servers to listen on its runtime `PORT`.
Buzz already exposes canonical environment variables for every deployment
setting, so Vercel support does not require changes to the Rust application.
[`entrypoint.sh`](entrypoint.sh) performs the deployment-boundary translation:

- an immediate `$PORT` TCP listener forwarding to Buzz on a private,
  non-conflicting port, holding cold-start connections while Buzz completes
  storage admission so it can exceed Vercel's startup deadline without
  changing the relay;
- non-conflicting private health and metrics ports;
- Upstash `KV_URL` to `REDIS_URL`;
- Vercel's deployment host to `RELAY_URL` and `BUZZ_MEDIA_BASE_URL`; and
- explicit Vercel defaults for `BUZZ_AUTO_MIGRATE`,
  `BUZZ_HUDDLE_AUDIO_AVAILABLE`, `BUZZ_S3_ENDPOINT`, and `BUZZ_S3_REGION`.

The Vercel-specific Dockerfile layers this adapter onto a pinned digest of the
published, multi-architecture `ghcr.io/block/buzz` image. It does not modify or
duplicate Buzz's production Dockerfile. The adapter only activates when
`VERCEL=1`; any explicitly configured canonical variable is preserved.

When intentionally upgrading the bundled Buzz version, update the digest in
[`Dockerfile.vercel`](../../Dockerfile.vercel) after validating the new
published image.

## After deployment

Use the production deployment URL with the `wss://` scheme in the Buzz desktop
app. For example, `https://my-buzz.vercel.app` becomes
`wss://my-buzz.vercel.app`.

The template keeps Buzz's open-relay evaluation defaults. Before treating it as
a production community, configure the production controls described in
[`deploy/compose/.env.example`](../compose/.env.example), especially relay
membership, token auth, and an owner pubkey.

## Vercel constraints

This target is useful for evaluation and small workspaces, but it is not
equivalent to the always-on Compose deployment:

- WebSocket connections are terminated at the Function maximum duration.
  Buzz clients reconnect, but users will see periodic reconnects.
- Vercel Functions cap request and response payloads at 4.5 MB. Large media
  uploads and realistic Git clone/push payloads will exceed this limit.
- Containers scale to zero and their filesystem is ephemeral. Buzz uses the
  local filesystem only for disposable Git workspaces and caches; durable state
  remains in Postgres, Redis, and object storage.
- Huddle audio is disabled by default because its room state is process-local
  and Vercel may route peers to different instances.

For unrestricted Git/media payloads and long-lived WebSockets, use the
[production Compose deployment](../compose/README.md) or another always-on
container host.
