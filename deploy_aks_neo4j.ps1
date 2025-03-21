param(
    [string]$Region = "eastus2",
    [string]$ResourceGroup = "neo4j-aks-rg",
    [string]$Password = "aksneo4j",
    [string]$Clu     = "az-neo4j-cluster",
    [string]$Namespace = "neo4j"
)

$ErrorActionPreference = 'SilentlyContinue'
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Function to test if a command exists
function Test-CommandExists {
    param ($Command)
    
    try {
        if (Get-Command $Command -ErrorAction Stop) {
            return $true
        }
    }
    catch {
        return $false
    }
    return $false
}

# Function to test Helm installation
function Test-HelmInstall {
    try {
        $helmVersion = helm version --short
        if ($helmVersion) {
            Write-Host "Helm is installed and accessible."
            Write-Host "Version: $helmVersion"
            return $true
        }
    }
    catch {
        Write-Host "Helm is not installed or not accessible."
        return $false
    }
    return $false
}

# Function to test Azure CLI installation
function Test-AzureCliInstall {
    try {
        $azVersion = az version
        if ($azVersion) {
            Write-Host "Azure CLI is installed and accessible."
            return $true
        }
    }
    catch {
        Write-Host "Azure CLI is not installed or not accessible."
        return $false
    }
    return $false
}

# Function to test kubectl installation
function Test-KubectlInstall {
    try {
        $kubectlVersion = kubectl version --client
        if ($kubectlVersion) {
            Write-Host "kubectl is installed and accessible."
            return $true
        }
    }
    catch {
        Write-Host "kubectl is not installed or not accessible."
        return $false
    }
    return $false
}

Write-Host "Checking prerequisites..."

# Check and install Chocolatey if needed
$chocoInstall = Test-CommandExists choco
if (-not $chocoInstall) {
    Write-Host "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    refreshenv
}

# Check and install Helm if needed
$isHelmInstalled = Test-HelmInstall
if (-not $isHelmInstalled) {
    Write-Host "Installing Helm..."
    choco install kubernetes-helm -y
    refreshenv
}

# Check and install Azure CLI if needed
$isAzureCliInstalled = Test-AzureCliInstall
if (-not $isAzureCliInstalled) {
    Write-Host "Installing Azure CLI..."
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
    Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
    Remove-Item .\AzureCLI.msi
    refreshenv
}

# Check and install kubectl if needed
$isKubectlInstalled = Test-KubectlInstall
if (-not $isKubectlInstalled) {
    Write-Host "Installing kubectl..."
    choco install kubernetes-cli -y
    refreshenv
}

# Install and update Az PowerShell module
Write-Host "Installing/Updating Az PowerShell module..."
if (-not (Get-Module -ListAvailable -Name Az)) {
    Install-Module -Name Az -Repository PSGallery -Force
}
Update-Module -Name Az -Force

# Connect to Azure
Write-Host "Logging into Azure..."
Connect-AzAccount

# Create resource group
Write-Host "Creating resource group: $ResourceGroup"
New-AzResourceGroup -Name $ResourceGroup -Location $Region -Force

# Create AKS cluster
Write-Host "Creating AKS cluster: $ClusterName (this may take several minutes)..."
New-AzAksCluster -ResourceGroupName $ResourceGroup -Name $ClusterName -NodeCount 2 -GenerateSshKey

# Get AKS credentials
Write-Host "Getting AKS credentials..."
Import-AzAksCredential -ResourceGroupName $ResourceGroup -Name $ClusterName -Force

# Add Neo4j Helm repository
Write-Host "Adding Neo4j Helm repository..."
helm repo add neo4j https://helm.neo4j.com/neo4j
helm repo update

# Create namespace
Write-Host "Creating namespace: $Namespace"
kubectl create namespace $Namespace

# Deploy Neo4j using Helm
Write-Host "Deploying Neo4j..."
helm install $ClusterName neo4j/neo4j `
    --namespace $Namespace `
    --set neo4j.password=$Password `
    --version 5.20.0 `
    -f neo4j-values.yaml

Write-Host "Waiting for Neo4j pod to be ready..."
Start-Sleep -Seconds 10

# Optional: Install plugins
$InstallPlugins = $false
if ($InstallPlugins) {
    Write-Host "Installing Neo4j plugins..."
    
    # Create plugins directory if it doesn't exist
    if (-not (Test-Path "neo4j-plugins")) {
        New-Item -ItemType Directory -Path "neo4j-plugins" -Force
    }
    
    # Get pod and statefulset names
    $Neo4jPodName = (kubectl get pods -n $Namespace -l "app.kubernetes.io/name=neo4j" -o name) -replace "pod/"
    $Neo4jStatefulSetName = (kubectl get statefulset -n $Namespace -l "app.kubernetes.io/name=neo4j" -o name) -replace "statefulset/"
    
    # Copy plugins
    Get-ChildItem "neo4j-plugins" | ForEach-Object {
        kubectl cp $_.FullName -n $Namespace "${Neo4jPodName}:/plugins/"
    }
    
    # Restart the pod to load plugins
    kubectl rollout restart statefulset/$Neo4jStatefulSetName -n $Namespace
}

Write-Host "Neo4j deployment completed successfully!"
$ErrorActionPreference = 'Continue'
