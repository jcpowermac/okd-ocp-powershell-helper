# Modify these variables below for your environment
# OKD variables
# OKD version to be installed
$version = "4.9"
$clustername = "jcallen2"
$basedomain = "vmc.devcluster.openshift.com"
$sshkeypath = "/home/jcallen/.ssh/id_rsa.pub"
# trying to make this as simple as possible
# will reuse IPIs haproxy, keepalived
# then we can simply use DHCP.
$apivip = "192.168.1.10"
$ingressvip = "192.168.1.11"


# vCenter variables
$vcenter = "vcs8e-vc.ocp2.dev.cluster.com"
$username = ""
$password = ''
$portgroup = "ocp-ci-seg-1"
$datastore = "workload_share_vcs8eworkload_lrFsW"
$datacenter = "IBMCloud"
$cluster = "vcs-8e-workload"
$vcentercredpath = "secrets/vcenter-creds.xml"

$pullsecret = @"
{"auths":{"fake":{"auth":"aWQ6cGFzcwo="}}}
"@

$virtualmachines =@"
{
    "virtualmachines": {
        "bootstrap": {
            "server": "$($vcenter)",
            "datacenter": "$($datacenter)",
            "cluster": "$($cluster)",
            "network": "$($portgroup)",
            "datastore": "$($datastore)",
            "type": "bootstrap"
        },
        "master-0": {
            "server": "$($vcenter)",
            "datacenter": "$($datacenter)",
            "cluster": "$($cluster)",
            "network": "$($portgroup)",
            "datastore": "$($datastore)",
            "type": "master"
        },
        "master-1": {
            "server": "$($vcenter)",
            "datacenter": "$($datacenter)",
            "cluster": "$($cluster)",
            "network": "$($portgroup)",
            "datastore": "$($datastore)",
            "type": "master"
        },
        "master-2": {
            "type": "master",
            "server": "$($vcenter)",
            "datacenter": "$($datacenter)",
            "cluster": "$($cluster)",
            "network": "$($portgroup)",
            "datastore": "$($datastore)",
        }
    }
}
"@

$installconfig = @"
{
  "apiVersion": "v1",
  "baseDomain": "domain",
  "metadata": {
    "name": "cluster"
  },
  "platform": {
    "vsphere": {
      "vcenter": "vcsa",
      "username": "username",
      "password": "password",
      "datacenter": "dc1",
      "defaultDatastore": "datastore",
      "cluster": "cluster",
      "network": "network",
      "apiVIP": "ipaddr",
      "ingressVIP": "ipaddr"
    }
  },
  "pullSecret": "",
  "sshKey": ""
}
"@
