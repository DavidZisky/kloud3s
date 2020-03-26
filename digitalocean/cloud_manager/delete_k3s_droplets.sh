#!/usr/bin/env bash

# Call for easy deletion of all droplets created for the cluster (deletes all droplets with tag "k3s")

curl -X DELETE -H "Content-Type: application/json" -H "Authorization: Bearer PUT_DO_TOKEN_HERE" "https://api.digitalocean.com/v2/droplets?tag_name=k3s"
