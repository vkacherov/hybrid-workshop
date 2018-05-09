#!/bin/sh
#
# Install Docker Trusted Registry on Ubuntu

# UCP URL
readonly UCP_FQDN=$1

# DTR URL
readonly DTR_FQDN=$2

# Version of DTR to be installed
readonly DTR_VERSION=$3

# Azure Storage Account Credentials
readonly AZURE_STORAGE_ACCOUNT=$4
readonly AZURE_STORAGE_KEY=$5

# Node to configure DTR (current)
readonly UCP_NODE=$(cat /etc/hostname)

# UCP Admin credentials
readonly UCP_USERNAME='eeadmin'
readonly UCP_PASSWORD='DockerEE123!'

# Set a Replica ID 
readonly REPLICA_ID='012345678910'

checkDTR() {

    # Check if DTR exists by attempting to hit its load balancer
    STATUS=$(curl --request GET --url "https://${DTR_FQDN}/_ping" --insecure --silent --output /dev/null -w '%{http_code}' --max-time 5)
    
    echo "checkDTR: API status for ${DTR_FQDN} returned as ${STATUS}"
    
    if [ "$STATUS" -eq 200 ]; then
        echo "checkDTR: Successfully queried the DTR API. DTR is installed. Joining node to existing cluster."
        joinDTR
    else
        echo "checkDTR: Failed to query the DTR API. DTR is not installed. Installing DTR."
        installDTR
    fi

}

installDTR() {

    # Generate certificates for use with DTR
    letsencrypt

    echo "installDTR: Installing ${DTR_VERSION} Docker Trusted Registry (DTR) on ${UCP_NODE} for UCP at ${UCP_FQDN} and with a DTR Load Balancer at ${DTR_FQDN}"

    # Install Docker Trusted Registry
    docker run \
        --rm \
        docker/dtr:"${DTR_VERSION}" install \
        --dtr-ca "$(cat /etc/letsencrypt/live/"${DTR_FQDN}"/ca.pem)" \
        --dtr-cert "$(cat /etc/letsencrypt/live/"${DTR_FQDN}"/fullchain.pem)" \
        --dtr-key "$(cat /etc/letsencrypt/live/"${DTR_FQDN}"/privkey.pem)" \
        --dtr-external-url "https://${DTR_FQDN}" \
        --replica-id "${REPLICA_ID}" \
        --ucp-url "https://${UCP_FQDN}" \
        --ucp-node "${UCP_NODE}" \
        --ucp-username "${UCP_USERNAME}" \
        --ucp-password "${UCP_PASSWORD}"

    # Configure Azure Storage
    configureStorage

    echo "installDTR: Finished installing Docker Trusted Registry (DTR)"

}

joinDTR() {
    
    echo "joinDTR: Joining DTR with Replica ID ${REPLICA_ID}"

    # Join an existing Docker Trusted Registry
    docker run \
        --rm \
        docker/dtr:"${DTR_VERSION}" join \
        --existing-replica-id "${REPLICA_ID}" \
        --ucp-insecure-tls \
        --ucp-node "${UCP_NODE}" \
        --ucp-password "${UCP_PASSWORD}" \
        --ucp-url "https://${UCP_FQDN}" \
        --ucp-username "${UCP_USERNAME}" 

}

letsencrypt() {

    echo "letsencrypt: beginning generation of certificates ${DTR_FQDN}"

    # Pre-Pull Images
    docker pull nginx/alpine:latest
    docker pull certbot/certbot:latest

    # Certbot stands up a webserver to connect with letsencrypt
    # However it does not stay up long enough for the Azure LB Probe to detect it and route traffic
    # To get the LB working we'll start a webserver for a time, then exit and run the certbot
    docker run --detach --publish 80:80 --publish 443:443 --name lb_bait nginx:alpine
    sleep 20
    docker rm -f lb_bait
    docker rmi nginx/alpine:latest certbot/cerbot:latest

    while [ ! -f /etc/letsencrypt/live/"${DTR_FQDN}"/fullchain.pem ]
    do
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
        --domains "${DTR_FQDN}" \
        --noninteractive \
        --preferred-challenges http \
        --register-unsafely-without-email \
        --standalone
        
        sleep 3
    done

    # Store letsencrypt CA 
    curl -o /etc/letsencrypt/live/"${DTR_FQDN}"/ca.pem https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt

    echo "letsencrypt: finished generating certificates"

}

configureStorage() {

    echo "Configuring DTR Storage with Azure"

    # Configure DTR to use Azure Storage for its backend
    curl --request PUT \
    --url "https://${DTR_FQDN}/api/v0/admin/settings/registry/simple" \
    -u "${UCP_USERNAME}:${UCP_PASSWORD}" \
    --header 'accept: application/json' \
    --header 'content-type: application/json' \
    --data "{
        \"storage\": {
            \"azure\": {
                \"accountkey\": \"${AZURE_STORAGE_KEY}\",
                \"accountname\": \"${AZURE_STORAGE_ACCOUNT}\",
                \"container\": \"dtrstorage\",
                \"realm\": \"core.windows.net\"
            },
            \"delete\": {
                \"enabled\": true
            },
            \"maintenance\": {
                \"readonly\": {
                    \"enabled\": false
                }
            }
        }
    }"

}

main() {
  checkDTR
}

main