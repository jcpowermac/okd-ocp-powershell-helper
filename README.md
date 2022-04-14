# openshift-upi-powercli

Yet another way to install OpenShift or OKD but this time with
PowerShell and PowerCLI

## Installing

### Prerequisites

- PowerShell
- PowerCLI: `Install-Module VMware.PowerCLI`

### Credentials

Use the following PowerShell commands to create the credentials
xml file. This will be used in `Connect-VIServer`.

```powershell
Get-Credential | Export-Clixml secrets/vcenter-creds.xml
```
### Variables

Modify `variables.ps1` for your environment specifically the following:

#### Openshift/OKD variables
- Version: `$version = "4.9"`
- Cluster name: `$clustername = "clustername"`
- Base Domain name: `$basedomain = "openshift.com"`
- Path to sshkey: `$sshkeypath = "/home/user/.ssh/id_rsa.pub"`
- API VIP Address: `$apivip = "192.168.1.10"`
- Ingress VIP Address: `$ingressvip = "192.168.1.11"`

#### vCenter variables
- URL: `$vcenter = "vcenter"`
- Username: `$username = "administrator@vsphere.local"`
- Password: `$password = ''`
- Portgroup: `$portgroup = "vlan9999"`
- Datastore: `$datastore = "Workload-Datastore"`
- Datacenter `$datacenter = "SDDC-Datacenter"`
- Cluster: `$cluster = "Cluster-1"`
- PowerClI credentials path: `$vcentercredpath = "secrets/vcenter-creds.xml"`

### Execute

```
PS /openshift-upi-powercli> ./upi.ps1
```

