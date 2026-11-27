# ntfy

## Add or change a user / token

Generate a bcrypt hash and a token:

```bash
docker run --rm -it binwiederhier/ntfy:v2.28.0 user hash
docker run --rm binwiederhier/ntfy:v2.28.0 token generate
```

Edit the secrets:

```bash
sops edit apps/infra/ntfy/auth-secret.sops.yaml          # NTFY_AUTH_USERS, NTFY_AUTH_TOKENS
sops edit apps/infra/monitoring/ntfy-secret.sops.yaml    # token
sops edit apps/infra/grafana/ntfy-secret.sops.yaml       # token
```

Formats:

```
NTFY_AUTH_USERS:  "<user>:<hash>:<admin|user>,..."
NTFY_AUTH_TOKENS: "<user>:<token>:<label>,..."
```

ACLs: `apps/infra/ntfy/server.yml`.

Restart:

```bash
kubectl -n ntfy rollout restart deploy/ntfy
```

## Test

```bash
curl -u felix -d "hello from the homelab" https://ntfy.int.felixwallner.com/homelab-alerts
```

Through Alertmanager:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093
amtool alert add NtfyTest severity=warning --alertmanager.url=http://localhost:9093
```
