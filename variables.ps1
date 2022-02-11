$clustername = "jcallen2"
$version = "4.9"
$vcenter = "vcs8e-vc.ocp2.dev.cluster.com"
$portgroup = "ocp-ci-seg-1"
$datastore = "workload_share_vcs8eworkload_lrFsW"
$datacenter = "IBMCloud"
$cluster = "vcs-8e-workload"
$username = ""
$basedomain = "vmc.devcluster.openshift.com"

# trying to make this as simple as possible
# will reuse IPIs haproxy, keepalived
# then we can simply use DHCP.
$apivip = "192.168.1.10"
$ingressvip = "192.168.1.11"

$sshkeypath = "/home/jcallen/.ssh/id_rsa.pub"
$vcentercredpath = "secrets/ci-ibm-creds.xml"
$password = ''
$apivip = "192.168.1.10"
$ingressvip = "192.168.1.11"

$pullsecret = @"
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

#$virtualmachines =@"
#{
#    "virtualmachines": {
#        "bootstrap": {
#            "server": "10.93.120.67",
#            "datacenter": "DC1",
#            "cluster": "DC1_C1",
#            "network": "10-5-132-0-25",
#            "datastore": "DC1_DS1",
#            "type": "bootstrap"
#        },
#        "master-0": {
#            "server": "10.93.120.67",
#            "datacenter": "DC2",
#            "cluster": "DC2_C1",
#            "network": "10-5-132-0-25",
#            "datastore": "DC2_DS1",
#            "type": "master"
#        },
#        "master-1": {
#            "server": "10.93.120.67",
#            "datacenter": "DC2",
#            "cluster": "DC2_C2",
#            "network": "10-5-132-0-25",
#            "datastore": "DC2_DS2",
#            "type": "master"
#        },
#        "master-2": {
#            "server": "10.93.120.68",
#            "datacenter": "DC3",
#            "cluster": "DC3_C1",
#            "network": "10-5-132-0-25",
#            "datastore": "DC3_DS1",
#            "type": "master"
#        }
#    }
#}
#"@
