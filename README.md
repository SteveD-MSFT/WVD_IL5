# WVD IL5 Tools
    This scripts moves WVD session hosts in a hostpool to an already deployed Azure Dedicated Host Group.
    The script currently requires the Dedicated Host Group to already exist, but it will provision additional hosts
    when existing hosts are at capacity.

    By default, it shuts down and migrates all virtual machines in a WVD hostpool, but you can also only move VMs
    in drainmode by using the -drainmode switch.
    

## EXAMPLES
    .\migrateWVD.ps1 -resourceGroupName 'wvd-sessionhosts-rg' -wvdHostPool 'MYHP' -hostGroupName 'MYHG' -skuName 'DSv3-Type1'

    Moves all VMs in the MYHP WVD host pool to the MYHG Azure Dedicated Host Group.

    .\migrateWVD.ps1 -resourceGroupName 'SD322A-sharedsvcs-rg' -wvdHostPool 'DEDHPG' -hostGroupName 'MYHGG' -skuName 'DSv3-Type1' -subscriptionID '3c09cfd5-3ea6-48c8-a9ac-3f997816d723'

    Moves all VMs in the MYHP WVD host pool to the MYHG Azure Dedicated Host Group. Specifies a subscription ID.

    .\migrateWVD.ps1 -resourceGroupName 'SD322A-sharedsvcs-rg' -wvdHostPool 'DEDHPG' -hostGroupName 'MYHGG' -skuName 'DSv3-Type1' -environment 'AzureUSGovernment'

    Connects to Azure Government. Moves all VMs in the MYHP WVD host pool to the MYHG Azure Dedicated Host Group.
