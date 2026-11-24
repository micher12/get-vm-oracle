#!/usr/bin/env bash
# Tentativa de launch da VM Ampere A1 Always Free a partir do GitHub Actions.
set -euo pipefail

: "${OCI_USER:?OCI_USER obrigatorio}"
: "${OCI_TENANCY:?OCI_TENANCY obrigatorio}"
: "${OCI_FINGERPRINT:?OCI_FINGERPRINT obrigatorio}"
: "${OCI_REGION:?OCI_REGION obrigatorio}"
: "${OCI_PRIVATE_KEY_B64:?OCI_PRIVATE_KEY_B64 obrigatorio}"
: "${OCI_SUBNET_ID:?OCI_SUBNET_ID obrigatorio}"
: "${OCI_IMAGE_ID:?OCI_IMAGE_ID obrigatorio}"
: "${OCI_AD:?OCI_AD obrigatorio}"
: "${OCI_SSH_PUBLIC_KEY:?OCI_SSH_PUBLIC_KEY obrigatorio}"

MAX_ATTEMPTS="${MAX_ATTEMPTS:-20}"
SLEEP_SECONDS="${SLEEP_SECONDS:-60}"

mkdir -p "$HOME/.oci"
cat > "$HOME/.oci/config" <<EOF
[DEFAULT]
user=$OCI_USER
fingerprint=$OCI_FINGERPRINT
key_file=$HOME/.oci/oci_api_key.pem
tenancy=$OCI_TENANCY
region=$OCI_REGION
EOF
printf '%s' "$OCI_PRIVATE_KEY_B64" | base64 -d > "$HOME/.oci/oci_api_key.pem"
chmod 600 "$HOME/.oci/oci_api_key.pem"

printf '%s\n' "$OCI_SSH_PUBLIC_KEY" > "$RUNNER_TEMP/oci_authorized_keys"

launched=""
for ((i = 1; i <= MAX_ATTEMPTS; i++)); do
  echo "=== tentativa $i/$MAX_ATTEMPTS ==="
  if out=$(oci compute instance launch \
      --availability-domain "$OCI_AD" \
      --compartment-id "$OCI_TENANCY" \
      --subnet-id "$OCI_SUBNET_ID" \
      --image-id "$OCI_IMAGE_ID" \
      --shape VM.Standard.A1.Flex \
      --shape-config '{"ocpus":2,"memoryInGBs":12}' \
      --ssh-authorized-keys-file "$RUNNER_TEMP/oci_authorized_keys" \
      --assign-public-ip true \
      --boot-volume-size-in-gbs 50 \
      --display-name 'a1-free-ubuntu' \
      --query 'data.id' --raw-output 2>&1); then
    launched="$out"
    echo "VM CRIADA: $launched"
    printf '%s\n' "$launched" > instance-id.txt
    break
  fi

  echo "$out"
  if echo "$out" | grep -qiE 'out of (host )?capacity|InternalError|TooManyRequests|ServiceUnavailable'; then
    echo "Sem capacidade. Aguardando ${SLEEP_SECONDS}s..."
    sleep "$SLEEP_SECONDS"
  else
    echo "Erro nao recuperavel. Abortando."
    exit 1
  fi
done

if [[ -z "$launched" ]]; then
  echo "Falhou apos $MAX_ATTEMPTS tentativas."
  exit 2
fi

echo "Aguardando estado RUNNING..."
for ((i = 0; i < 60; i++)); do
  state=$(oci compute instance get --instance-id "$launched" \
      --query "data['lifecycle-state']" --raw-output 2>/dev/null || true)
  [[ "$state" == "RUNNING" ]] && break
  sleep 15
done

public_ip=$(oci compute instance list-vnics --instance-id "$launched" \
    --query "data[0]['public-ip']" --raw-output 2>/dev/null || true)
private_ip=$(oci compute instance list-vnics --instance-id "$launched" \
    --query "data[0]['private-ip']" --raw-output 2>/dev/null || true)

cat > vm-info.txt <<EOF
instance_id=$launched
public_ip=$public_ip
private_ip=$private_ip
ssh_user=ubuntu
EOF
echo "===== VM PRONTA ====="
cat vm-info.txt
