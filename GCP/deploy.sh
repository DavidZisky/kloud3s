#!/bin/bash
set -e

# Timing doesn't work on zsh currently (works on bash)
START_TIME=$(date "+%s")

# Put same user as in ssh key here
user=julien.sudan
# If set to true, your existing kubectl config will be OVERWRITTEN, if set to false, script will only download kubectl config for you
load_kube_config=true

#-----
# Below ZONE and PROJECT variables are just in case You don't have those defaults set up in gcloud (you should).
ZONE="europe-west1-b"
PROJECT="default"
DEFAULT_PROJECT=$(gcloud config list --format 'value(core.project)')
DEFAULT_ZONE=$(gcloud config list --format 'value(compute.zone)')
ZONE="${DEFAULT_ZONE:-$ZONE}"
PROJECT="${DEFAULT_PROJECT:-$PROJECT}"
CLUSTER_NAME="${1:-k3s}"
FW_RULE_NAME="allow-tcp-6443"

#Put your ssh private key path here if not default
privkeypath="/home/nedsi/.ssh/julien-rsa"

#Default ssh private key path
if [ -f "/home/$USER/.ssh/id_rsa" ]; then
  default_privkeypath=$(/home/"$USER"/.ssh/id_rsa)
fi
privkeypath=${default_privkeypath:-$privkeypath}

if [ "$2" = "delete" ]
then
  gcloud compute instances delete "$CLUSTER_NAME"-master "$CLUSTER_NAME"-worker1 "$CLUSTER_NAME"-worker2 "$CLUSTER_NAME"-worker3
  echo "Cluster $CLUSTER_NAME deleted"
  gcloud compute firewall-rules describe "$FW_RULE_NAME" --no-user-output-enabled --quiet >/dev/null 
  echo "Firewall rule $FW_RULE_NAME deleted"
  exit 0
fi

echo "----- K3S GO!!! -----"

# If you want to provide ssh key add this line under the gcloud command:
gcloud compute --project="$PROJECT" instances create "$CLUSTER_NAME"-master \
  --metadata=ssh-keys="julien.sudan:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDEauZPOCeD7ygrp1Z/tML12Q0gwlYg7WC2EIqJAgT9AD1t4cXCZ+4yMPpdZBbuRvCCaBXNz69VhSxqKXahtmOvlRkLRoZ03U5Xt60Le+oEI/FZFTKCRoAlMhEhlm+lVoeo736YusNe3N9bIqnK5KiKDCxBV1d4hiMlEHeeh1DA1thl/UYew7zNHn7Sibv06WZC7LmkYvtX2knCr3WJbufHCzwm9GaUYqEoZJJ7wxOjAIti2gHLXRgNQCqWoxa7E5XKJ9cqgTGMonGP4+Nw2NBzOwI2MeVwC1foTx1m89EBIUiClNc7KRYiKGCgBV1fGe+NSxVbIgHAfrWFxZro1olfGg+dvPWxPasT/wkGGvi7MbyFGjA1yKgQgWwnXOhs5BWle8Lm5kTs202T7YpCZ+QNE6mltuLCRF+/hk2hG6QErKBAz+KGD2btCn2rM725lX3/I4/NAQIslPlhdQrz+4kFXTjO5gi9jWXsBBtkvxR5WObq4bvaDNdBZ/Y4fVkOamM= julien.sudan@container-solutions.com" \
  --zone="$ZONE" \
  --machine-type=n1-standard-2 \
  --tags=k3smaster,k3s-"$CLUSTER_NAME" \
  --subnet=default \
  --network-tier=PREMIUM \
  --maintenance-policy=MIGRATE \
  --image-family=ubuntu-minimal-2004-lts \
  --image-project=ubuntu-os-cloud \
  --no-user-output-enabled >/dev/null &
  
gcloud compute --project="$PROJECT" instances create "$CLUSTER_NAME"-worker1 "$CLUSTER_NAME"-worker2 "$CLUSTER_NAME"-worker3 \
  --zone="$ZONE" \
  --machine-type=n1-standard-2 \
  --tags=k3s-"$CLUSTER_NAME" \
  --subnet=default \
  --network-tier=PREMIUM \
  --maintenance-policy=MIGRATE \
  --image-family=ubuntu-minimal-2004-lts \
  --image-project=ubuntu-os-cloud \
  --no-user-output-enabled >/dev/null &

# the existence of this rule needs to be checked before trying to create it, otherwise we risk running into an error.
gcloud compute --project="$PROJECT" firewall-rules create "$FW_RULE_NAME" \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:6443 \
  --source-ranges=0.0.0.0/0 \
  --no-user-output-enabled >/dev/null 

echo "----- VMs creating... -----"
sleep 7
master_public=$(gcloud compute instances describe --zone="$ZONE"  --project="$PROJECT" "$CLUSTER_NAME"-master --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
master_private=$(gcloud compute instances describe --zone="$ZONE"  --project="$PROJECT" "$CLUSTER_NAME"-master --format='get(networkInterfaces[0].networkIP)')
echo "----- Master node public IP: $master_public -----"

echo "----- Waiting for the master node... -----"
until ssh -i "$privkeypath" -q -o "StrictHostKeyChecking=no" -o "ConnectTimeout=3" $user@"$master_public" 'hostname' > /dev/null
do
  sleep 5
done

echo "----- Nodes ready... deploying k3s on master... -----"
ssh -i "$privkeypath" -q -o "StrictHostKeyChecking=no" -t $user@"$master_public" "curl -sfL https://get.k3s.io | sudo INSTALL_K3S_EXEC=\"server --tls-san=$master_public --node-external-ip=$master_public\" sh -" >/dev/null

token=$(ssh -i "$privkeypath" -q -o "StrictHostKeyChecking=no" -t $user@"$master_public" 'sudo cat /var/lib/rancher/k3s/server/node-token')

echo "----- K3s master deployed... -----"
echo "----- Downloading kubectl config... -----"
ssh -i "$privkeypath" -q -o "StrictHostKeyChecking=no" -t $user@"$master_public" "sudo cp /etc/rancher/k3s/k3s.yaml /home/$user && sudo chown $user:$user /home/$user/k3s.yaml"
scp_command="$user@$master_public:/home/$user/k3s.yaml ./k3s.yaml"
scp -i "$privkeypath" -o "StrictHostKeyChecking=no" $scp_command >/dev/null
sed -i.bak "s/127.0.0.1/$master_public/g" ./k3s.yaml
if [ "$load_kube_config" = "true" ]
then
  echo "----- Loading kubectl config... -----"
  mv ./k3s.yaml ~/.kube/config
fi

echo "----- Deploying worker nodes... -----"
for worker in $CLUSTER_NAME-worker1 $CLUSTER_NAME-worker2 $CLUSTER_NAME-worker3
do
  host=$(gcloud compute instances describe --project="$PROJECT" --zone="$ZONE" "$worker" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

  ssh -i "$privkeypath" -q -o "StrictHostKeyChecking=no" $user@"$host" "echo ${token} > /tmp/token.txt && curl -sfL https://get.k3s.io | sudo sh -s - agent --server https://${master_private}:6443 --token-file /tmp/token.txt --node-external-ip ${host}" &>/dev/null  &
done

echo "----- Deployment finished... waiting for all the nodes to become k3s ready... -----"
if [ "$load_kube_config" = "true" ]
then
  nodes_check=$(kubectl get nodes | grep -c Ready | tr -d ' ')
  while [ "$nodes_check" != "4" ]
  do
    echo "----- Waiting... -----"
    nodes_check=$(kubectl get nodes | grep -c Ready | tr -d ' ')
    sleep 6
  done
else
  nodes_check=$(ssh -i "$privkeypath" -q -o "StrictHostKeyChecking=no" "$user"@"$master_public" "sudo kubectl get nodes | grep -c Ready")
  while [ "$nodes_check" != "4" ]
  do
    echo "----- Waiting... -----"
    nodes_check=$(ssh -i "$privkeypath" -q -o "StrictHostKeyChecking=no" "$user"@"$master_public" "sudo kubectl get nodes | grep -c Ready")
    sleep 6
  done
  ssh -i "$privkeypath" -q -o "StrictHostKeyChecking=no" "$user"@"$master_public" "sudo kubectl get nodes"
fi

END_TIME=$(date "+%s")
echo "----- After $((END_TIME - START_TIME)) seconds - your cluster is ready :) -----"
