import sys
import subprocess
import os
import shutil
import json
import time

def main(resource_group: str):
    if not resource_group:
        print("Error: Please provide a resource group name.")
        sys.exit(1)

    az_executable = shutil.which("az")
    if not az_executable:
        print("Error: 'az' command not found. Please make sure Azure CLI is installed and in your PATH.")
        sys.exit(1)

    # Create a resource group
    print(f"Creating resource group '{resource_group}'...")
    subprocess.run([az_executable, "group", "create", "--name", resource_group, "--location", "eastus"])

    # Create an SSH key
    print(f"Creating SSH key 'neo4jSSHKey' in resource group '{resource_group}'...")
    sshkey_output = subprocess.check_output([az_executable, "sshkey", "create", "--name", "neo4jSSHKey", "--resource-group", resource_group]).decode("utf-8")
    print("Copy the key below for use in the next step:")
    print("SSH public key:", json.loads(sshkey_output)["publicKey"])

    # Deploy AKS cluster using the ARM template
    print("Deploying AKS cluster for neo4j...")
    arm_template_url = "https://raw.githubusercontent.com/AIGeekSquad/neo4j-on-azure/main/Azure-Kubernetes-Svc/aks-arm-deploy.json"
    subprocess.run([az_executable, "deployment", "group", "create", "--resource-group", resource_group, "--template-uri", arm_template_url])

    # Get AKS credentials
    print("Getting AKS credentials...")
    subprocess.run([az_executable, "aks", "get-credentials", "--resource-group", resource_group, "--name", "azneo4jcluster"])

    # Verify access to the cluster
    print("Verifying access to the AKS cluster...")
    subprocess.run(["kubectl", "get", "nodes"])

    # Deploy neo4j on the AKS cluster using Helm
    print("Deploying neo4j on the AKS cluster...")
    subprocess.run(["helm", "install", "azneo4j-sk", "../neo4j-on-azure/", "--create-namespace"])

    # Get the External IP of the neo4j LoadBalancer
    print("Getting the External IP of the neo4j LoadBalancer...")
    kubectl_output = subprocess.check_output(["kubectl", "get", "services"]).decode("utf-8")
    print(kubectl_output)

    neo4j_ip = "<pending>"
    while neo4j_ip == "<pending>":
        print("Waiting for external IP to be assigned...")
        time.sleep(10)  # Wait for 10 seconds before checking again
        kubectl_output = subprocess.check_output(["kubectl", "get", "services"]).decode("utf-8")
        for line in kubectl_output.splitlines():
            if "azure-neo4j-loadbalancer" in line:
                neo4j_ip = line.split()[-3]

    # Extract the External IP from the kubectl output
    for line in kubectl_output.splitlines():
        if "azure-neo4j-loadbalancer" in line:
            neo4j_ip = line.split()[-3]

    # # Test neo4j deployment by creating a test collection
    # print(f"Testing neo4j deployment with IP: {neo4j_ip}...")
    # test_collection_url = f"http://{neo4j_ip}:6333/collections/test_collection"
    # test_collection_data = '{"vectors": {"size": 4, "distance": "Dot"}}'
    # max_attempts = 3
    # attempt = 1
    # success = False
    # while not success and attempt <= max_attempts:
    #     try:
    #         print(f"Attempt {attempt}: Testing neo4j deployment with IP: {neo4j_ip}...")
    #         curl_output = subprocess.check_output(["curl", "-X", "PUT", test_collection_url, "-H", "Content-Type: application/json", "--data-raw", test_collection_data]).decode("utf-8")
    #         success = True
    #     except subprocess.CalledProcessError:
    #         attempt += 1
    #         time.sleep(10)  # Wait for 10 seconds before trying again
    # if not success:
    #     print("Error: Failed to connect to neo4j server after multiple attempts.")
    #     sys.exit(1)
    # print(curl_output)

    # if "result" in curl_output and "status" in curl_output:
    #     print("neo4j test collection created successfully!")
    # else:
    #     print("Error: Failed to create neo4j test collection.")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python deploy_neo4j.py <resource_group_name>")
        sys.exit(1)

    resource_group_name = sys.argv[1]
    main(resource_group_name)