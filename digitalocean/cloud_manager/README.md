# k3sDOCCM
K3S + DO Cloud Manager

PROPER README COMING SOON...

Script which creates 4 droplets on DigitalOcean, installs k3s cluster on them (1 master + 3 workers), installs DigitalOcean Cloud Controller Manager (in order to automatically spin up a DO LoadBalancer when you create service type LoadBalancer), installs ExternalDNS (in order to automatically create DNS entries when specified in ingress - your domain MUST be hosted on DigitalOcean), installs Cert-manager (in order to automatically request certificate for ingress, uses DNS challenge which is also done automatically via ExternalDNS).

REQUIREMENTS:

1. Add your email on line 10 in dns-issuer.yaml file
2. Add SSH fingerprints (From "security" menu on digitalocean) in droplet_master and droplets_workers JSON files
3. Add your DigitalOcean api token on line 7 in externaldns-values.yaml file
4. Add your DigitalOcean api token on line 7 in k3s_deployer_cloudmanag.sh file
5. Add your DigitalOcean api token on line 7 in dotoken.yaml file
6. OPTIONALLY: Put your domain on line 44 in example_deployment.yaml (if you want to use it)


USAGE:

1. Make sure You fill requirements above
2. Simply execute ./k3s_deployer_cloudmanag.sh
3. After ~3 minutes your cluster is ready and kubectl config is loaded into your system - you can start using it :)
4. If you deploy now any deployment with service and ingress, the DNS entries and SSL certificate are being created automatically and after few minutes your application is available under specified in ingress dns name and with https:// use example_deployment.yaml for reference how to create proper ingress

So workflow looks like this:

1. ./k3s_deployer_cloudmanag.sh
2. kubectl apply -f example_deployment.yaml
3. Go to browser and open https://nginx.yourdomain.com
