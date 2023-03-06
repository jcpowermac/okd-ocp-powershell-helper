#!/usr/bin/pwsh

. .\dev-variables.ps1

$ErrorActionPreference = "Stop"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue

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

    $token = Read-Host -Prompt "Token from:`n$($ciTokenUri)" -MaskInput

    # TODO: Change to start-process
    $loginProcess = start-process -PassThru -Wait -FilePath ./bin/oc -argumentlist @("login", "--token", "$($token)", "--server", "$($ciApiUri)")
    if($loginProcess.ExitCode -ne 0) {
        $loginProcess.StandardError
        Exit $loginProcess.ExitCode
    }
    $registryLoginProcess = start-process -PassThru -Wait -FilePath ./bin/oc -argumentlist @("registry", "login", "--to", "$($ciRegistryAuthFile)")
    if($registryLoginProcess.ExitCode -ne 0) {
        $registryLoginProcess.StandardError
        Exit $registryLoginProcess.ExitCode
    }

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

    $releaseExtractProcess = start-process -PassThru -Wait -FilePath ./bin/oc -argumentlist @("adm", "release", "extract", "--tools", "$($releases['pullSpec'])", "--registry-config", "$($pullSecretFile)")
    if($releaseExtractProcess.ExitCode -ne 0) {
        $releaseExtractProcess.StandardError
        Exit $releaseExtractProcess.ExitCode
    }

    Get-Item -Path *.tar.gz | ForEach-Object -Process {
        tar -xvf $_ -C ./bin
    }
    Remove-Item -Path *.tar.gz
    Remove-Item -Path *.txt
}

$pullSecret = ConvertTo-Json $pullSecretHash
$config = ConvertFrom-Json -InputObject $minimalInstallConfig

# Set the install-config.json from upi-variables
$config.metadata.name = $clustername
$config.baseDomain = $basedomain
$config.sshKey = [string](Get-Content -Path $sshkeypath -Raw:$true)
$config.pullSecret = $pullSecret -replace "`n", "" -replace " ", ""

# Write out the install-config.yaml (really json)
$config | ConvertTo-Json -Depth 8 | Out-File -FilePath ./secrets/install-config.yaml -Force:$true
