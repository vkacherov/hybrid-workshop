# Join a Windows Server 2016 node 
# to Docker Universal Control Plane 

param (
  [Parameter(Mandatory = $True)][String]$Username,
  [Parameter(Mandatory = $True)][String]$Password,
  [Parameter(Mandatory = $True)][String]$UCP_FQDN,
  [string]$UCP_Version = "latest"
)

# Join node if not in a Swarm
If ((docker info -f '{{.Swarm.LocalNodeState}}') -eq 'active') {
  Write-Output "Node is currently in a Swarm. Skipping join process"
}
Else {
  Write-Output "Node is not currently in a Swarm. Joining to Swarm at $UCP_FQDN"

  # Setup node to work with UCP
  docker image pull docker/ucp-agent-win:$UCP_Version
  docker image pull docker/ucp-dsinfo-win:$UCP_Version
  $script = [ScriptBlock]::Create((docker run --rm docker/ucp-agent-win:$UCP_Version windows-script | Out-String))
  Invoke-Command $script

  # Allow queries against self-signed certificates in UCP
  [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

  # Get Authentication Token
  Try {
    $AUTH_TOKEN = (Invoke-RestMethod `
        -Uri "https://$UCP_FQDN/auth/login" `
        -Body "{`"username`":`"$Username`",`"password`":`"$Password`"}" `
        -Method POST).auth_token
    
    Write-Output "Successfully retrieved Authentication Token"
  }
  Catch {
    Write-Error "Failed to get Authentication Token"
    Exit 1
  }

  # Get Swarm Manager IP Address + Port
  Try {
    $UCP_MANAGER_ADDRESS = (Invoke-RestMethod `
        -Method GET `
        -Uri "https://$UCP_FQDN/info" `
        -Headers @{"Accept" = "application/json"; "Authorization" = "Bearer $AUTH_TOKEN"}).Swarm.RemoteManagers[0].Addr

    Write-Output "Successfully retrieved Swarm Manager IP and Port"
  }
  Catch {
    Write-Error "Failed to get Swarm Manager IP and Port"
    Exit 1
  }

  # Get Swarm Join Tokens
  Try {
    $UCP_JOIN_TOKEN_WORKER = (Invoke-RestMethod `
        -Method GET `
        -Uri "https://$UCP_FQDN/swarm" `
        -Headers @{"Accept" = "application/json"; "Authorization" = "Bearer $AUTH_TOKEN"}).JoinTokens.Worker

    Write-Output "Successfully retrieved Swarm Worker Join Token"
  }
  Catch {
    Write-Error "Failed to get Swarm Worker Join Token"
    Exit 1
  }

  # Join Swarm
  Try {
    docker swarm join --token $UCP_JOIN_TOKEN_WORKER $UCP_MANAGER_ADDRESS
  }
  Catch {
    Write-Error "Unable to join node to Swarm"
    Exit 1
  }

}

# Pre-Pull images used in the lab
docker pull microsoft/iis:latest
docker pull microsoft/aspnetcore-build:latest
docker pull microsoft/aspnetcore:latest

