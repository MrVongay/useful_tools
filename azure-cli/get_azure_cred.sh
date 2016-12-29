#!/bin/bash
# This script has been tested in 
#   Ubuntu 14.04.5 LTS
#   Ubuntu 16.04 LTS
#
# To properly execute this script the Azure user must have permissions in AD
# - Create an app
# - Create a service principal
# - Create a role
# - Map role to service princpal
#
# Reference: https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-authenticate-service-principal-cli


# Initialize Parameters
# Create hidden directory for stuff if it doesn't exist

if [ ! -d $HOME/.Azure ]; then
    mkdir $HOME/.Azure
fi

# Use separate log file for each important step.

AzureCliInstallLog=$HOME/.Azure/AzureCliInstallLog
AzureAccountLog=$HOME/.Azure/PMCAzureAccountLog
AzureAppLog=$HOME/.Azure/PMCAzureAppLog
AzureServicePrincipalLog=$HOME/.Azure/PMCAzureServicePrincipalLog
AzureRoleLog=$HOME/.Azure/PMCAzureRoleLog
AzureRoleMapLog=$HOME/.Azure/PMCAzureRoleMapLog

AzureRolePermsFile=$HOME/.Azure/PMCExampleAzureRole.json

# Install nodejs and npm if they aren't installed

NodeStatus=`node -v 2>&1`

if [[ $NodeStatus =~ .*command* ]]; then
    echo "Installing nodejs and npm"
    curl -sL https://deb.nodesource.com/setup_7.x | sudo -E bash - >> $AzureCliInstallLog 2>&1
    sudo apt-get install -y nodejs >> $AzureCliInstallLog 2>&1
    echo
fi

# Install Azure CLI (if it doesn't exist already)
# Need to figure out how to determine if azure-cli is installed

AzureStatus=`azure -v 2>&1`

if [[ $AzureStatus =~ .*command.* ]]; then
    echo "Installing azure-cli"
    sudo npm install -g azure-cli >> $AzureCliInstallLog 2>&1
    echo
fi

# Login to Azure
# Prompt for username. Can't be NULL

echo "Logging into Azure."
echo

while [ -z $Username ]; 
do
    read -p "Enter your Azure username : " Username
done

azure login -u $Username


# Get subscription and tenant ID's
azure account show > $AzureAccountLog

SubscriptionID=`grep "ID" $AzureAccountLog | grep -v Tenant | awk -F": " '{print $3}' | xargs`
TenantID=`grep "Tenant ID" $AzureAccountLog | awk -F": " '{print $3}' | xargs`

# Prompt for App name. Can't be NULL
echo "Need to create a ParkMyCloud application in your subscription."
echo "Here's the catch: It must be unique. "
echo

while [ -z "$AppName" ]; 
do
    read -p "What do you want to call it? (e.g., ParkMyCloud Azure Dev): " AppName
done

# Prompt for application password
while [ -z "$AppPwd" ];
do 

    while [ -z "$AppPwd1" ]; 
    do
        echo "Enter password for your application: " 
        read -s AppPwd1
    done

    while [ -z "$AppPwd2" ]; 
    do
        echo "Re-enter your password: " 
        read -s AppPwd2
    done

    if [ "$AppPwd1"=="$AppPwd2 ];then
        AppPwd=$AppPwd1
    else
        echo "Your passwords do not match. Try again."
        echo
    fi
        
done


# Create App
# Can have -p <password> and provide password, but never get the key back

# If AppName is multiple words then replace whites spaces with "-"
HTTPName=`echo "$AppName" | sed "s/ /-/g"`

# Need proper enddate
azure ad app create -n "$AppName" -m "https://console.parkmycloud.com" -i "https://$HTTPName-not-used" -p "$AppPwd" > $AzureAppLog

AppID=`grep AppId $AzureAppLog | awk -F": " '{print $3}' | xargs`


# Create Service Principal for App
azure ad sp create -a $AppID > $AzureServicePrincipalLog

echo "Created service principal for application."
echo 

ServicePrincipalID=`grep Id $AzureServicePrincipalLog | awk -F": " '{print $3}' | xargs`
ServicePrincipalName=`grep  -A1 -P 'Names' ~/.Azure/PMCAzureServicePrincipalLog | awk -F: '{print $2}' | grep -v Names | xargs`

# Create custom role with limited permissions
# Generate permissions file

echo "{" > $AzureRolePermsFile
echo "    \"Name\": \"$AppName\"," >> $AzureRolePermsFile
echo "    \"Description\": \"$AppName Role\"," >> $AzureRolePermsFile
echo "    \"IsCustom\": \"True\"," >> $AzureRolePermsFile
echo "    \"Actions\": [" >> $AzureRolePermsFile
echo "        \"Microsoft.Compute/virtualMachines/read\"," >> $AzureRolePermsFile
echo "        \"Microsoft.Compute/virtualMachines/*/read\"," >> $AzureRolePermsFile
echo "        \"Microsoft.Compute/virtualMachines/start/action\"," >> $AzureRolePermsFile
echo "        \"Microsoft.Compute/virtualMachines/deallocate/action\"," >> $AzureRolePermsFile
echo "        \"Microsoft.Network/networkInterfaces/read\"," >> $AzureRolePermsFile
echo "        \"Microsoft.Network/publicIPAddresses/read\"," >> $AzureRolePermsFile
echo "        \"Microsoft.Compute/virtualMachineScaleSets/read\"," >> $AzureRolePermsFile
echo "        \"Microsoft.Compute/virtualMachineScaleSets/write\"," >> $AzureRolePermsFile
echo "        \"Microsoft.Compute/virtualMachineScaleSets/start/action\"," >> $AzureRolePermsFile
echo "        \"Microsoft.Compute/virtualMachineScaleSets/deallocate/action\"," >> $AzureRolePermsFile
echo "        \"Microsoft.Compute/virtualMachineScaleSets/*/read\"," >> $AzureRolePermsFile
echo "        \"Microsoft.Resources/subscriptions/resourceGroups/read\"" >> $AzureRolePermsFile
echo "    ]," >> $AzureRolePermsFile
echo "    \"NotActions\": []," >> $AzureRolePermsFile
echo "    \"AssignableScopes\": [" >> $AzureRolePermsFile
echo "    \"/subscriptions/$SubscriptionID\"" >> $AzureRolePermsFile
echo "    ]" >> $AzureRolePermsFile
echo "}" >> $AzureRolePermsFile

azure role create --inputfile $AzureRolePermsFile > $AzureRoleLog

echo "Created limited access role for app."
echo 

RoleID=`grep Id $AzureRoleLog | awk -F": " '{print $3}' | xargs`

# 
while [ -z "$SP_Present" ];
do
    SP_Present=`azure ad sp list | grep $ServicePrincipalID`
    echo "$SP_Present"
    echo "Waiting on Service Principal to show up in AD"
    sleep 30
done

# Assign role to application service principal
# sh ./map_role.sh

azure role assignment create "$ServicePrincipalID" --roleId "$RoleID"  --scope "/subscriptions/$SubscriptionID" > $AzureRoleMapLog

echo "Role has been mapped to service principal for application."
echo 

# Print out final values for user for ParkMyCloud cred
#   Subscription ID
#   Tenant ID
#   App ID (Client ID)
#   App API Access Key

echo "Subscription ID: $SubscriptionID"
echo "      Tenant ID: $TenantID"
echo "         App ID: $AppID"
echo " API Access Key: $AppPwd"
echo 
echo "Enter these on the Azure credential page in ParkMyCloud."
echo 

echo "If you want to login interactively with this service principal, enter the following from the CLI:"
echo 
echo "azure login -u $ServicePrincipalName --service-principal --tenant $TenantID"
echo
echo


