#!/bin/bash
set -e

# Timing doesn't work on zsh currently (works on bash)
START_TIME=`date "+%s"`

# Put same user as in ssh key here
user=dave
# If set to true, your existing kubectl config will be OVERWRITTEN, if set to false, script will only download kubectl config for you
load_kube_config=true

#-----
# Below ZONE and PROJECT variables are just in case You don't have those defaults set up in gcloud (you should).
ZONE="europe-west4-a"
PROJECT="default"
DEFAULT_PROJECT=`gcloud config list --format 'value(core.project)'`
DEFAULT_ZONE=`gcloud config list --format 'value(compute.zone)'`
ZONE="${DEFAULT_ZONE:-$ZONE}"
PROJECT="${DEFAULT_PROJECT:-$PROJECT}"
CLUSTER_NAME="${1:-k3s}"

if [ "$2" = "delete" ]
then
  gcloud compute instances delete $CLUSTER_NAME-master $CLUSTER_NAME-worker1 $CLUSTER_NAME-worker2 $CLUSTER_NAME-worker3
  echo "Cluster $CLUSTER_NAME deleted"
  exit 0
fi

echo "----- K3S GO!!! -----"

# If you want to provide ssh key add this line:
#--metadata=ssh-keys="[USER_AS_IN_SSH_KEY]:[YOUR_SSH_KEY_HERE]" \
gcloud compute --project=$PROJECT instances create $CLUSTER_NAME-master \
--zone=$ZONE \
--machine-type=n1-standard-2 \
--tags=k3smaster,k3s-$CLUSTER_NAME \
--subnet=default \
--network-tier=PREMIUM \
--maintenance-policy=MIGRATE \
--image=ubuntu-minimal-1910-eoan-v20200521 \
--image-project=ubuntu-os-cloud \
--no-user-output-enabled >/dev/null &

gcloud compute --project=$PROJECT instances create $CLUSTER_NAME-worker1 $CLUSTER_NAME-worker2 $CLUSTER_NAME-worker3 \
--zone=$ZONE \
--machine-type=n1-standard-2 \
--tags=k3s-$CLUSTER_NAME \
--subnet=default \
--network-tier=PREMIUM \
--maintenance-policy=MIGRATE \
--image=ubuntu-minimal-1910-eoan-v20200521 \
--image-project=ubuntu-os-cloud \
--no-user-output-enabled >/dev/null &

echo "----- VMs creating... -----"
sleep 7
master_public=`gcloud compute instances describe --zone=$ZONE  --project=$PROJECT $CLUSTER_NAME-master --format='get(networkInterfaces[0].accessConfigs[0].natIP)'`
master_private=`gcloud compute instances describe --zone=$ZONE  --project=$PROJECT $CLUSTER_NAME-master --format='get(networkInterfaces[0].networkIP)'`
echo "----- Master node public IP: $master_public -----"
ssh-keygen -R $master_public > /dev/null


until ssh -q -o "StrictHostKeyChecking=no" -o "ConnectTimeout=3" $user@$master_public 'hostname' > /dev/null
do
  echo "----- Waiting for the nodes... -----"
  sleep 3
done

echo "----- Nodes ready... deploying k3s on master... -----"
ssh -q -o "StrictHostKeyChecking=no" $user@$master_public 'sudo modprobe ip_vs'
ssh -q -o "StrictHostKeyChecking=no" -t $user@$master_public "curl -sfL https://get.k3s.io | sudo INSTALL_K3S_EXEC=\"server --tls-san=$master_public\" sh -" >/dev/null

token=`ssh -q -o "StrictHostKeyChecking=no" -t $user@$master_public 'sudo cat /var/lib/rancher/k3s/server/node-token'`

echo "----- K3s master deployed... -----"
echo "----- Downloading kubectl config... -----"
ssh -q -o "StrictHostKeyChecking=no" -t $user@$master_public "sudo cp /etc/rancher/k3s/k3s.yaml /home/$user && sudo chown $user:$user /home/$user/k3s.yaml"
scp_command="$user@$master_public:/home/$user/k3s.yaml ./k3s.yaml"
scp $scp_command >/dev/null
sed -i.bak "s/127.0.0.1/$master_public/g" ./k3s.yaml
if [ "$load_kube_config" = "true" ]
then
  echo "----- Loading kubectl config... -----"
  mv ./k3s.yaml ~/.kube/config
fi

echo "----- Deploying worker nodes... -----"
for worker in $CLUSTER_NAME-worker1 $CLUSTER_NAME-worker2 $CLUSTER_NAME-worker3
do
  host=`gcloud compute instances describe --project=$PROJECT --zone=$ZONE $worker --format='get(networkInterfaces[0].accessConfigs[0].natIP)'`
  ssh-keygen -R $host > /dev/null
  ssh -q -o "StrictHostKeyChecking=no" $user@$host 'sudo modprobe ip_vs'
  ssh -q -o "StrictHostKeyChecking=no" $user@$host "curl -sfL https://get.k3s.io | sudo K3S_TOKEN=${token} K3S_URL=https://${master_private}:6443 sh -" &>/dev/null  &
done

echo "----- Deployment finished... waiting for all the nodes to become k3s ready... -----"
if [ "$load_kube_config" = "true" ]
then
  nodes_check=`kubectl get nodes | grep Ready | wc -l | tr -d ' '`
  while [ "$nodes_check" != "4" ]
  do
    echo "----- Waiting... -----"
    nodes_check=`kubectl get nodes | grep Ready | wc -l | tr -d ' '`
    sleep 3
  done
else
  nodes_check=`ssh -q -o "StrictHostKeyChecking=no" $user@$master_public "sudo kubectl get nodes | grep Ready | wc -l"`
  while [ "$nodes_check" != "4" ]
  do
    echo "----- Waiting... -----"
    nodes_check=`ssh -q -o "StrictHostKeyChecking=no" $user@$master_public "sudo kubectl get nodes | grep Ready | wc -l"`
    sleep 3
  done
  ssh -q -o "StrictHostKeyChecking=no" $user@$master_public "sudo kubectl get nodes"
fi

END_TIME=`date "+%s"`
echo "----- After $((${END_TIME} - ${START_TIME})) seconds - your cluster is ready :) -----"
