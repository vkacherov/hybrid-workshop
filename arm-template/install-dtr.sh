#!/bin/sh
#
# Install Docker Trusted Registry on Ubuntu

# UCP URL
readonly UCP_FQDN=$1

# DTR URL
readonly DTR_FQDN=$2

# Version of DTR to be installed
readonly DTR_VERSION=$3

# Node to configure DTR (current)
readonly UCP_NODE=$(cat /etc/hostname)

# UCP Admin credentials
readonly UCP_USERNAME="eeadmin"
readonly UCP_PASSWORD='DockerEE123!'

checkDTR() {

    # Generate certificates for use with UCP
    # letsencrypt

    # Check if DTR exists by attempting to hit its load balancer
    STATUS=$(curl --request GET --url "https://${DTR_FQDN}/_ping" --insecure --silent --output /dev/null -w '%{http_code}' --max-time 5)
    
    echo "checkDTR: API status for ${DTR_FQDN} returned as: ${STATUS}"
    
    if [ "$STATUS" -eq 200 ]; then
        echo "checkDTR: Successfully queried the DTR API. DTR is installed. Joining node to existing cluster."
        joinDTR
    else
        echo "checkDTR: Failed to query the DTR API. DTR is not installed. Installing DTR."
        installDTR
    fi

}

installDTR() {

    echo "installDTR: Installing ${DTR_VERSION} Docker Trusted Registry (DTR) on ${UCP_NODE} for UCP at ${UCP_FQDN} and with a DTR Load Balancer at ${DTR_FQDN}"

    # Pre-Pull Images
    docker run --rm docker/dtr:"${DTR_VERSION}" images | xargs -L 1 docker pull

    # Install Docker Trusted Registry
    docker run \
        --rm \
        docker/dtr:${DTR_VERSION} install \
        --dtr-external-url "https://${DTR_FQDN}" \
        --ucp-url "https://${UCP_FQDN}" \
        --ucp-node "${UCP_NODE}" \
        --ucp-username "${UCP_USERNAME}" \
        --ucp-password "${UCP_PASSWORD}" \
        --ucp-insecure-tls 

    echo "installDTR: Finished installing Docker Trusted Registry (DTR)"

}

joinDTR() {

    # Get DTR Replica ID
    REPLICA_ID=$(curl --request GET --insecure --silent --url "https://${DTR_FQDN}/api/v0/meta/settings" -u "${UCP_USERNAME}":"${UCP_PASSWORD}" --header 'Accept: application/json' | jq --raw-output .replicaID)
    
    echo "joinDTR: Joining DTR with Replica ID ${REPLICA_ID}"

    # Pre-Pull Images
    docker run --rm docker/dtr:"${DTR_VERSION}" images | xargs -L 1 docker pull

    # Join an existing Docker Trusted Registry
    docker run \
        --rm \
        docker/dtr:${DTR_VERSION} join \
        --existing-replica-id "${REPLICA_ID}" \
        --ucp-insecure-tls \
        --ucp-node "${UCP_NODE}" \
        --ucp-password "${UCP_PASSWORD}" \
        --ucp-url "https://${UCP_FQDN}" \
        --ucp-username "${UCP_USERNAME}" 

}

letsencrypt() {

    echo "letsencrypt: beginning generation of certificates"

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
    -d "${UCP_FQDN}" \
    -n \
    --register-unsafely-without-email \
    --standalone \

    # Wait for letsencrypt to finish before proceeding
    docker wait letsencrypt

    # Make a volume and copy in certificates 
    docker volume create ucp-controller-server-certs
    cp /etc/letsencrypt/live/"${UCP_FQDN}"/fullchain.pem /var/lib/docker/volumes/ucp-controller-server-certs/_data/cert.pem
    cp /etc/letsencrypt/live/"${UCP_FQDN}"/privkey.pem /var/lib/docker/volumes/ucp-controller-server-certs/_data/key.pem
    curl -o /var/lib/docker/volumes/ucp-controller-server-certs/_data/ca.pem https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt

    echo "letsencrypt: finished generating certificates"

}

main() {
  checkDTR
}

main