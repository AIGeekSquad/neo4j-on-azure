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
default_cluster_name="az-neo4j-cluster"
default_namespace="neo4j"

while getopts r:g:p:h flag
do
    case "${flag}" in
        r) region=${OPTARG};;
        g) resource_group=${OPTARG};;
        p) password=${OPTARG};;
        c) cluster_name=${OPTARG};;
        h) echo "Usage: $0 -r region -g resource group -p password -c cluster name -h help"; exit 1;;
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

if [[ -z $cluster_name ]]; then
    cluster_name=$default_cluster_name
    echo "Cluster Name is not provided. Using default cluster name: $cluster_name"
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

echo "Logging into Azure CLI via Device Code..."
az login --use-device-code

echo "Creating a new resource group... $resource_group"
az group create --name $resource_group --location $region

echo "Creating a new AKS cluster... $cluster_name. This may take a few minutes..."
az aks create --resource-group $resource_group --name $cluster_name --node-count 2 --generate-ssh-keys

echo "Getting credentials for the AKS cluster... $cluster_name"
az aks get-credentials -n $cluster_name -g $resource_group --admin --overwrite-existing 

echo "Verifying the context to the AKS cluster..."
#disk_id=$(az disk create --name "neo4j-volume-manual" --size-gb "10" --max-shares 1 --resource-group "${node_resource_group}" --location ${AZ_LOCATION} --output tsv --query id)

echo "Adding the Neo4j Helm repository..."
helm repo add neo4j https://helm.neo4j.com/neo4j

echo "Updating the Helm repository..."
helm repo update

# echo "Getting additional Neo4j plugins ..."
# mkdir -p neo4j-plugins
# cd neo4j-plugins
# curl -O https://github.com/neo4j-labs/neosemantics/releases/download/5.20.0/neosemantics-5.20.0.jar

echo "Creating a new namespace for Neo4j in cluster: $cluster_name ..."
kubectl create namespace $default_namespace

# helm upgrade --install $cluster_name neo4j/neo4j -n $default_namespace --set neo4j.password=$password --set data.storageClassName="dynamic" --set data.reclaimPolicy="Retain" -f aks-neo4j-values.yaml
helm install $cluster_name neo4j/neo4j -n $default_namespace --set neo4j.password=$password --version 5.20.0 -f neo4j-values.yaml 

echo "Waiting for the Neo4j pod to be ready; Please be patient..."
sleep 10s

# echo "Installing Neo4j plugins ..."
# neo4j_pod_name=$(kubectl get --no-headers=true pods -o name --namespace $default_namespace | awk -F "/" '{print $2}')
# echo "Neo4j pod name: $neo4j_pod_name"
# neo4j_statefulset_name=$(kubectl get --no-headers=true statefulset -o name --namespace $default_namespace| awk -F "/" '{print $2}')
# echo "Neo4j statefulset name: $neo4j_statefulset_name"
# kubectl cp neo4j-plugins/* $default_namespace/$neo4j_pod_name:/plugins/

# echo "Restarting the Neo4j statefulset/pod to load the plugins..."
# kubectl rollout restart statefulset/$neo4j_statefulset_name --namespace $default_namespace

echo "Completed Neo4j installation script..."

