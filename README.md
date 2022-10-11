# lkeluks
Automatically convert LKE worker nodes into a LUKS encrypted root filesystem with Tang/Clevis Unlocking

Node pool must be provisioned with a large secondary custom disk and the main boot disk at the minimum 15GB size.  This can only be provisioned usin the Linode API.  Example:

```
$ linode-cli lke pool-create --count 1 --type g6-standard-4 --disks '[{"size": 148840,"type": "raw"}]' <LKE_clusterID>
```
