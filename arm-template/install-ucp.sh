#!/bin/sh
#
# Install Docker Universal Control Plane on Ubuntu

# UCP URL
readonly UCP_FQDN=$1

# External Service Load Balancer URL
readonly APPS_LB_FQDN=$2

# Is node a worker or manager?
readonly NODE_ROLE=$3

# Version of UCP to be installed
readonly UCP_VERSION=$4

# CIDR Range of Subnet containing nodes
readonly SUBNET_IP_RANGE=$5

# Name of current node
readonly NODE_NAME=$(cat /etc/hostname)

# UCP Administrator Credentials
readonly UCP_ADMIN="eeadmin"
readonly UCP_PASSWORD="DockerEE123!"

# Install jq library for parsing JSON
sudo apt-get -qq install jq -y

checkUCP() {

    # Check if UCP exists by attempting to hit its load balancer
    STATUS=$(curl --request GET --url "https://${UCP_FQDN}/_ping" --insecure --silent --output /dev/null -w '%{http_code}' --max-time 5)
    
    echo "checkUCP: API status for ${UCP_FQDN} returned as: ${STATUS}"

    if [ "$STATUS" -eq 200 ]; then
        echo "checkUCP: Successfully queried the UCP API. UCP is installed. Joining node to existing cluster."
        joinUCP
    else
        echo "checkUCP: Failed to query the UCP API. UCP is not installed. Installing UCP."
        installUCP
    fi

}

installUCP() {
    
    # Initialize a Swarm
    docker swarm init

    # Generate certificates for use with UCP
    letsencrypt

    echo "installUCP: Installing Docker Universal Control Plane (UCP)"
    echo "installUCP: Subnet CIDR is ${SUBNET_IP_RANGE}"

    # Install Universal Control Plane
    # https://docs.docker.com/ee/ucp/admin/install/install-on-azure/
    docker run \
        --rm \
        --name ucp \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        docker/ucp:"${UCP_VERSION}" install \
        --admin-username "${UCP_ADMIN}" \
        --admin-password "${UCP_PASSWORD}" \
        --cloud-provider Azure \
        --san "${UCP_FQDN}" \
        --pod-cidr "${SUBNET_IP_RANGE}" \
        --external-server-cert \
        --external-service-lb "${APPS_LB_FQDN}"

    # Wait for node to reach a ready state
    until [ $(curl --request GET --url "https://${UCP_FQDN}/_ping" --insecure --silent --header 'Accept: application/json' | grep OK) ]
    do
        echo '...created cluster, waiting for a ready state'
        sleep 5
    done

    echo "installUCP: Cluster's healthcheck returned a ready state"
    echo "installUCP: Finished installing Docker Universal Control Plane (UCP)"

}

joinUCP() {

    # Get Authentication Token
    AUTH_TOKEN=$(curl --request POST --url "https://${UCP_FQDN}/auth/login" --insecure --silent --header 'Accept: application/json' --data '{ "username": "'${UCP_ADMIN}'", "password": "'${UCP_PASSWORD}'" }' | jq --raw-output .auth_token)

    # Get Swarm Manager IP Address + Port
    UCP_MANAGER_ADDRESS=$(curl --request GET --url "https://${UCP_FQDN}/info" --insecure --silent --header 'Accept: application/json' --header "Authorization: Bearer ${AUTH_TOKEN}" | jq --raw-output .Swarm.RemoteManagers[0].Addr)
    
    # Get Swarm Join Tokens
    UCP_JOIN_TOKENS=$(curl --request GET --url "https://${UCP_FQDN}/swarm" --insecure --silent --header 'Accept: application/json' --header "Authorization: Bearer ${AUTH_TOKEN}" | jq .JoinTokens)
    UCP_JOIN_TOKEN_MANAGER=$(echo "${UCP_JOIN_TOKENS}" | jq --raw-output .Manager)
    UCP_JOIN_TOKEN_WORKER=$(echo "${UCP_JOIN_TOKENS}" | jq --raw-output .Worker)

    # Join Swarm
    if [ "$NODE_ROLE" = "Manager" ]
    then
        echo "joinUCP: Joining Swarm as a Manager"
        docker swarm join --token "${UCP_JOIN_TOKEN_MANAGER}" "${UCP_MANAGER_ADDRESS}"
    else
        echo "joinUCP: Joining Swarm as a Worker"
        docker swarm join --token "${UCP_JOIN_TOKEN_WORKER}" "${UCP_MANAGER_ADDRESS}"
    fi

    # Wait for node to reach a ready state
    while [ "$(curl --request GET --url "https://${UCP_FQDN}/nodes/${NODE_NAME}" --insecure --silent --header 'Accept: application/json' --header "Authorization: Bearer ${AUTH_TOKEN}" | jq --raw-output .Status.State)" != "ready" ]
    do
        echo '...node joined, waiting for a ready state'
        sleep 5
    done

    echo "joinUCP: Finished joining node to UCP"

}

letsencrypt() {

    echo "letsencrypt: beginning generation of certificates for ${UCP_FQDN}"

    # Certbot stands up a webserver to connect with letsencrypt
    # However it does not stay up long enough for the Azure LB Probe to detect it and route traffic
    # To get the LB working we'll start a webserver for a time, then exit and run the certbot
    docker run --detach --publish 80:80 --publish 443:443 --name lb_bait nginx:alpine
    sleep 20
    docker rm -f lb_bait

    # Generate certificate with certbot
    docker run \
    --rm \
    --publish 443:443 \
    --publish 80:80 \
    --name letsencrypt \
    --volume "/etc/letsencrypt:/etc/letsencrypt" \
    --volume "/var/lib/letsencrypt:/var/lib/letsencrypt" \
    certbot/certbot:latest \
    certonly \
    --agree-tos \
    --domains "${UCP_FQDN}" \
    --noninteractive \
    --preferred-challenges http \
    --register-unsafely-without-email \
    --standalone 

    # Make a volume and copy in certificates 
    docker volume create ucp-controller-server-certs
    cp /etc/letsencrypt/live/"${UCP_FQDN}"/fullchain.pem /var/lib/docker/volumes/ucp-controller-server-certs/_data/cert.pem
    cp /etc/letsencrypt/live/"${UCP_FQDN}"/privkey.pem /var/lib/docker/volumes/ucp-controller-server-certs/_data/key.pem
    curl -o /var/lib/docker/volumes/ucp-controller-server-certs/_data/ca.pem https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt

    echo "letsencrypt: finished generating certificates"

}

main() {
  checkUCP
}

main