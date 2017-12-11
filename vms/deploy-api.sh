#!/bin/bash

CONNECTION="$(az storage account show-connection-string --name $STORAGE_NAME --resource-group $RESOURCE_GROUP --output tsv)"
export AZURE_STORAGE_CONNECTION_STRING=$CONNECTION

mkdir -p .tmp
az storage blob download \
  --container-name $KEY_CONTAINER \
  --name api.pub \
  --file .tmp/key


###################################################################
############################ API ##################################
###################################################################


# Create a public IP to attach to the API
API_IP_NAME="dsgoapiPublicIP"
API_DNS="dsgoapi"
az network public-ip create \
  --name $API_IP_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $REGION \
  --allocation-method Static \
  --dns-name $API_DNS \
  --tags "ds-project=ifrcgo-infrastructure"


VNET_NAME="dsgoVnet"
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --location $REGION \
  --name $VNET_NAME \
  --address-prefix "192.168.0.0/16" \
  --tags "ds-project=ifrcgo-infrastructure"


API_SUBNET="dsgoapisubnet"
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name $API_SUBNET \
  --address-prefix "192.168.1.0/24"


# Create the NSG
GO_NSG="dsgoNSG"
az network nsg create \
  --resource-group $RESOURCE_GROUP \
  --location $REGION \
  --name $GO_NSG \
  --tags "ds-project=ifrcgo-infrastructure"


# open port 80 for HTTP traffic
az network nsg rule create \
  --resource-group $RESOURCE_GROUP \
  --nsg-name $GO_NSG \
  --name 'AllowHttp' \
  --access allow \
  --protocol Tcp \
  --direction Inbound \
  --priority 200 \
  --source-address-prefix "Internet" \
  --source-port-range "*" \
  --destination-address-prefix "*" \
  --destination-port-range 80


# open port 9200 for HTTP traffic
az network nsg rule create \
  --resource-group $RESOURCE_GROUP \
  --nsg-name $GO_NSG \
  --name 'AllowESHttp' \
  --access allow \
  --protocol Tcp \
  --direction Inbound \
  --priority 300 \
  --source-address-prefix "Internet" \
  --source-port-range "*" \
  --destination-address-prefix "*" \
  --destination-port-range 9200


API_NIC="dsgoapiPublicVMNIC"
az network nic create \
  --name $API_NIC \
  --resource-group $RESOURCE_GROUP \
  --network-security-group $GO_NSG \
  --location $REGION \
  --subnet $API_SUBNET \
  --private-ip-address 192.168.1.101 \
  --vnet-name $VNET_NAME \
  --public-ip-address $API_IP_NAME \
  --tags "ds-project=ifrcgo-infrastructure"


# Create a vm for the API
API_NAME="dsgoapi"
az vm create \
  --ssh-key-value @.tmp/key \
  --authentication-type ssh \
  --admin-username $API_ADMIN \
  --resource-group $RESOURCE_GROUP \
  --name $API_NAME \
  --nics $API_NIC \
  --location $REGION \
  --image UbuntuLTS \
  --storage-sku Standard_LRS \
  --tags "ds-project=ifrcgo-infrastructure"


# set the API docker extension
az vm extension set \
  --name DockerExtension \
  --publisher Microsoft.Azure.Extensions \
  --vm-name $API_NAME \
  --resource-group $RESOURCE_GROUP \
  --version 1.1


# remove the public key
rm .tmp/key