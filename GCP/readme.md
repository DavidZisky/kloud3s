## Google Cloud

This script will create 4 VMs (1 k3s master + 3 k3s workers) on Google Cloud, then will install and configure k3s cluster on them and will download kube config.

The script uses gcloud CLI so you need to have it installed and configured.

### Usage

1. Add your username (as in your ssh key on GCP) to the script (line 8)
2. Execute ./deploy.sh [cluster_name]
