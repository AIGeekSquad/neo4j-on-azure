$ErrorActionPreference = 'SilentlyContinue'
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

$azrmInstall = Get-Module -Name AzureRM -ListAvailable
$chocoInstall = choco -v
$helmInstall = helm version --short

function Test-HelmInstall {

 $result =""
# Check if Helm is installed
    try {
        $helmVersion = Get-Command helm | Invoke-Expression
        if ($helmVersion -match "Version:") {
            Write-Host "Helm is installed and accessible."
            Write-Host "Version: $($helmVersion)"
            $result=$true
        } else {
            Write-Host="Helm is not installed or not accessible."
            $result=$false
        }
    }
    catch {
         Write-Host="Helm is not installed or not accessible."
         $result=$false
    }

    return $result

}


if ([string]::IsNullOrEmpty($chocoInstall)){
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

$isHelmInstalled = Test-HelmInstall
if ($isHelmInstalled -eq $false){
    choco install kubernetes-helm
}

Install-Module -Name Az -Repository PSGallery -Force
Update-Module -Name Az -Force

Connect-AzAccount

$ErrorActionPreference = 'Continue'
