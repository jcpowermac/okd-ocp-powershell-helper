#!/bin/pwsh

. .\upi-variables.ps1

function ConvertTo-Base64 {
    <#
    .SYNOPSIS
        Writes a base64 encoded string
    #>
    [CmdletBinding()]
    param ([string]$Path)
    begin{}
    process {
        $bytes = Get-Content -Path $Path -AsByteStream
        $encoded = [Convert]::ToBase64String($bytes)
    }
    end{return $encoded}
}

function Get-RhcosOva {
    <#
    .SYNOPSIS
    #>
    [CmdletBinding()]
    param ([string]$Version)
    begin{}
    process {
        if(-Not (Test-Path -Path "rhcos-$($Version).ova")) {
        $rhcosDataUrl = "https://raw.githubusercontent.com/openshift/installer/release-$($Version)/data/data/rhcos.json"
        $rhcosData = (Invoke-WebRequest -Uri $rhcosDataUrl |ConvertFrom-Json -AsHashtable)
        $ovaUri = $rhcosData.baseURI + $rhcosData.images.vmware.path
        Invoke-WebRequest -uri $ovaUri -OutFile "rhcos-$($Version).ova"
        }
    }
}

function Invoke-Installer () {
    <#
    .SYNOPSIS
    #>
    [CmdletBinding()]
    param()
    begin{}
    process{
        ./openshift-install create manifests
        ./openshift-install create ignition-configs
        $metadata = Get-Content -Path ./metadata.json | ConvertFrom-Json
    }
    end{return $metadata.infraID}
}

function Initialize-Installer () {
    <#
    .SYNOPSIS
    #>
    [CmdletBinding()]
    param()
    begin{}
    process{
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
        $config.pullSecret = $pullsecret -replace "`n","" -replace " ",""

        $config | ConvertTo-Json | Out-File -FilePath install-config.yaml -Force:$true
    }
    end{}
}


function Get-Installer () {
    <#
    .SYNOPSIS
    #>
    [CmdletBinding()]
    param ([string]$Version)
    begin{}
    process {
        $installerUrl = "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable-$($Version)/openshift-install-linux.tar.gz"

        if(-Not (Test-Path -Path "openshift-install")) {
            Invoke-WebRequest -uri $installerUrl -OutFile "installer.tar.gz"
            tar -xvf "installer.tar.gz"
        }
    }
    end {}
}

function Import-RhcosOva {
    <#
    .SYNOPSIS
    #>
    [CmdletBinding()]
    param(
        [string]$Ovf,
        [string]$PortGroup,
        [string]$Name,
        [string]$Datastore
    )
    begin{}
    process {

        $vm = Get-VM -Name $Name

        if (-Not $?) {
            $vmhost = Get-Random -InputObject (Get-VMHost)
            $ovfConfig = Get-OvfConfiguration -Ovf $Ovf
            $ovfConfig.NetworkMapping.VM_Network.Value = $PortGroup
            $vm = Import-Vapp -Source $Ovf -Name $Name -OvfConfiguration $ovfConfig -VMHost $vmhost -Datastore $Datastore -Force:$true
        }
    }
    end{return $vm}
}

function New-RhcosVM {
    <#
    .SYNOPSIS
    #>
    [CmdletBinding()]
    param(
        [object]$Template,
        [string]$Name,
        [string]$Ignition, # do we really want this to be a string? Who knows what this will do to the encoding
        [string]$IPAddress,
        [string]$Gateway,
        [string]$Netmask,
        [string]$Dns,
        [int]$NumCpu,
        [long]$MemoryMB,
        [string]$ResourcePool,
        [string]$Datastore,
        [object]$Folder
    )
    begin{}
    process {
        $network = "ip=$($IPAddress)::$($Gateway):$($Netmask):$($Name):ens192:off:$($Dns)"

        $rp = Get-Cluster -Name $ResourcePool

        if(-Not $?) {
            $rp = Get-ResourcePool -Name $ResourcePool
        }

        $vm = New-VM -VM $Template -Name $Name -ResourcePool $rp -Datastore (Get-Datastore -Name $Datastore) -Location $Folder
        $vm | Get-HardDisk | Select-Object -First 1 | Set-HardDisk -CapacityGB 120 -Confirm:$false
        $vm | Set-VM -MemoryGB 16 -NumCpu 4 -CoresPerSocket 4 -Confirm:$false

        $vm | New-AdvancedSetting -name "guestinfo.ignition.config.data" -value $Ignition -confirm:$false -Force > $null
        $vm | New-AdvancedSetting -name "guestinfo.ignition.config.data.encoding" -value "base64" -confirm:$false -Force > $null
        $vm | New-AdvancedSetting -name "guestinfo.afterburn.initrd.network-kargs" -value $network -confirm:$false -Force > $null
        $vm | New-AdvancedSetting -name "guestinfo.hostname" -value $Name -Confirm:$false -Force
    }
    end{return $vm}
}

Get-Installer -Version $version

# this should return the path to the ova
Get-RhcosOva -Version $version

Initialize-Installer
$infraid = Invoke-Installer

$folder = New-Folder -Name $infraid -Confirm:$false -Location (Get-Folder vm)

$vm = Import-RhcosOva -Ovf "rhcos-$($version).ova" -Name "$($infraid)-rhcos" -Datastore $datastore -PortGroup $portgroup

$masterIgn = ConvertTo-Base64 -Path ./master.ign
$bootstrapIgn = ConvertTo-Base64 -Path ./bootstrap.ign

New-RhcosVM -Template $vm -Name "$($infraid)-bootstrap" -MemoryMB 16384 -NumCpu 4 -IPAddress "192.168.59.3" -Netmask "255.255.255.224" -Dns "10.0.0.2" -Gateway "192.168.59.1" -Ignition $bootstrapIgn -ResourcePool "Cluster-1" -Datastore "WorkloadDatastore" -Folder $folder
New-RhcosVM -Template $vm -Name "$($infraid)-master-0" -MemoryMB 16384 -NumCpu 4 -IPAddress "192.168.59.4" -Netmask "255.255.255.224" -Dns "10.0.0.2" -Gateway "192.168.59.1" -Ignition $masterIgn -ResourcePool "Cluster-1" -Datastore "WorkloadDatastore" -Folder $folder
New-RhcosVM -Template $vm -Name "$($infraid)-master-1" -MemoryMB 16384 -NumCpu 4 -IPAddress "192.168.59.5" -Netmask "255.255.255.224" -Dns "10.0.0.2" -Gateway "192.168.59.1" -Ignition $masterIgn -ResourcePool "Cluster-1" -Datastore "WorkloadDatastore" -Folder $folder
New-RhcosVM -Template $vm -Name "$($infraid)-master-2" -MemoryMB 16384 -NumCpu 4 -IPAddress "192.168.59.6" -Netmask "255.255.255.224" -Dns "10.0.0.2" -Gateway "192.168.59.1" -Ignition $masterIgn -ResourcePool "Cluster-1" -Datastore "WorkloadDatastore" -Folder $folder




