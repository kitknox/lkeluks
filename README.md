# lkeluks
Automatically convert LKE worker nodes into a LUKS encrypted root filesystem with Tang/Clevis Unlocking

*Warning: This is an unofficial capability that is not currently a supported use case by Linode.  Use at your own risk*

Node pool must be provisioned with a large secondary custom disk and the main boot disk at the minimum 15GB size.  This can only be provisioned usin the Linode API.  Example:

```
$ linode-cli lke pool-create --count 1 --type g6-standard-4 --disks '[{"size": 148840,"type": "raw"}]' <LKE_clusterID>
```

To apply to your LKE cluster:

```
kubectl apply -f daemonset-lke-luks.yaml
```

DaemonSet will :
* Updated base Debian 11 packages
* Changes TCP congestion control to BBR
* Increase eth0 NIC queue to max allowed
* One node at a time drain, convert to LUKS, reboot, uncordon, and then wipe original in the clear disk.
* Nodes are then labeled with luks=enabled allowing you to schedule work only on workers that have been secured.

To determine which nodes have been secured :

```
$ kubectl get nodes -L luks
NAME                           STATUS   ROLES    AGE   VERSION   LUKS
lke75642-117585-63434c5cc0b2   Ready    <none>   43h   v1.23.6   enabled
lke75642-117585-6343753083ed   Ready    <none>   41h   v1.23.6   enabled
lke75642-117585-63437530ab29   Ready    <none>   41h   v1.23.6   enabled
lke75642-117619-63440cb6e434   Ready    <none>   30h   v1.23.6   enabled
lke75642-117619-6345a0727229   Ready    <none>   12m   v1.23.6   enabled
lke75642-117619-6345b080de99   Ready    <none>   48m   v1.23.6   enabled
lke75642-117619-6345b62e9f08   Ready    <none>   23m   v1.23.6   enabled
lke75642-117619-6345b62eca30   Ready    <none>   24m   v1.23.6   enabled
lke75642-117619-6345b62eef86   Ready    <none>   23m   v1.23.6   enabled
```

To change any of the behavior including the TANG server URL you must fork this repo, modify the setup script, and point the DaemonSet at the new URL with your customized version.
