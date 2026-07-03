# homelab

## Prerequisites

- Docker + Docker Compose plugin
- [`just`](https://github.com/casey/just)
- A domain managed in Cloudflare
- A Cloudflare API **token** (not the global key) scoped to:
  - **Zone → DNS → Edit**
  - **Zone → Zone → Read**

  restricted to the zone(s) you use.

## 1. Configure environment

Two env files are loaded by the justfile.

### `.env` (repo root, shared by all stacks)

```env
ROOT_DOMAIN=example.com
INT_ROOT_DOMAIN=int.example.com
# Tailscale IP of this host — Traefik publishes its ports only on this address.
# Find it with: tailscale ip -4
TAILSCALE_IP=100.x.x.x
```

### `traefik/enviromnet.env` (Cloudflare/ACME tuning)

```env
HTTP_TIMEOUT=60
POLLING_INTERVAL=5
PROPAGATION_TIMEOUT=600
TTL=120
LOG_LEVEL=INFO
```

> These files contain no secrets, but `.env` is gitignored anyway. Copy the
> snippets above and adjust the values for your setup.

## 2. Provide the Cloudflare token

Traefik needs the Cloudflare token **at startup** to solve the DNS-01 challenge
and issue certificates — it is a bootstrap credential. It's mounted as a Docker
secret from a file:

```bash
printf '%s' 'YOUR_CLOUDFLARE_API_TOKEN' > traefik/cloudflare-token.txt
```

This file is **gitignored** and must never be committed.

## 3. Start the stacks

The `up` recipe creates the shared `internal` network automatically.

```bash
just up          # start everything (traefik + vault)
just up traefik  # or start a single stack
just up vault
```

Run `just` with no arguments to list all recipes.

## 4. Initialize Vault (first run only)

See [blog post](https://support.hashicorp.com/hc/en-us/articles/41778354863379-Vault-server-cluster-deployment-and-version-upgrade-via-docker-compose) for more detailed informations.

Vault starts **sealed and uninitialized**. Initialize it once:

```bash
just exec vault vault operator init
```

Save the **unseal keys** and **root token** it prints somewhere safe — they are
shown only once. Then unseal (repeat with enough keys to meet the threshold):

```bash
just exec vault vault operator unseal   # run for each required key share
```

Vault must be unsealed again after every restart of the container (unless you
configure auto-unseal).

## 5. Access

Services are split across two entrypoints by how they're exposed. Traefik sits on
two Docker networks: `internal` (Tailscale-exposed) and `external` (Cloudflare-
tunnel-exposed).

| Entrypoint  | Container bind    | Network    | Reachable from        | Domain                     |
| ----------- | ----------------- | ---------- | --------------------- | -------------------------- |
| `web`       | `:80`             | internal   | tailnet only          | redirects → `tsadmin`      |
| `tsadmin`   | `:443`            | internal   | tailnet only          | `traefik.${INT_ROOT_DOMAIN}` |
| `websecure` | `172.30.0.2:8443` | external   | Cloudflare tunnel only | `vault.${ROOT_DOMAIN}`     |

- `web`/`tsadmin` are published on the host **only** on `${TAILSCALE_IP}`, so
  they're reachable exclusively over the tailnet. `http://…:80` permanently
  redirects to `https://…` on `tsadmin`.
- `websecure` is **not published on the host at all**. It binds solely to
  Traefik's fixed IP on the `external` network (`172.30.0.2:8443`), so the only
  thing that can reach it is the `cloudflared` container on that same network — a
  call to the host/LAN/Tailscale IP is refused (nothing is listening there).

Tailnet services (from a Tailscale-connected device):

- `https://traefik.${INT_ROOT_DOMAIN}` — Traefik dashboard

Public services (via the Cloudflare tunnel, from anywhere incl. the Kubernetes
cluster):

- `https://vault.${ROOT_DOMAIN}` — Vault UI

Verify the binds — on the **host**, only `:80` and `:443` show the Tailscale IP,
and `:8443` is absent (not published):

```bash
ss -tlnp | grep -E ':(80|443)'      # both on ${TAILSCALE_IP}
ss -tlnp | grep ':8443'             # nothing
```

Inside the Traefik container, `:8443` binds only to `172.30.0.2` — not `0.0.0.0`:

```bash
docker exec traefik sh -c 'netstat -ltn' | grep 8443
```

### Publishing Vault through the Cloudflare tunnel

The `cloudflared` tunnel is **token-managed** (`TUNNEL_TOKEN`), so its ingress is
configured in the Cloudflare Zero Trust dashboard, not in this repo. Add a
**public hostname** to the tunnel:

- Hostname: `vault.${ROOT_DOMAIN}` (this creates the proxied CNAME automatically)
- Service: `https://traefik:8443` — `traefik` resolves to `172.30.0.2` on the
  `external` network; the original `Host`/SNI is preserved so Traefik's router
  and the per-host cert both match.
- Origin settings: set **Origin Server Name = `vault.${ROOT_DOMAIN}`** so the
  Let's Encrypt cert validates (or enable **No TLS Verify** to skip pinning).

## 6. DNS

ACME uses **DNS-01**, so no inbound ports are needed for certificates — the
Cloudflare token lets Traefik create the `_acme-challenge` TXT records itself.
You only add the records clients use to reach the services:

| Name (in the zone) | Type  | Value                          | Cloudflare proxy      |
| ------------------ | ----- | ------------------------------ | --------------------- |
| `traefik.int`      | A     | `${TAILSCALE_IP}`              | **DNS only (grey)**   |
| `vault`            | CNAME | `<tunnel-id>.cfargotunnel.com` | **Proxied (orange)**  |

- Internal hosts (`*.int.${ROOT_DOMAIN}`) resolve to the **Tailscale IP**. This
  is a public DNS record pointing at a private `100.x` address — off-tailnet
  clients get a dead IP they can't route to; tailnet clients connect. It must be
  **grey-cloud (DNS only)**: Cloudflare's proxy can't reach `100.x`.
- `vault.${ROOT_DOMAIN}` is created automatically when you add the tunnel's public
  hostname and is **proxied (orange)** — traffic reaches Traefik over the tunnel,
  never a direct inbound port.
- Don't use MagicDNS `*.ts.net` names — the internal cert is issued for
  `traefik.${INT_ROOT_DOMAIN}`, so a `ts.net` URL would throw a cert mismatch.

## 7. Certificates (per-host)

Both TLS entrypoints obtain **per-host certificates** via DNS-01 — no wildcard.
The Pi runs only two services (everything else is in Kubernetes), so there's
nothing to amortise a wildcard over:

- `tsadmin` → `traefik.${INT_ROOT_DOMAIN}` (dashboard)
- `websecure` → `vault.${ROOT_DOMAIN}` (Vault, via the tunnel)

Each cert is requested straight from the router's `Host(...)` rule — a docker
router's `tls=true` does **not** inherit the entrypoint's certResolver, so each
router carries `tls.certresolver=letsencrypt` explicitly.
