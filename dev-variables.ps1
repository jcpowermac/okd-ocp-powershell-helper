# Modify these variables below for your environment

$ciTokenUri = "https://oauth-openshift.apps.ci.l2s4.p1.openshiftapps.com/oauth/token/request"
$ciApiUri = "https://api.ci.l2s4.p1.openshiftapps.com:6443"

# Find release stream here
# https://amd64.origin.releases.ci.openshift.org/
# https://amd64.ocp.releases.ci.openshift.org/
# The latest will be used.
$releaseStream = "4.13.0-0.nightly"
$project = "ocp" # this should be origin or ocp

# https://mirror.openshift.com/pub/openshift-v4/clients/ocp/
$ocClientVersion = "stable-4.12"


$ciRegistryAuthFile = "secrets/ci.json"
$pullSecretFile = "secrets/pull-secret.json"


$clustername = "jcallen2"
$basedomain = "vmc.devcluster.openshift.com"
$sshkeypath = "/home/jcallen/.ssh/openshift-dev.pub"
# trying to make this as simple as possible
# will reuse IPIs haproxy, keepalived
# then we can simply use DHCP.
$apivip = "192.168.10.4"
$ingressvip = "192.168.10.5"

# vCenter variables
$vcenter = "ibmvcenter.vmc-ci.devcluster.openshift.com"
$username = "administrator@vsphere.local"
$password = ''

$hardwareVersion = 18

$datacenters = @("IBMCloud","datacenter-2")
$masterZones = @("us-east-1","us-east-2", "us-east-3")
$workerZones = @("us-east-2","us-east-3", "us-west-1")

$datacentersString = ConvertTo-Json $datacenters
$masterZonesString = ConvertTo-Json $masterZones 
$workerZonesString = ConvertTo-Json $workerZones 

$vcentercredpath = "secrets/vcenter-creds.xml"



$vcenterJson = @"
[{
"server": "$($vcenter)",
"user": "$($username)",
"password": "$($password)",
"datacenters": $($datacentersString) 
}]
"@
$failureDomainJson = @"
[
{
"name": "us-east-1",
"region": "us-east",
"zone": "us-east-1a",
"server": "$($vcenter)",
"topology": 
{
"datacenter": "IBMCloud",
"computeCluster": "/IBMCloud/host/vcs-mdcnc-workload-1",
"networks": ["ocp-ci-seg-10"],
"datastore": "/IBMCloud/datastore/mdcnc-ds-1"
}
},
{
"name": "us-east-2",
"region": "us-east",
"zone": "us-east-2a",
"server": "$($vcenter)",
"topology": 
{
"datacenter": "IBMCloud",
"computeCluster": "/IBMCloud/host/vcs-mdcnc-workload-2",
"networks": ["ocp-ci-seg-10"],
"datastore": "/IBMCloud/datastore/mdcnc-ds-2"
}
},
{
"name": "us-east-3",
"region": "us-east",
"zone": "us-east-3a",
"server": "$($vcenter)",
"topology": 
{
"datacenter": "IBMCloud",
"computeCluster": "/IBMCloud/host/vcs-mdcnc-workload-3",
"networks": ["ocp-ci-seg-10"],
"datastore": "/IBMCloud/datastore/mdcnc-ds-3"
}
},
{
"name": "us-west-1",
"region": "us-west",
"zone": "us-west-1a",
"server": "$($vcenter)",
"topology": 
{
"datacenter": "datacenter-2",
"computeCluster": "/datacenter-2/host/vcs-mdcnc-workload-4",
"networks": ["ocp-ci-seg-10"],
"datastore": "/datacenter-2/datastore/mdcnc-ds-4"
}
},
]
"@

$installconfig = @"
{
  "apiVersion": "v1",
  "baseDomain": "domain",
  "metadata": {
    "name": "cluster"
  },
  "networking": {
	  "networkType": "OpenShiftSDN",
    "machineNetwork":[{
      "cidr": "192.168.10.0/24"
  }],
},
  "controlPlane": {
  "name": "master",
  "replicas": 3,
  "platform": {
    "vsphere": {
      "zones": $($masterZonesString) 
    }
  }
},
"compute": [{
  "name": "worker",
  "replicas": 3,
  "platform": {
    "vsphere": {
    "zones": $($workerZonesString) 
    }
  }
}],
  "platform": {
    "vsphere": {
      "vcenters": $($vcenterJson), 
      "failureDomains": $($failureDomainJson), 
      "apiVIP": "ipaddr",
      "ingressVIP": "ipaddr"
    }
  },
  "pullSecret": "",
  "sshKey": ""
}
"@

$okdPullSecret = @"
{"auths":{"fake":{"auth":"aWQ6cGFzcwo="}}}
"@

$failureDomainMap = @{}
ConvertFrom-Json $failureDomainJson | ForEach-Object -Process {
  $failureDomainMap.add($_.name, $_)
}
