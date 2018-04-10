#!/bin/sh
#
# Install Docker Trusted Registry on Ubuntu

# UCP URL
readonly UCP_FQDN=$1

# DTR URL
readonly DTR_FQDN=$2

# Node to install DTR on
readonly UCP_NODE=$(cat /etc/hostname)

# Version of DTR to be installed
readonly DTR_VERSION="2.5.0-beta3"

# UCP Admin credentials
readonly UCP_USERNAME="admin"
readonly UCP_PASSWORD='Docker123!'

checkDTR() {

    # Check if UCP exists by attempting to hit its load balancer
    STATUS=$(curl --request GET --url "https://${DTR_FQDN}/_ping" --insecure --silent --output /dev/null -w '%{http_code}' --max-time 5)
    
    if [ "$STATUS" -eq 200 ]; then
        echo "checkDTR: Successfully queried the DTR API. DTR is installed. Joining node to existing cluster."
        joinDTR
    else
        echo "checkDTR: Failed to query the DTR API. DTR is not installed. Installing DTR."
        installDTR
    fi

}

installDTR() {

    echo "installDTR: Installing Docker Trusted Registry (DTR)"

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

    # Join an existing Docker Trusted Registry
    docker run \
        --rm \
        docker/dtr:${DTR_VERSION} join \
        --existing-replica-id "${REPLICA_ID}" \
        --ucp-url "https://${UCP_FQDN}" \
        --ucp-node "${UCP_NODE}" \
        --ucp-username "${UCP_USERNAME}" \
        --ucp-password "${UCP_PASSWORD}" \
        --ucp-insecure-tls 

}

main() {
  checkDTR
}

main