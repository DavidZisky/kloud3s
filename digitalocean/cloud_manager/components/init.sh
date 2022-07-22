#!/usr/bin/env bash

set -a
source .env
set +a

if [[ -z ${do_api_token} ]] || [[ -z ${ssh_fingerprint} ]] || [[ -z ${email} ]];
then
    echo "Token, SSH fingerprint and/or email values missing, please update .env file"
    exit 1
fi

if grep -q "PUT_SSH_FINGERPRINT_HERE" components/droplets_workers.json; then
  sed -i.bak "s,PUT_SSH_FINGERPRINT_HERE,$ssh_fingerprint," components/droplets_workers.json
fi

if grep -q "PUT_SSH_FINGERPRINT_HERE" components/droplet_master.json; then
  sed -i.bak "s,PUT_SSH_FINGERPRINT_HERE,$ssh_fingerprint," components/droplet_master.json
fi

if grep -q "PUT_EMAIL_HERE" components/dns-issuer.yaml; then
  sed -i.bak "s,PUT_EMAIL_HERE,$email," components/dns-issuer.yaml
fi

if grep -q "PUT_DO_TOKEN_HERE" delete_k3s_droplets.sh; then
  sed -i.bak "s,PUT_DO_TOKEN_HERE,$do_api_token," delete_k3s_droplets.sh
fi
