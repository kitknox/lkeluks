# lkeluks
Automatically convert LKE worker nodes into a LUKS encrypted root filesystem with Tang/Clevis Unlocking

Node pool must be provisioned with a large secondary custom disk and the main boot disk at the minimum 15GB size.  This can only be provisioned usin the Linode API.  Example:

```
$ linode-cli lke pool-create --count 1 --type g6-standard-4 --disks '[{"size": 148840,"type": "raw"}]' <LKE_clusterID>
```

To apply to your LKE cluster:

```
kubectl apply -f daemonset-lks-luks.yaml
```

DaemonSet will :
* Updated base Debian 11 packages
* Changed TCP congestion control to BBR
* Increase eth0 NIC queue to max allowed
* One node at a time drain, convert to LUKS, reboot, uncordon, and then wipe original in the clear disk.
* Nodes are then labeled with luks=enabled allowing you to schedule work only on workers that have been secured.
