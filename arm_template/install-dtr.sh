#!/bin/bash
#
# Install Docker Enterprise Edition Engine on Ubuntu

# UCP URL
readonly UCP_URL=$1

# DTR URL
readonly DTR_URL=$2

# Version of DTR to be installed
readonly DTR_VERSION="2.5.0-beta3"

# UCP Admin credentials
readonly UCP_USERNAME="admin"
readonly UCP_PASSWORD="Docker123!"

installDTR() {

    echo "Installing Docker Trusted Registry (DTR)"

    # Install Docker Trusted Registry
    # Uses port 443 for ease of pulls/pushes
    docker run \
        --rm \
        docker/dtr:latest install \
        --dtr-external-url "${DTR_URL}" \
        --ucp-node dtr01 \
        --ucp-username "${UCP_USERNAME}" \
        --ucp-password "${UCP_PASSWORD}}" \
        --ucp-url "${UCP_URL}":8080 \
        --ucp-insecure-tls 

    echo "Finished installing Docker Trusted Registry (DTR)"

}

main() {
  installDTR
}

main