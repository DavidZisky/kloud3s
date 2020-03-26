# k3sDOCCM
K3S + DO Cloud Manager

PROPER README COMING SOON...

Script which creates 4 droplets on DigitalOcean, installs k3s cluster on them (1 master + 3 workers), installs DigitalOcean Cloud Controller Manager (in order to automatically spin up a DO LoadBalancer when you create service type LoadBalancer), installs ExternalDNS (in order to automatically create DNS entries when specified in ingress - your domain MUST be hosted on DigitalOcean), installs Cert-manager (in order to automatically request certificate for ingress, uses DNS challenge which is also done automatically via ExternalDNS).

REQUIREMENTS:

0. Make sure you have Helm3 and jq installed
1. Add your email, DigitalOcean API Token and SSH Key fingerprint in .env file
2. OPTIONALLY: Put your domain on line 44 in example_deployment.yaml (if you want to use it)


USAGE:

1. Make sure You fill requirements above
2. Simply execute ./k3s_deployer_cloudmanag.sh
3. After ~3-5 minutes your cluster is ready and kubectl config is loaded into your system - you can start using it :)
4. If you deploy now a k8s deployment with service and ingress, the DNS entries and SSL certificate are being created automatically and after few minutes your application is available under specified in ingress dns name and with https:// use example_deployment.yaml for reference how to create proper ingress

So workflow looks like this:

1. ./k3s_deployer_cloudmanag.sh
2. kubectl apply -f example_deployment.yaml
3. Go to browser and open https://nginx.yourdomain.com
