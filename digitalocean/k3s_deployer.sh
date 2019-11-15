#!/bin/bash
set -eu

START_TIME=`date "+%s"`

# Paste your DO token below
do_api_token=""
# Set below to false if you don't want your existing kube config to be overwriten. Config for k3s cluster will be still downloaded so you can use it manually or append
load_kube_config="true"

echo "1. Create Master VM"
curl -s -X POST \
  https://api.digitalocean.com/v2/droplets \
  -H "Authorization: Bearer $do_api_token" \
  -H "Content-Type: application/json" \
  --data @droplet_master.json > /dev/null

echo "2. Create Workers VMs"
curl -s -X POST \
  https://api.digitalocean.com/v2/droplets \
  -H "Authorization: Bearer $do_api_token" \
  -H "Content-Type: application/json" \
  --data @droplets_workers.json > /dev/null

get_master_ip () {
  master_ip=`curl -s -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $do_api_token" "https://api.digitalocean.com/v2/droplets?tag_name=k3s-master" | jq -c '.droplets[].networks.v4[] | select( .type == "public" )' | jq -r '.ip_address'`
  master_ip_priv=`curl -s -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $do_api_token" "https://api.digitalocean.com/v2/droplets?tag_name=k3s-master" | jq -c '.droplets[].networks.v4[] | select( .type == "private" )' | jq -r '.ip_address'`
}

sleep 15
until [[ $master_ip ]]
do
  echo "3a. Waiting for the IP Address get assigned to Master VM"
  get_master_ip > /dev/null
  sleep 2
done


master_ip=`curl -s -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $do_api_token" "https://api.digitalocean.com/v2/droplets?tag_name=k3s-master" | jq -c '.droplets[].networks.v4[] | select( .type == "public" )' | jq -r '.ip_address'`
master_ip_priv=`curl -s -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $do_api_token" "https://api.digitalocean.com/v2/droplets?tag_name=k3s-master" | jq -c '.droplets[].networks.v4[] | select( .type == "private" )' | jq -r '.ip_address'`
echo "3. Master node IP assigned: $master_ip"

sleep 10
until ssh -q -o "StrictHostKeyChecking=no" -o "ConnectTimeout=3" root@$master_ip 'hostname' > /dev/null
do
  echo "4. Waiting for the master node to be up and running..."
  sleep 3
done

# Uncomment below if you want to use CentOS based Droplets
#ssh -q -o "StrictHostKeyChecking=no" -t root@$master_ip 'echo "LANG=en_US.utf-8" > /etc/environment' > /dev/null 2>&1
#ssh -q -o "StrictHostKeyChecking=no" -t root@$master_ip 'echo "LC_ALL=en_US.utf-8" >> /etc/environment' > /dev/null 2>&1

echo "5. Install k3s on Master node"
ssh -q -o "StrictHostKeyChecking=no" -t root@$master_ip "curl -sfL https://get.k3s.io | sh -" > /dev/null

echo "6. Get token for joining nodes"
token=`ssh -q -o "StrictHostKeyChecking=no" -t root@$master_ip 'cat /var/lib/rancher/k3s/server/node-token'`

echo "7. Get Worker Nodes IP Addresses"
workers_ip=`curl -s -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $do_api_token" "https://api.digitalocean.com/v2/droplets?tag_name=k3s-workers" | jq -c '.droplets[].networks.v4[] | select( .type == "public" )' | jq -r '.ip_address'`
echo $workers_ip

echo "8. Install k3s on workers and join the cluster"
for worker in $workers_ip
do
  echo "8a. Deploying worker: $worker"
  ssh -q -o "StrictHostKeyChecking=no" root@$worker "curl -sfL https://get.k3s.io | sudo K3S_TOKEN=${token} K3S_URL=https://${master_ip_priv}:6443 sh -" > /dev/null 2>&1
done

echo "9. Downloading kubectl config..."
ssh -q -o "StrictHostKeyChecking=no" -t root@$master_ip "sudo cp /etc/rancher/k3s/k3s.yaml /root" > /dev/null
scp_command="root@$master_ip:/root/k3s.yaml ./k3s.yaml"
scp $scp_command >/dev/null
sed -i '' "s/127.0.0.1/$master_ip/g" ./k3s.yaml
if [ "$load_kube_config" = "true" ]
then
  echo "9a. Loading kubectl config..."
  mv ./k3s.yaml ~/.kube/config
fi


END_TIME=`date "+%s"`
echo "----- After $((${END_TIME} - ${START_TIME})) seconds - your cluster is ready :) -----"
