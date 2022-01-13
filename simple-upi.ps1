#!/usr/bin/pwsh

. .\upi-variables.ps1

$ErrorActionPreference = "Stop"

Connect-VIServer -Server $vcenter -Credential (Import-Clixml $vcentercredpath)

$installerUrl = "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable-$($Version)/openshift-install-linux.tar.gz"

# how to get the installer
# change this to the api and grab the latest okd release based on version
$installerUrl = "https://github.com/openshift/okd/releases/download/4.9.0-0.okd-2021-12-12-025847/openshift-install-linux-4.9.0-0.okd-2021-12-12-025847.tar.gz"


if (-Not (Test-Path -Path "openshift-install")) {
    Invoke-WebRequest -uri $installerUrl -OutFile "installer.tar.gz"
    tar -xvf "installer.tar.gz"
}

if (-Not (Test-Path -Path "template-$($Version).ova")) {
    Start-Process -Wait -Path ./openshift-install -ArgumentList @("coreos", "print-stream-json") -RedirectStandardOutput coreos.json

    $coreosData= Get-Content -Path ./coreos.json | ConvertFrom-Json -AsHashtable
    $ovaUri = $coreosData.architectures.x86_64.artifacts.vmware.formats.ova.disk.location 
    Invoke-WebRequest -uri $ovaUri -OutFile "template-$($Version).ova"
}


$config = Get-Content -Path ./install-config.json | ConvertFrom-Json

$config.metadata.name = $clustername
$config.baseDomain = $basedomain
$config.sshKey = [string](Get-Content -Path $sshkeypath -Raw:$true)
$config.platform.vsphere.vcenter = $vcenter
$config.platform.vsphere.username = $username
$config.platform.vsphere.password = $password
$config.platform.vsphere.datacenter = $datacenter
$config.platform.vsphere.defaultDatastore = $datastore
$config.platform.vsphere.cluster = $cluster
$config.platform.vsphere.network = $portgroup

$config.platform.vsphere.apiVIP = $apivip
$config.platform.vsphere.ingressVIP = $ingressvip

$config.pullSecret = $pullsecret -replace "`n", "" -replace " ", ""

$config | ConvertTo-Json | Out-File -FilePath install-config.yaml -Force:$true


start-process -Wait -FilePath ./openshift-install -argumentlist @("create","manifests")
start-process -Wait -FilePath ./openshift-install -argumentlist @("create", "ignition-configs")

$metadata = Get-Content -Path ./metadata.json | ConvertFrom-Json

$templateName = "$($metadata.infraID)-rhcos"


$folder = Get-Folder -Name $metadata.infraID -ErrorAction continue 
if (-Not $?) {
	(get-view (Get-Datacenter -Name ibmcloud).ExtensionData.vmfolder).CreateFolder($metadata.infraID)
	$folder = Get-Folder -Name $metadata.infraID
}

$template = Get-VM -Name $templateName -ErrorAction continue 

if (-Not $?) {
    $vmhost = Get-Random -InputObject (Get-VMHost -Location (Get-Cluster $cluster))
    $ovfConfig = Get-OvfConfiguration -Ovf "template-$($Version).ova"
    $ovfConfig.NetworkMapping.VM_Network.Value = $portgroup

    # add folder to import-vapp
    $template = Import-Vapp -Source "template-$($Version).ova" -Name $templateName -OvfConfiguration $ovfConfig -VMHost $vmhost -Datastore $Datastore -InventoryLocation $folder -Force:$true
}

$vmHash = ConvertFrom-Json -InputObject $virtualmachines -AsHashtable

foreach ($key in $vmHash.virtualmachines.Keys) {
    $node = $vmHash.virtualmachines[$key]

    $name = "$($metadata.infraID)-$($key)"


    $rp = Get-Cluster -Name $node.cluster -Server $node.server
    $datastore = Get-Datastore -Name $node.datastore -Server $node.server

    $bytes = Get-Content -Path "./$($node.type).ign" -AsByteStream
    $ignition = [Convert]::ToBase64String($bytes)

    $vm = New-VM -VM $template -Name $name -ResourcePool $rp -Datastore $datastore -Location $folder
    $vm | Get-HardDisk | Select-Object -First 1 | Set-HardDisk -CapacityGB 128 -Confirm:$false
    $vm | Set-VM -MemoryGB 16 -NumCpu 4 -CoresPerSocket 4 -Confirm:$false

    $vm | New-AdvancedSetting -name "guestinfo.ignition.config.data" -value $ignition -confirm:$false -Force > $null
    $vm | New-AdvancedSetting -name "guestinfo.ignition.config.data.encoding" -value "base64" -confirm:$false -Force > $null
    $vm | New-AdvancedSetting -name "guestinfo.hostname" -value $name -Confirm:$false -Force
}
