#!/bin/bash
# Writes every out-of-band Secret the releases need as a SOPS-encrypted
# manifest under releases/secrets/. Plaintext never touches disk: each Secret
# is rendered by `kubectl create --dry-run` and piped straight into `sops -e`.
#
#   bash scripts/seal-secrets.sh            # (re)seal all of them
#   bash scripts/seal-secrets.sh gemini     # only the ones named
#
# Asks only for the ghcr token; the bearer tokens, the LLM virtual key and the
# xray snapshot identity are random.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=releases/secrets
only=("$@")

want() { [[ ${#only[@]} -eq 0 ]] || printf '%s\n' "${only[@]}" | grep -qxF "$1"; }
seal() { # name file -- stdin is the Secret manifest
  sops --encrypt --filename-override "$OUT/$1.sops.yaml" --input-type yaml --output-type yaml /dev/stdin > "$OUT/$1.sops.yaml"
  echo "sealed $OUT/$1.sops.yaml"
}
kc() { kubectl create --dry-run=client -o yaml "$@"; }

if want ghcr; then
  default_user=$(gh api user --jq .login 2>/dev/null || true)
  read -r -p "ghcr username [${default_user}]: " GHCR_USER; GHCR_USER=${GHCR_USER:-$default_user}
  read -r -s -p "ghcr token with read:packages (empty = \`gh auth token\`): " GHCR_TOKEN; echo
  GHCR_TOKEN=${GHCR_TOKEN:-$(gh auth token)}
  # flux-system: OCIRepository secretRef for the private triage-core/triage-agent charts.
  kc secret docker-registry ghcr-credentials -n flux-system \
    --docker-server=ghcr.io --docker-username="$GHCR_USER" --docker-password="$GHCR_TOKEN" | seal ghcr-credentials
  # triage: imagePullSecrets for triage pods + secretRef for the triage-namespace OCIRepositories.
  kc secret docker-registry triage-ghcr-pull -n triage \
    --docker-server=ghcr.io --docker-username="$GHCR_USER" --docker-password="$GHCR_TOKEN" | seal triage-ghcr-pull
  unset GHCR_TOKEN
fi

if want llm; then
  # agentgateway-llm's "kagent" virtual key, and the same value for kagent's
  # default-model-config to present. Random -- only these two sides use it.
  KAGENT_LLM_KEY=$(openssl rand -hex 32)
  kc secret generic agentgateway-llm-secrets -n agentgateway-system \
    --from-literal=KAGENT_LLM_KEY="$KAGENT_LLM_KEY" | seal agentgateway-llm-secrets
  kc secret generic kagent-llm-key -n kagent \
    --from-literal=OPENAI_API_KEY="$KAGENT_LLM_KEY" | seal kagent-llm-key
  unset KAGENT_LLM_KEY
fi

if want xray; then
  kc secret generic xray-memory-auth -n xray-memory \
    --from-literal=token="$(openssl rand -hex 32)" | seal xray-memory-auth
  # A fresh identity: maps encrypted to someone else's key are skipped with a
  # warning, anything this server writes is ours.
  kc secret generic xray-memory-snapshot-key -n xray-memory \
    --from-literal=identity="$(age-keygen 2>/dev/null)" | seal xray-memory-snapshot-key
fi
