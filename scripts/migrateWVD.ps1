<#
.SYNOPSIS
    This script migrates Azure Windows Virtual Desktop (WVD) session hosts to Azure dedicated hosts.
.DESCRIPTION
    This scripts moved WVD session hosts in a hostpool to an already deployed Azure Dedicated Host Group.
    The script currently requires the Dedicated Host Group to already exist, but it will provision additional hosts
    when existing hosts are at capacity.

    By default, it shuts down and migrates all virtual machines in a WVD hostpool, but you can also only move VMs
    in drainmode by using the -drainmode switch.
    
.LINK
    https://github.com/SteveDatAzureGov/WVD_IL5

.EXAMPLE
    .\migrateWVD.ps1 -resourceGroupName 'wvd-sessionhosts-rg' -wvdHostPool 'MYHP' -hostGroupName 'MYHG' -skuName 'DSv3-Type1'

    Moves all VMs in the MYHP WVD host pool to the MYHG Azure Dedicated Host Group.

.EXAMPLE
    .\migrateWVD.ps1 -resourceGroupName 'SD322A-sharedsvcs-rg' -wvdHostPool 'DEDHPG' -hostGroupName 'MYHGG' -skuName 'DSv3-Type1' -subscriptionID '3c09cfd5-3ea6-48c8-a9ac-3f997816d723'

    Moves all VMs in the MYHP WVD host pool to the MYHG Azure Dedicated Host Group. Specifies a subscription ID.

.EXAMPLE
    .\migrateWVD.ps1 -resourceGroupName 'SD322A-sharedsvcs-rg' -wvdHostPool 'DEDHPG' -hostGroupName 'MYHGG' -skuName 'DSv3-Type1' -environment 'AzureUSGovernment'

    Connects to Azure Government. Moves all VMs in the MYHP WVD host pool to the MYHG Azure Dedicated Host Group.

.INPUTS
    None. You cannot pipe objects into this script.

.OUTPUTS
    None. Only console text is displayed by this script.
#>

#
#################################
# Azure Settings & other parms
#################################

[CmdletBinding(SupportsShouldProcess=$false)]
param(
    [Parameter(Mandatory=$true)] 
    [string] $resourceGroupName,
    [Parameter(Mandatory=$true)]
    [string] $wvdHostPool,
    [Parameter(Mandatory=$true)] 
    [string] $hostGroupName,
    [Parameter(Mandatory=$true)]
    [string] $skuName,
    [Parameter(Mandatory=$false)]
    [Switch]$drainmode,
    [string] $subscriptionID,
    [string] $environment
  )


#################################
# Functions
#################################
  function Select-Host {
   [CmdletBinding()]
   param(
      [Parameter(Mandatory=$true)] 
      [string] $hostGroupName,
      [Parameter(Mandatory=$true)]
      [string] $resourceGroupName,
      [Parameter(Mandatory=$true)]
      [string] $vmType,
      [Parameter(Mandatory=$true)]
      [string] $skuName
   )

   $spaceAvailable = $false

   $myHG = Get-AzHostGroup -ResourceGroupName $resourceGroupName -hostGroupName $hostGroupName -InstanceView
 
   foreach ($h in $myHG.InstanceView.Hosts) {
      $dhName = $h.Name
      $allocatableVMs = $h.AvailableCapacity.AllocatableVMs

      Write-Host "Host:" $h.Name

      $vmTypeDetails = $allocatableVMs.Where({$_.VMsize -eq $vmType})

      Write-host "Allocatable $vmType VMs:" $vmTypeDetails[0].Count
      [boolean] $spaceAvailable = $vmTypeDetails[0].Count

      if ($spaceAvailable -eq $true) {
         $selectedHostName = $h.Name
         Write-host "Selecting host:" $selectedHostName
         $myDH = Get-AzHost -HostGroupName $hostGroupName -ResourceGroupName $resourceGroupName -Name $selectedHostName
         return $myDH
      }
   }

   #All hosts are full so another needs to be added to the Dedicated Host Group
   $splitHost = $dhName -split '(?=\d)',2
   $newHostNumber = [int]$splitHost[1] + 1
   $newHostname = $splitHost[0] + $newHostNumber
   Write-Host "Deploying host: " $newHostName
   $h = New-AzHost -ResourceGroupName $resourceGroupName -HostGroupName $hostGroupName -Name $newHostname -Sku $skuName -location $myHG.location
   return $h       
}

  
#################################
# Install WVD Module... in case you don't have it
#################################

if (!(Get-Module -ListAvailable -name Az.DesktopVirtualization)) {
   Write-Verbose "Installing WVD Powershell module"
   Install-Module -Name Az.DesktopVirtualization
}

#################################
# Connect to Azure
#################################
If (!(Get-AzContext)) {
   Write-Host "Please login to Azure"

   if($environment) {
      Connect-AzAccount -Environment $environment
   }
   else {
      Connect-AzAccount
   }
}

if ($subscriptionID) {
   Select-AzSubscription -SubscriptionId $SubscriptionID
}


#################################
# Retreive eligible VMs in the WVD Hostpool. If -drainmode is passed, then only select VMs in drainmode
#################################

if($drainMode) {
   Write-Host "SELECTING SESSION HOSTS: Only $wvdHostPool session hosts in Drain Mode will be moved to dedicated hosts."
   $VMs = Get-AZWVDSessionHost -ResourceGroupName $resourceGroupName -HostPoolName $wvdHostPool | Where-Object {$_.AllowNewSession -eq $false}
} else {   
   Write-Host "SELECTING SESSION HOSTS: All $wvdHostPool session hosts will be moved to dedicated hosts."
   $VMs = Get-AZWVDSessionHost -ResourceGroupName $resourceGroupName -HostPoolName $wvdHostPool
}


# Determine which VMs to move. VMs with active user sessions and VMs already assigned to a dedicated host will be skipped.
$eligibleVMs = [System.Collections.ArrayList]::new()
foreach ($VM in $VMs) {
   $DNSname = $VM.name.split("/")[1]
	$VMname = $DNSname.split(".")[0]

   $myVM = Get-AzVM -ResourceGroupName $resourceGroupName -Name $VMname
   if ($VM.session -ne 0) {
      Write-Host "SKIPPING: $VMname has active user sessions."
   }
   elseif ($null -ne $myVM.Host.Id) {
      $hostID = $myVM.Host.Id
      Write-Host "SKIPPING: $VMname is already assigned $hostID."
   }
   else {
      if ($VM.AllowNewSession -eq $true ) {
         Update-AzWvdSessionHost -ResourceGroupName $resourceGroupName -HostPoolName $wvdHostPool -name $DNSname -AllowNewSession:$false | Out-Null
      }

      Write-Host "STOPPING: $VMname"
      Stop-AzVM -ResourceGroupName $resourceGroupName -Name $VMname -Force
      $eligibleVMs.Add($VM) | Out-Null
   }
}

#################################
# Move eligible VMs to Dedicated Hosts
#################################

foreach ($VM in $eligibleVMs) {
	$DNSname = $VM.name.split("/")[1]
	$VMname = $DNSname.split(".")[0]
   $myVM = Get-AzVM -ResourceGroupName $resourceGroupName -Name $VMname

   Write-Host "-== Evaluating $VMname ==-"

   if ($null -eq $myVM.Host.Id) {
      Write-Host "$VMname is not assigned a dedicted host"
      $myVM.Host = New-Object Microsoft.Azure.Management.Compute.Models.SubResource

      #Select host for deployment
      $myDH = Select-Host -hostGroupName $hostGroupName -resourceGroupName $resourceGroupName -skuName $skuName -vmType $myVM.HardwareProfile.VmSize

      $dhName = $myDH.Name
      Write-Host "-== Moving $VMname to $dhName ==-"
      $myVM.Host.Id = $myDH.Id

      Update-AzVM -ResourceGroupName $resourceGroup -VM $myVM 
      Update-AzWvdSessionHost -ResourceGroupName $resourceGroupName -HostPoolName $wvdHostPool -name $DNSname -AllowNewSession:$true

      Write-Host "STARTING: $VMname"
      Start-AzVM -ResourceGroupName $resourceGroupName -Name $VMName -NoWait

   } else {
      if ($myVM.Host.Id) { Write-Host "-== $VMname is already assigned to " $myVM.Host.Id  "==-" }
   }
}