#!/bin/bash
#
# Install Docker Enterprise Edition Engine on Ubuntu

# Store license URL
readonly DOCKER_EE_URL=$1

# UCP URL
readonly UCP_URL=$2

# Repository name for Docker EE Engine
readonly DOCKER_EE_VERSION="test"

# Version of UCP to be installed
readonly UCP_VERSION="3.0.0-beta3"

# Version of DTR to be installed
readonly DTR_VERSION="2.5.0-beta3"

# CIDR of the subnet containing cluster nodes
readonly AZURE_SUBNET_CIDR="10.0.0.0/24"

configure_swarm() {

  # Initiate a Docker Swarm
  docker swarm init

  # Create secret from toml file
  docker secret create azure_ucp_admin.toml "./azure_ucp_admin.toml"

  # Use secret in a service to prepopulate VMs with IPs
  docker service create \
    --mode=global \
    --secret=azure_ucp_admin.toml \
    --log-driver json-file \
    --log-opt max-size=1m \
    --name ipallocator \
    ddebroy/azip

}

installUCP() {
    
    echo "Installing Docker Universal Control Plane (UCP)"

    # Install Universal Control Plane
    # Uses port 8080 to avoid conflict with DTR
    docker run \
        --rm \
        --name ucp \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        docker/ucp:"${UCP_VERSION}" install \
        --admin-username "admin" \
        --admin-password "Docker123!" \
        --san "${UCP_URL}" 
        #--cloud-provider Azure \
        #--pod-cidr "${AZURE_SUBNET_CIDR}"

    echo "Finished installing Docker Universal Control Plane (UCP)"

}

main() {
  #configure_swarm
  installUCP
}

main