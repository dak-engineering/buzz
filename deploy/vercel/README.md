# Deploy Buzz on Vercel

This is an experimental, evaluation-oriented deployment of the Buzz relay as a
Vercel container Function.

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Fdak-engineering%2Fbuzz&project-name=buzz&repository-name=buzz-vercel&stores=%5B%7B%22type%22%3A%22integration%22%2C%22protocol%22%3A%22storage%22%2C%22productSlug%22%3A%22neon%22%2C%22integrationSlug%22%3A%22neon%22%2C%22allowConnectExistingProduct%22%3Atrue%7D%2C%7B%22type%22%3A%22integration%22%2C%22protocol%22%3A%22storage%22%2C%22productSlug%22%3A%22upstash-kv%22%2C%22integrationSlug%22%3A%22upstash%22%2C%22allowConnectExistingProduct%22%3Atrue%7D%5D&env=TIGRIS_STORAGE_ACCESS_KEY_ID%2CTIGRIS_STORAGE_SECRET_ACCESS_KEY%2CTIGRIS_STORAGE_BUCKET%2CBUZZ_RELAY_PRIVATE_KEY%2CBUZZ_GIT_HOOK_HMAC_SECRET&envDescription=Tigris+S3-compatible+bucket+credentials+plus+two+stable+32-byte+hex+secrets.+Generate+each+Buzz+secret+with%3A+openssl+rand+-hex+32&envLink=https%3A%2F%2Fgithub.com%2Fdak-engineering%2Fbuzz%2Fblob%2Fmain%2Fdeploy%2Fvercel%2FREADME.md%23required-values)

The deploy flow:

1. clones this repository into your Git provider;
2. creates a Vercel project;
3. provisions or connects Neon Postgres and Upstash Redis through the Vercel
   Marketplace;
4. asks for object-storage credentials and two stable Buzz secrets; and
5. builds the existing root `Dockerfile` as a Vercel container Function.

Neon injects `DATABASE_URL`. Upstash injects `KV_URL`, which Buzz accepts as a
fallback for `REDIS_URL`. Buzz also derives its bind port and public relay/media
URLs from Vercel's system environment variables and runs database migrations
automatically on Vercel.

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
| `TIGRIS_STORAGE_ACCESS_KEY_ID` | Tigris access key (`tid_...`) |
| `TIGRIS_STORAGE_SECRET_ACCESS_KEY` | Tigris secret key (`tsec_...`) |
| `TIGRIS_STORAGE_BUCKET` | Existing bucket name |
| `BUZZ_RELAY_PRIVATE_KEY` | Stable Nostr relay key: `openssl rand -hex 32` |
| `BUZZ_GIT_HOOK_HMAC_SECRET` | Stable hook secret: `openssl rand -hex 32` |

Buzz supplies Tigris's standard endpoint (`https://t3.storage.dev`) and signing
region (`auto`) when those variables are present.

The relay runs its Git object-store conformance probe before accepting traffic.
This is deliberate: if Tigris or another S3-compatible provider does not
provide the conditional-write semantics Buzz needs, startup fails instead of
risking Git ref corruption. AWS S3 or another backend that passes the same
probe can be configured with the existing `BUZZ_S3_*` variables.

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

