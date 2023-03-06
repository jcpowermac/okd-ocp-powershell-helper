#!/usr/bin/pwsh

. .\dev-variables.ps1

$ErrorActionPreference = "Stop"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue

Connect-VIServer -Server $vcenter -Credential (Import-Clixml $vcentercredpath)

$releaseStreamUri = "https://amd64.$($project).releases.ci.openshift.org/api/v1/releasestream/$($releaseStream)/latest"


$progressPreference = 'silentlyContinue'
$webrequest = Invoke-WebRequest -uri $releaseStreamUri
$progressPreference = 'Continue'
$releases = ConvertFrom-Json $webrequest.Content -AsHashtable
$registry = ($releases['pullSpec'] -split '/')[0]

# Set Release Image Override for Installer
$Env:OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE = $releases['pullSpec']

# Read and convert the cloud.redhat.com pull secret
$tempPullSecret = Get-Content -Path $pullSecretFile -raw
$pullSecretHash = ConvertFrom-Json $tempPullSecret -AsHashtable


# Download `oc`
if (-Not (Test-Path -Path "./bin/oc")) {
    $ocClientUri = "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$($ocClientVersion)/openshift-client-linux.tar.gz"
    #$progressPreference = 'silentlyContinue'
    Invoke-WebRequest -uri $ocClientUri -OutFile "oc.tar.gz"
    tar -xvf "oc.tar.gz" -C ./bin
    #$progressPreference = 'Continue'
}

# if the installer is missing or the ci registry token file is greater than 12 hours old
if ( (-Not (Test-Path -Path "./bin/openshift-install")) -or (-Not (Test-Path ./secrets/ci.json -NewerThan (get-date).AddHours(-12)))) {

    $token = Read-Host -Prompt "Token from $($ciTokenUri)" -MaskInput

    # TODO: Change to start-process
    ./bin/oc login --token=$token --server=$ciApiUri
    ./bin/oc registry login --to $ciRegistryAuthFile

    $ciauth = Get-Content -Path $ciRegistryAuthFile -Raw
    $ciHash = ConvertFrom-Json $ciauth -AsHashtable
    if ($pullSecretHash["auths"].ContainsKey($registry)) {
        $pullSecretHash["auths"].Remove($registry)
        $pullSecretHash["auths"].Add($registry, $ciHash["auths"][$registry])
    }
    else {
        $pullSecretHash["auths"].Add($registry, $ciHash["auths"][$registry])
    }
    $pullSecret = ConvertTo-Json $pullSecretHash
    Out-File -FilePath $pullSecretFile -InputObject $pullSecret -Force -Confirm:$false

    ./bin/oc adm release extract --tools $releases['pullSpec'] --registry-config $pullSecretFile

    Get-Item -Path *.tar.gz | ForEach-Object -Process {
        tar -xvf $_ -C ./bin
    }
    Remove-Item -Path *.tar.gz
    Remove-Item -Path *.txt
}

$pullSecret = ConvertTo-Json $pullSecretHash


Write-Output "Downloading OVA"
Start-Process -Wait -Path ./bin/openshift-install -ArgumentList @("coreos", "print-stream-json") -RedirectStandardOutput coreos.json
$coreosData = Get-Content -Path ./coreos.json | ConvertFrom-Json -AsHashtable
$sha = $coreosData.architectures.x86_64.artifacts.vmware.formats.ova.disk.sha256
$ovaUri = $coreosData.architectures.x86_64.artifacts.vmware.formats.ova.disk.location

# If the OVA doesn't exist on the path, determine the url from openshift-install and download it.
if (-Not (Test-Path -Path "$($sha).ova")) {
    #$progressPreference = 'silentlyContinue'
    Invoke-WebRequest -uri $ovaUri -OutFile "$($sha).ova"
    #$progressPreference = 'Continue'
}

$config = ConvertFrom-Json -InputObject $installconfig
#$vcenterObj = ConvertFrom-Json -InputObject $vcenterJson
#$failureDomainObj = ConvertFrom-Json -InputObject $failureDomainJson

# Set the install-config.json from upi-variables
$config.metadata.name = $clustername
$config.baseDomain = $basedomain
$config.sshKey = [string](Get-Content -Path $sshkeypath -Raw:$true)
$config.platform.vsphere.apiVIP = $apivip
$config.platform.vsphere.ingressVIP = $ingressvip
$config.pullSecret = $pullSecret -replace "`n", "" -replace " ", ""
$config.platform.vsphere.vcenters[0].user = $username
$config.platform.vsphere.vcenters[0].password = $password

# Write out the install-config.yaml (really json)
$config | ConvertTo-Json -Depth 8 | Out-File -FilePath ./secrets/install-config.yaml -Force:$true

# openshift-install create manifests
start-process -Wait -FilePath ./bin/openshift-install -argumentlist @("create", "manifests", "--dir", "./secrets")

#Remove-Item -Path ./secrets/openshift/99_openshift-cluster-api_master-machines-*.yaml
Remove-Item -Path ./secrets/openshift/99_openshift-cluster-api_worker-machineset-*.yaml 

# openshift-install create ignition-configs
start-process -Wait -FilePath ./bin/openshift-install -argumentlist @("create", "ignition-configs", "--dir", "./secrets")

# Remove openshift install state and log
Remove-Item -Path ./secrets/.openshift_install* -Force:$true

$Env:KUBECONFIG = "$($Env:PWD)/secrets/auth/kubeconfig" 

# Convert the installer metadata to a powershell object
$metadata = Get-Content -Path ./secrets/metadata.json | ConvertFrom-Json

$folder = @{}
$template = @{}
$snapshot = @{}


foreach ($key in $failureDomainMap.Keys) {
    # Since we are using MachineSets for the workers make sure we set the
    # template name to what is expected to be generated by the installer.
    $region = $failureDomainMap[$key].region
    $zone = $failureDomainMap[$key].zone
    $computeCluster = ($failureDomainMap[$key].topology.computeCluster -Split "/") | Select-Object -Last 1
    $datacenterName = $failureDomainMap[$key].topology.datacenter
    $templateName = "$($metadata.infraID)-rhcos-$($region)-$($zone)"
    $portgroup = $failureDomainMap[$key].topology.networks | Select-Object -First 1
    $datastoreName = ($failureDomainMap[$key].topology.datastore -Split "/") | Select-Object -Last 1

    $datacenter = Get-Datacenter -Name $datacenterName
    $datastore = Get-Datastore -Name $datastoreName -Location $datacenter

    New-Folder -Name $metadata.infraID -Location (Get-Folder -Name vm -Location $datacenter) -ErrorAction SilentlyContinue 
    $folder[$key] = Get-Folder -Name $metadata.infraID -Location (Get-Folder -Name vm -Location $datacenter)

    $template[$key] = Get-VM -Name $templateName -ErrorAction SilentlyContinue 

    # Otherwise import the ova to a random host on the vSphere cluster
    if (-Not $?) {
        $vmhost = Get-Random -InputObject (Get-VMHost -Location (Get-Cluster $computeCluster))
        $ovfConfig = Get-OvfConfiguration -Ovf "$($sha).ova"
        $ovfConfig.NetworkMapping.VM_Network.Value = $portgroup
        $template[$key] = Import-Vapp -Source "$($sha).ova" -Name $templateName -OvfConfiguration $ovfConfig -VMHost $vmhost -Datastore $datastore -InventoryLocation $folder[$key] -Force:$true

        Set-VM -VM $template[$key] -Version "v$($hardwareVersion)" -MemoryGB 16 -NumCpu 4 -CoresPerSocket 4 -Confirm:$false > $null
        Get-HardDisk -VM $template[$key] | Select-Object -First 1 | Set-HardDisk -CapacityGB 120 -Confirm:$false > $null
        New-AdvancedSetting -Entity $template[$key] -name "disk.EnableUUID" -value 'TRUE' -confirm:$false -Force > $null
        New-AdvancedSetting -Entity $template[$key] -name "guestinfo.ignition.config.data.encoding" -value "base64" -confirm:$false -Force > $null
        $snapshot[$key] = New-Snapshot -VM $template[$key] -Name "linked-clone" -Description "linked-clone" -Memory -Quiesce
    }
    else {
        $snapshot[$key] = Get-Snapshot -VM $template[$key] -Name "linked-clone" 
    }
}


Write-Progress -id 222 -Activity "Creating virtual machines" -PercentComplete 0

# TODO: this
$vmStep = (100 / 7)
$vmCount = 1
$wait = 0
foreach ($nodetype in @("bootstrap", "master", "worker")) {
    switch ($nodetype) {
        "bootstrap" {  
            $nodeTypeCount = 1
            $zones = @($masterZones[0])
            $wait = 0
        }
        "master" {
            $nodeTypeCount = 3
            $zones = $masterZones
            $wait = 300
        }
        "worker" {
            $nodeTypeCount = 3
            $zones = $workerZones
            $wait = 600
        }
    }

    for ($i = 0; $i -lt $nodeTypeCount; $i++ ) {
        $zoneName = $zones[$i % $zones.Count]
        $fd = $failureDomainMap[$zoneName]
        $datacenterName = $fd.topology.datacenter
        $computeClusterName = ($fd.topology.computeCluster -Split "/") | Select-Object -Last 1
        $datastoreName = ($fd.topology.datastore -Split "/") | Select-Object -Last 1
        $name = "$($metadata.infraID)-$($nodetype)-$($i)"
        $computeCluster = Get-Cluster -Name $computeClusterName
        $datacenter = Get-Datacenter -Name $datacenterName
        $datastore = Get-Datastore -Name $datastoreName -Location $datacenter

        # Get the content of the ignition file per machine type (bootstrap, master, worker)
        $bytes = Get-Content -Path "./secrets/$($nodetype).ign" -AsByteStream
        $ignition = [Convert]::ToBase64String($bytes)

        # Clone the virtual machine from the imported template
        $vm = New-VM -VM $template[$zoneName] -Name $name -ResourcePool $computeCluster -Datastore $datastore -Location $folder[$zoneName] -LinkedClone -ReferenceSnapshot $snapshot[$zoneName]

        New-AdvancedSetting -Entity $vm -name "guestinfo.ignition.config.data" -value $ignition -confirm:$false -Force > $null
        New-AdvancedSetting -Entity $vm -name "guestinfo.hostname" -value $name -Confirm:$false -Force > $null

        Start-ThreadJob -ThrottleLimit 10 -ArgumentList ($wait, $vm) -ScriptBlock {
            param($waitSec, $virtualMachine)
            Start-Sleep -Seconds $waitSec
            $virtualMachine | Start-VM
        }

        Write-Progress -id 222 -Activity "Creating virtual machines" -PercentComplete ($vmStep * $vmCount)
        $vmCount++
    }
}
Write-Progress -id 222 -Activity "Completed virtual machines" -PercentComplete 100 -Completed

Clear-Host

# Instead of restarting openshift-install to wait for bootstrap, monitor
# the bootstrap configmap in the kube-system namespace

# Extract the Client Certificate Data from auth/kubeconfig
$match = Select-String "client-certificate-data: (.*)" -Path ./secrets/auth/kubeconfig
[Byte[]]$bytes = [Convert]::FromBase64String($match.Matches.Groups[1].Value)
$clientCertData = [System.Text.Encoding]::ASCII.GetString($bytes)

# Extract the Client Key Data from auth/kubeconfig
$match = Select-String "client-key-data: (.*)" -Path ./secrets/auth/kubeconfig
$bytes = [Convert]::FromBase64String($match.Matches.Groups[1].Value)
$clientKeyData = [System.Text.Encoding]::ASCII.GetString($bytes)

# Create a X509Certificate2 object for Invoke-WebRequest
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem($clientCertData, $clientKeyData)

# Extract the kubernetes endpoint uri
$match = Select-String "server: (.*)" -Path ./secrets/auth/kubeconfig
$kubeurl = $match.Matches.Groups[1].Value

$apiTimeout = (20 * 60)
$apiCount = 1
$apiSleep = 30
Write-Progress -Id 444 -Status "1% Complete" -Activity "API" -PercentComplete 1
:api while ($true) {
    Start-Sleep -Seconds $apiSleep
    try {
        $webrequest = Invoke-WebRequest -Uri "$($kubeurl)/version" -SkipCertificateCheck
        $version = (ConvertFrom-Json $webrequest.Content).gitVersion

        if ($version -ne "" ) {
            Write-Debug "API Version: $($version)"
            Write-Progress -Id 444 -Status "Completed" -Activity "API" -PercentComplete 100
            break api
        }
    }
    catch {}

    $percentage = ((($apiCount * $apiSleep) / $apiTimeout) * 100)
    if ($percentage -le 100) {
        Write-Progress -Id 444 -Status "$percentage% Complete" -Activity "API" -PercentComplete $percentage
    }
    $apiCount++
}


$bootstrapTimeout = (30 * 60)
$bootstrapCount = 1
$bootstrapSleep = 30
Write-Progress -Id 333 -Status "1% Complete" -Activity "Bootstrap" -PercentComplete 1
:bootstrap while ($true) {
    Start-Sleep -Seconds $bootstrapSleep

    try {
        $webrequest = Invoke-WebRequest -Certificate $cert -Uri "$($kubeurl)/api/v1/namespaces/kube-system/configmaps/bootstrap" -SkipCertificateCheck

        $bootstrapStatus = (ConvertFrom-Json $webrequest.Content).data.status

        if ($bootstrapStatus -eq "complete") {
            Get-VM "$($metadata.infraID)-bootstrap-0" | Stop-VM -Confirm:$false | Remove-VM -Confirm:$false
            Start-ThreadJob -Name csr -ThrottleLimit 10 -ScriptBlock {
                while ($true) {
                    Start-Sleep -Seconds 30 
                    $ocGetCsrProcess = Start-Process -PassThru -Wait -Path ./bin/oc -ArgumentList @("get", "csr", "-o", "json") -RedirectStandardOutput csr.json -ErrorAction SilentlyContinue 

                    if ($ocGetCsrProcess.ExitCode -eq 0) { 
                        $csr = (Get-Content -Path ./csr.json | ConvertFrom-Json)
                        foreach ($c in $csr.items) {
                            if ($c.status.certificate -eq $null) {
                                Start-Process -Wait -Path ./bin/oc -ArgumentList @("adm", "certificate", "approve", $c.metadata.name) -ErrorAction SilentlyContinue 
                            }
                        }
                        Remove-Item -Path ./csr.json
                    }
                }
            }

            Write-Progress -Id 333 -Status "Completed" -Activity "Bootstrap" -PercentComplete 100
            break bootstrap
        }
    }
    catch {}

    $percentage = ((($bootstrapCount * $bootstrapSleep) / $bootstrapTimeout) * 100)
    if ($percentage -le 100) {
        Write-Progress -Id 333 -Status "$percentage% Complete" -Activity "Bootstrap" -PercentComplete $percentage
    }
    else {
        Write-Output "Warning: Bootstrap taking longer than usual." -NoNewLine -ForegroundColor Yellow
    }

    $bootstrapCount++
}

$progressMsg = ""
Write-Progress -Id 111 -Status "1% Complete" -Activity "Install" -PercentComplete 1
:installcomplete while ($true) {
    Start-Sleep -Seconds 30
    try {
        $webrequest = Invoke-WebRequest -Certificate $cert -Uri "$($kubeurl)/apis/config.openshift.io/v1/clusterversions" -SkipCertificateCheck

        $clusterversions = ConvertFrom-Json $webrequest.Content -AsHashtable

        # just like the installer check the status conditions of the clusterversions config
        foreach ($condition in $clusterversions['items'][0]['status']['conditions']) {
            switch ($condition['type']) {
                "Progressing" {
                    if ($condition['status'] -eq "True") {

                        $matchper = ($condition['message'] | Select-String "^Working.*\(([0-9]{1,3})\%.*\)")
                        $matchmsg = ($condition['message'] | Select-String -AllMatches -Pattern "^(Working.*)\:.*")

                        $progressMsg = $matchmsg.Matches.Groups[1].Value
                        $progressPercent = $matchper.Matches.Groups[1].Value

                        Write-Progress -Id 111 -Status "$progressPercent% Complete - $($progressMsg)" -Activity "Install" -PercentComplete $progressPercent
                        continue
                    }
                }
                "Available" {
                    if ($condition['status'] -eq "True") {
                        Write-Progress -Id 111 -Activity "Install" -Status "Completed" -PercentComplete 100
                        break installcomplete
                    }
                    continue
                }
                Default { continue }
            }
        }
    }
    catch {}
}

Get-Job | Remove-Job -Force:$true -Confirm:$false


Write-Output "Install Complete!"
