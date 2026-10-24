#!/bin/sh
# Daily Vault raft snapshot into a restic repository on Garage.
set -eu

SNAPSHOT=/tmp/vault-raft.snap

FAILURES=0
NOTIFY_EVERY=5

ERROR_LOG="\e[31mERROR\e[0m:"
INFO_LOG="\e[43mINFO\e[0m:"

log() {
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"
}

notify_failure() {
  FAILURES=$((FAILURES + 1))

  if [ "$FAILURES" -ne 1 ] && [ $((FAILURES % NOTIFY_EVERY)) -ne 0 ]; then
    log "$INFO_LOG alert suppressed, $FAILURES consecutive failures"
    return 0
  fi

  wget -qO- \
    --header="Authorization: Bearer $NTFY_TOKEN" \
    --header="Title: Vault backup failed" \
    --header="Priority: high" \
    --header="Tags: rotating_light" \
    --post-data="$1 ($FAILURES consecutive failure(s))" \
    "$NTFY_URL" >/dev/null 2>&1 ||
    log "$ERROR_LOG ntfy unreachable, alert not delivered"

  return 0
}

backup() {
  token=$(
    wget -qO- \
      --post-data="{\"role_id\":\"$VAULT_BACKUP_ROLE_ID\",\"secret_id\":\"$VAULT_BACKUP_SECRET_ID\"}" \
      "$VAULT_ADDR/v1/auth/approle/login" | jq -er .auth.client_token
  ) || token=""
  if [ -z "$token" ]; then
    echo "$ERROR_LOG approle login failed" >&2
    return 1
  fi

  rm -f "$SNAPSHOT"
  # Revoke the token as soon as the snapshot is out, whether or not it worked.
  snapshot_ok=0
  wget -q --header="X-Vault-Token: $token" -O "$SNAPSHOT" \
    "$VAULT_ADDR/v1/sys/storage/raft/snapshot" || snapshot_ok=1
  wget -qO- --header="X-Vault-Token: $token" --post-data="" \
    "$VAULT_ADDR/v1/auth/token/revoke-self" >/dev/null 2>&1 ||
    log "$INFO_LOG token revoke failed, it expires on its own TTL"
  [ "$snapshot_ok" -eq 0 ] || return 1

  # `set -e` is suspended inside `if backup`, so every step has to fail
  # the function explicitly or a broken run is reported as ok.
  gzip -t "$SNAPSHOT" || return 1
  log "$INFO_LOG snapshot ok, $(wc -c <"$SNAPSHOT") bytes"

  restic cat config >/dev/null 2>&1 || restic init || return 1

  restic backup "$SNAPSHOT" --host vault --tag vault || return 1
  restic forget --host vault --tag vault \
    --keep-hourly 24 \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6 \
    --prune || return 1
  restic snapshots --host vault --tag vault --latest 1
}

while :; do
  if backup; then
    if [ "$FAILURES" -gt 0 ]; then
      log "$INFO_LOG backup ok, recovered after $FAILURES failed run(s)"
    else
      log "$INFO_LOG backup ok"
    fi
    FAILURES=0
  else
    log "$ERROR_LOG backup FAILED"
    notify_failure "Vault raft snapshot backup failed at $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  fi
  rm -f "$SNAPSHOT"

  sleep $((86400 - $(date +%s) % 86400))
done
