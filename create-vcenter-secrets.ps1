#!/usr/bin/pwsh

md /projects/secrets/

Get-Credential | Export-Clixml /projects/secrets/vcenter.clixml
