# Homelab compose management
# Usage: `just <recipe> [stack]`  where stack is one of: traefik, vault, all (default)

set shell := ["bash", "-uc"]

# List of every managed stack
stacks := "traefik vault"

# Default recipe: show the available commands
default:
    @just --list

# Resolve the `docker compose ...` invocation for a given stack
_dc stack:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{stack}}" in
      traefik) echo "docker compose -f traefik/traefik-docker-compose.yaml --env-file .env --env-file traefik/enviromnet.env" ;;
      vault)   echo "docker compose -f vault/docker-compose.yml --env-file .env" ;;
      *) echo "unknown stack: {{stack}} (expected: traefik, vault)" >&2; exit 1 ;;
    esac

# Expand "all" into the full stack list, otherwise echo the single stack back
_stacks stack="all":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{stack}}" = "all" ]; then echo "{{stacks}}"; else echo "{{stack}}"; fi

# Ensure the external `internal` network the vault expects exists
ensure-net:
    @docker network inspect internal >/dev/null 2>&1 || docker network create internal

# Start stack(s) in the background (creates the shared network first)
up stack="all": ensure-net
    #!/usr/bin/env bash
    set -euo pipefail
    for s in $(just _stacks {{stack}}); do
      echo "==> up: $s"
      $(just _dc "$s") up -d
    done

# Stop and remove stack(s)
down stack="all":
    #!/usr/bin/env bash
    set -euo pipefail
    for s in $(just _stacks {{stack}}); do
      echo "==> down: $s"
      $(just _dc "$s") down
    done

# Restart stack(s)
restart stack="all":
    #!/usr/bin/env bash
    set -euo pipefail
    for s in $(just _stacks {{stack}}); do
      echo "==> restart: $s"
      $(just _dc "$s") restart
    done

# Recreate stack(s) from scratch (down then up)
recreate stack="all": (down stack) (up stack)

# Pull the latest images for stack(s)
pull stack="all":
    #!/usr/bin/env bash
    set -euo pipefail
    for s in $(just _stacks {{stack}}); do
      echo "==> pull: $s"
      $(just _dc "$s") pull
    done

# Pull latest images and recreate stack(s)
update stack="all": (pull stack) (up stack)

# Show container status for stack(s)
ps stack="all":
    #!/usr/bin/env bash
    set -euo pipefail
    for s in $(just _stacks {{stack}}); do
      echo "==> ps: $s"
      $(just _dc "$s") ps
    done

# Follow logs for a single stack (optionally a specific service)
logs stack service="":
    $(just _dc {{stack}}) logs -f --tail=100 {{service}}

# Render the fully-resolved compose config for a stack
config stack:
    $(just _dc {{stack}}) config

# Validate every stack's compose file
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    for s in {{stacks}}; do
      echo "==> lint: $s"
      $(just _dc "$s") config -q && echo "ok"
    done

# Run a one-off command in a service, e.g. `just exec vault vault1 sh`
exec stack service +cmd:
    $(just _dc {{stack}}) exec {{service}} {{cmd}}

# Remove stopped containers, dangling images and unused networks
prune:
    docker system prune -f
