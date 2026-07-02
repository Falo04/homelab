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

Traefik exposes entrypoints split by which interface each Docker port is
published on, and each entrypoint serves its own domain:

| Entrypoint  | Container port | Published on           | Reachable from     | Domain                    |
| ----------- | -------------- | ---------------------- | ------------------ | ------------------------- |
| `web`       | `:80`          | all interfaces         | anywhere (→ HTTPS) | —                         |
| `websecure` | `:443`         | all interfaces         | anywhere           | `*.${ROOT_DOMAIN}`        |
| `tsadmin`   | `:8443`        | `${TAILSCALE_IP}` only | tailnet only       | `*.${INT_ROOT_DOMAIN}`    |

`websecure` is reserved for anything you want reachable publicly under
`*.${ROOT_DOMAIN}`; it currently has no routers.

Verify the binds on the host — `:8443` should show the Tailscale IP, while
`:443` shows `0.0.0.0`:

```bash
ss -tlnp | grep -E ':(80|443|8443)'
```

## 6. DNS

ACME uses **DNS-01**, so no inbound ports are needed for certificates — the
Cloudflare token lets Traefik create the `_acme-challenge` TXT records itself.
You only add the records clients use to reach the services:

| Name (in the zone) | Type | Value                       | Cloudflare proxy    |
| ------------------ | ---- | --------------------------- | ------------------- |
| `*.int`            | A    | `${TAILSCALE_IP}`           | **DNS only (grey)** |
| `*` (public hosts) | A    | your public/LAN IP          | your choice         |

- Internal hosts (`*.int.${ROOT_DOMAIN}`) resolve to the **Tailscale IP**. This
  is a public DNS record pointing at a private `100.x` address — off-tailnet
  clients get a dead IP they can't route to; tailnet clients connect. It must be
  **grey-cloud (DNS only)**: Cloudflare's proxy can't reach `100.x` and doesn't
  proxy port `8443`.
- Don't use MagicDNS `*.ts.net` names — the certs are issued for
  `*.int.${ROOT_DOMAIN}`, so a `ts.net` URL would throw a cert mismatch.

## 7. Certificates (wildcard)

Each entrypoint obtains a **single wildcard certificate** via DNS-01, rather
than one cert per hostname:

- `tsadmin` → `*.${INT_ROOT_DOMAIN}`
- `websecure` → `*.${ROOT_DOMAIN}`

Why wildcard here:

- **Add subdomains for free** — a new `*.int` host is already covered, no ACME
  round-trip, instant TLS.
- **Fewer ACME requests** — no per-host issuance, far less chance of hitting
  Let's Encrypt rate limits.
- **Certificate Transparency privacy** — per-host certs publish every hostname
  to public CT logs (searchable on crt.sh), leaking your internal service
  inventory. A wildcard logs only `*.int.${ROOT_DOMAIN}`, revealing nothing.

Tradeoff: one private key covers all subdomains (larger blast radius if leaked,
no per-host revocation). Acceptable for a single-host homelab. Wildcards
**require** DNS-01 — which is already how this is set up.
