#!/bin/bash

is_helm_installed() {
    # Run the command to check if Helm is installed
    helm version > /dev/null 2>&1

    # If the command returns 0, Helm is installed
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

is_azurecli_installed() {
    # Run the command to check if Azure CLI is installed
    az version > /dev/null 2>&1
    
    # If the command returns 0, Azure CLI is installed
    if [ $? -eq 0 ]; then
        echo "Azure CLI is $?"
        return 0
    else
        return 1
    fi
}

is_kubectl_installed() {
    kubectl version --client > /dev/null 2>&1

     # If the command returns 0, Kubectl is installed
    if [ $? -eq 0 ]; then
        echo "Kubectl is $?"
        return 0
    else
        return 1
    fi
}

# Deploy an AKS cluster
echo "Name of the script: $0"
echo "Total number of arguments: $#"
echo "Values of all the arguments: $@"

default_region="eastus2"
default_resource_group="neo4j-aks-rg"
default_password="aksneo4j"
cluster_name="az-neo4j-cluster"

while getopts r:g:p:h flag
do
    case "${flag}" in
        r) region=${OPTARG};;
        g) resource_group=${OPTARG};;
        p) password=${OPTARG};;
        h) echo "Usage: $0 -r region -g resource_group -p password -h help"; exit 1;;
    esac
done


echo "Region: $region";
echo "Resource Group: $resource_group";
echo "Password: $password";
random_id="$(openssl rand -hex 3)"
echo "Random ID: $random_id"

if [[ -z $resource_group ]]; then
    resource_group=$default_resource_group
    echo "Resource Group is not provided. Using default resource group: $resource_group"
fi

if [[ -z $region ]]; then
    region=$default_region
    echo "Region is not provided. Using default region: $region"
fi

if [[ -z $password ]]; then
    password=$default_password
    echo "Password is not provided. Using default region: $password"
fi

if ! is_helm_installed; then
    echo "Helm is not installed. Installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
fi


if ! is_azurecli_installed; then
    echo "Azure CLI is not installed. Installing Azure CLI..."
    curl -L https://aka.ms/InstallAzureCli | bash
fi

if ! is_kubectl_installed; then
    echo "Kubectl is not installed. Installing Kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
else
    echo "Kubectl is already installed"
fi

az login --use-device-code

az group create --name $resource_group --location $region

az aks create --resource-group $resource_group --name $cluster_name --node-count 2 --generate-ssh-keys

az aks get-credentials -n $cluster_name -g $resource_group --admin

#disk_id=$(az disk create --name "neo4j-volume-manual" --size-gb "10" --max-shares 1 --resource-group "${node_resource_group}" --location ${AZ_LOCATION} --output tsv --query id)

helm repo add neo4j https://helm.neo4j.com/neo4j

helm repo update

kubectl create namespace neo4j

helm upgrade --install $cluster_name neo4j -n neo4j --set neo4j.password=$password --set data.reclaimPolicy="Retain" -f aks-neo4j-values.yaml