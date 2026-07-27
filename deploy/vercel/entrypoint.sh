#!/bin/sh
# Translate Vercel and Marketplace variables into Buzz's existing deployment
# contract. Outside Vercel this is a transparent pass-through.
set -eu

require_nonempty() {
    eval "value=\${$1:-}"
    if [ -z "$value" ]; then
        echo "buzz-vercel-entrypoint: required environment variable $1 is missing or empty" >&2
        exit 1
    fi
}

if [ "${VERCEL:-}" = "1" ]; then
    case "${PORT:-}" in
        "" | *[!0-9]*)
            echo "buzz-vercel-entrypoint: PORT must be a numeric TCP port" >&2
            exit 1
            ;;
    esac
    if [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; then
        echo "buzz-vercel-entrypoint: PORT must be between 1024 and 65535" >&2
        exit 1
    fi

    if [ "${BUZZ_BIND_ADDR+x}" != "x" ]; then
        export BUZZ_BIND_ADDR="0.0.0.0:$PORT"
    fi

    # The relay also opens private health and metrics listeners. Keep their
    # defaults from colliding with Vercel's assigned application port.
    if [ "$PORT" -le 65533 ]; then
        health_port=$((PORT + 1))
        metrics_port=$((PORT + 2))
    else
        health_port=$((PORT - 1))
        metrics_port=$((PORT - 2))
    fi
    if [ "${BUZZ_HEALTH_PORT+x}" != "x" ]; then
        export BUZZ_HEALTH_PORT="$health_port"
    fi
    if [ "${BUZZ_METRICS_PORT+x}" != "x" ]; then
        export BUZZ_METRICS_PORT="$metrics_port"
    fi

    if [ "${REDIS_URL+x}" != "x" ]; then
        require_nonempty KV_URL
        export REDIS_URL="$KV_URL"
    fi

    if [ "${VERCEL_ENV:-}" = "production" ]; then
        public_host="${VERCEL_PROJECT_PRODUCTION_URL:-${VERCEL_URL:-}}"
    else
        public_host="${VERCEL_URL:-${VERCEL_PROJECT_PRODUCTION_URL:-}}"
    fi
    if [ "${RELAY_URL+x}" != "x" ] || [ "${BUZZ_MEDIA_BASE_URL+x}" != "x" ]; then
        if [ -z "$public_host" ]; then
            echo "buzz-vercel-entrypoint: VERCEL_URL is required when public Buzz URLs are not set" >&2
            exit 1
        fi
    fi
    if [ "${RELAY_URL+x}" != "x" ]; then
        export RELAY_URL="wss://$public_host"
    fi
    if [ "${BUZZ_MEDIA_BASE_URL+x}" != "x" ]; then
        export BUZZ_MEDIA_BASE_URL="https://$public_host/media"
    fi

    if [ "${BUZZ_S3_ENDPOINT+x}" != "x" ]; then
        export BUZZ_S3_ENDPOINT="https://t3.storage.dev"
    fi
    if [ "${BUZZ_S3_REGION+x}" != "x" ]; then
        export BUZZ_S3_REGION="auto"
    fi
    if [ "${BUZZ_AUTO_MIGRATE+x}" != "x" ]; then
        export BUZZ_AUTO_MIGRATE="true"
    fi
    if [ "${BUZZ_HUDDLE_AUDIO_AVAILABLE+x}" != "x" ]; then
        export BUZZ_HUDDLE_AUDIO_AVAILABLE="false"
    fi

    require_nonempty DATABASE_URL
    require_nonempty REDIS_URL
    require_nonempty BUZZ_S3_ACCESS_KEY
    require_nonempty BUZZ_S3_SECRET_KEY
    require_nonempty BUZZ_S3_BUCKET
    require_nonempty BUZZ_RELAY_PRIVATE_KEY
    require_nonempty BUZZ_GIT_HOOK_HMAC_SECRET
fi

exec /usr/local/bin/buzz-relay "$@"
