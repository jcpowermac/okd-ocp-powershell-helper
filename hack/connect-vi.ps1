#!/bin/pwsh

. ./upi-variables.ps1

Connect-VIServer -Server $vcenter -Credential (Import-Clixml "/projects/secrets/vcenter.clixml")

