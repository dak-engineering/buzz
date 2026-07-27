#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
entrypoint="$script_dir/entrypoint.sh"

run_entrypoint() {
    sed 's|exec /usr/local/bin/buzz-relay "$@"|env|' "$entrypoint" |
        env -i PATH="${PATH:-/usr/bin:/bin}" BUZZ_VERCEL_TEST_NO_PROXY=1 "$@" sh
}

assert_has() {
    output=$1
    expected=$2
    if ! printf '%s\n' "$output" | grep -Fqx "$expected"; then
        echo "entrypoint test: missing expected value: $expected" >&2
        exit 1
    fi
}

assert_lacks_prefix() {
    output=$1
    prefix=$2
    if printf '%s\n' "$output" | grep -Fq "$prefix"; then
        echo "entrypoint test: unexpected value with prefix: $prefix" >&2
        exit 1
    fi
}

base_output=$(
    run_entrypoint \
        VERCEL=1 \
        VERCEL_ENV=preview \
        VERCEL_URL=buzz-preview.vercel.app \
        PORT=80 \
        DATABASE_URL=postgresql://test \
        KV_URL=rediss://marketplace \
        BUZZ_S3_ACCESS_KEY=test-access \
        BUZZ_S3_SECRET_KEY=test-secret \
        BUZZ_S3_BUCKET=test-bucket \
        BUZZ_RELAY_PRIVATE_KEY=test-relay-key \
        BUZZ_GIT_HOOK_HMAC_SECRET=test-hook-key
)
assert_has "$base_output" "BUZZ_BIND_ADDR=127.0.0.1:3000"
assert_has "$base_output" "BUZZ_HEALTH_PORT=8080"
assert_has "$base_output" "BUZZ_METRICS_PORT=9102"
assert_has "$base_output" "REDIS_URL=rediss://marketplace"
assert_has "$base_output" "RELAY_URL=wss://buzz-preview.vercel.app"
assert_has "$base_output" "BUZZ_MEDIA_BASE_URL=https://buzz-preview.vercel.app/media"
assert_has "$base_output" "BUZZ_S3_ENDPOINT=https://t3.storage.dev"
assert_has "$base_output" "BUZZ_S3_REGION=auto"
assert_has "$base_output" "BUZZ_AUTO_MIGRATE=true"
assert_has "$base_output" "BUZZ_HUDDLE_AUDIO_AVAILABLE=false"

collision_output=$(
    run_entrypoint \
        VERCEL=1 \
        VERCEL_URL=buzz-preview.vercel.app \
        PORT=8080 \
        DATABASE_URL=postgresql://test \
        KV_URL=rediss://marketplace \
        BUZZ_S3_ACCESS_KEY=test-access \
        BUZZ_S3_SECRET_KEY=test-secret \
        BUZZ_S3_BUCKET=test-bucket \
        BUZZ_RELAY_PRIVATE_KEY=test-relay-key \
        BUZZ_GIT_HOOK_HMAC_SECRET=test-hook-key
)
assert_has "$collision_output" "BUZZ_BIND_ADDR=127.0.0.1:3000"
assert_has "$collision_output" "BUZZ_HEALTH_PORT=8081"
assert_has "$collision_output" "BUZZ_METRICS_PORT=9102"

port_3000_output=$(
    run_entrypoint \
        VERCEL=1 \
        VERCEL_URL=buzz-preview.vercel.app \
        PORT=3000 \
        DATABASE_URL=postgresql://test \
        KV_URL=rediss://marketplace \
        BUZZ_S3_ACCESS_KEY=test-access \
        BUZZ_S3_SECRET_KEY=test-secret \
        BUZZ_S3_BUCKET=test-bucket \
        BUZZ_RELAY_PRIVATE_KEY=test-relay-key \
        BUZZ_GIT_HOOK_HMAC_SECRET=test-hook-key
)
assert_has "$port_3000_output" "BUZZ_BIND_ADDR=127.0.0.1:3001"
assert_has "$port_3000_output" "BUZZ_HEALTH_PORT=8080"
assert_has "$port_3000_output" "BUZZ_METRICS_PORT=9102"

override_output=$(
    run_entrypoint \
        VERCEL=1 \
        VERCEL_ENV=production \
        VERCEL_URL=preview.vercel.app \
        VERCEL_PROJECT_PRODUCTION_URL=production.vercel.app \
        PORT=4500 \
        DATABASE_URL=postgresql://test \
        KV_URL=rediss://marketplace \
        REDIS_URL=rediss://canonical \
        BUZZ_BIND_ADDR=0.0.0.0:9000 \
        RELAY_URL=wss://custom.example \
        BUZZ_MEDIA_BASE_URL=https://custom.example/media \
        BUZZ_S3_ENDPOINT=https://s3.example \
        BUZZ_S3_REGION=custom \
        BUZZ_S3_ACCESS_KEY=test-access \
        BUZZ_S3_SECRET_KEY=test-secret \
        BUZZ_S3_BUCKET=test-bucket \
        BUZZ_RELAY_PRIVATE_KEY=test-relay-key \
        BUZZ_GIT_HOOK_HMAC_SECRET=test-hook-key \
        BUZZ_AUTO_MIGRATE=false \
        BUZZ_HUDDLE_AUDIO_AVAILABLE=true
)
assert_has "$override_output" "BUZZ_BIND_ADDR=0.0.0.0:9000"
assert_has "$override_output" "REDIS_URL=rediss://canonical"
assert_has "$override_output" "RELAY_URL=wss://custom.example"
assert_has "$override_output" "BUZZ_MEDIA_BASE_URL=https://custom.example/media"
assert_has "$override_output" "BUZZ_S3_ENDPOINT=https://s3.example"
assert_has "$override_output" "BUZZ_S3_REGION=custom"
assert_has "$override_output" "BUZZ_AUTO_MIGRATE=false"
assert_has "$override_output" "BUZZ_HUDDLE_AUDIO_AVAILABLE=true"

passthrough_output=$(run_entrypoint CUSTOM_VALUE=unchanged)
assert_has "$passthrough_output" "CUSTOM_VALUE=unchanged"
assert_lacks_prefix "$passthrough_output" "BUZZ_BIND_ADDR="
assert_lacks_prefix "$passthrough_output" "BUZZ_AUTO_MIGRATE="

if run_entrypoint \
    VERCEL=1 \
    VERCEL_URL=buzz-preview.vercel.app \
    PORT=4500 \
    DATABASE_URL=postgresql://test \
    BUZZ_S3_ACCESS_KEY=test-access \
    BUZZ_S3_SECRET_KEY=test-secret \
    BUZZ_S3_BUCKET=test-bucket \
    BUZZ_RELAY_PRIVATE_KEY=test-relay-key \
    BUZZ_GIT_HOOK_HMAC_SECRET=test-hook-key \
    >/dev/null 2>&1; then
    echo "entrypoint test: missing Upstash KV_URL should fail" >&2
    exit 1
fi

if run_entrypoint VERCEL=1 PORT=0 >/dev/null 2>&1; then
    echo "entrypoint test: port zero should fail" >&2
    exit 1
fi

echo "Vercel entrypoint tests passed"
