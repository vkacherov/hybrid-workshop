# Join a Windows Server 2016 node 
# to Docker Universal Control Plane 

param (
  [Parameter(Mandatory = $True)][String]$Username,
  [Parameter(Mandatory = $True)][String]$Password,
  [Parameter(Mandatory = $True)][String]$UCP_FQDN,
  [string]$Engine_Version = "latest",
  [string]$UCP_Version = "latest"
)

function Check-Engine {

  Write-Output "Checking Engine Version"

  # Ensure installed engine is desired engine
  $Installed_Engine_Version=(docker version -f '{{.Server.Version}}')

  if($Engine_Version -eq $Installed_Engine_Version) {
    Write-Output "Installed engine version matches specified engine version"
  }
  else {

    Write-Output "Installed engine does not match specified engine version"
    Write-Output "Updating engine version"

    # Update PowerShell provider
    Stop-Service docker
    Install-Package -Name docker -ProviderName DockerMsftProvider -Update -Force -RequiredVersion $Engine_Version
    Restart-Service docker

    Write-Output "Updated engine version to $Engine_version"

  }

  # Check Swarm status
  Check-Swarm

}

function Check-Swarm {

  # Join node if not in a Swarm
  If ((docker info -f '{{.Swarm.LocalNodeState}}') -eq 'active') {
    Write-Output "Node is currently in a Swarm. Skipping join process"
    # Pre-Pull-Images
  }
  Else {
    Write-Output "Node is not currently in a Swarm. Joining to Swarm at $UCP_FQDN"
    Join-Swarm
  }

}

function Prepare-Node {

  # Pre-Pull necessary UCP images
  docker image pull docker/ucp-agent-win:$UCP_Version
  docker image pull docker/ucp-dsinfo-win:$UCP_Version

  # Run Windows node setup script to open firewall and securely connect to Docker engine
  $script = [ScriptBlock]::Create((docker run --rm docker/ucp-agent-win:$UCP_Version windows-script | Out-String))
  Invoke-Command $script

}

function Join-Swarm {

  Prepare-Node

  # Allow queries against self-signed certificates in UCP
  [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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
    # Pre-Pull-Images
  }
  Catch {
    Write-Error "Unable to join node to Swarm"
    Exit 1
  }

}

function Pre-Pull-Images {

  # Pre-Pull images used in the lab
  docker pull microsoft/iis:latest
  docker pull microsoft/aspnetcore-build:latest
  docker pull microsoft/aspnetcore:latest

}

function Main {
  Restart-Service docker
  Check-Engine
}

Main