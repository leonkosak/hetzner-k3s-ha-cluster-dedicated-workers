- Use external database (Postgres is preferred) for cluster (managed, HA) instead of etcd.\
Set the following setting (```additional_k3s_environment```) in ```kube.tf``` (and look ```kube.tf.example```)
```
additional_k3s_environment = {
    K3S_DATASTORE_ENDPOINT = "postgres://neondb_owner:xxx@xxxx.eu-central-1.aws.neon.tech:5432/management?sslmode=require"
}
```
Parameter ```K3S_DATASTORE_ENDPOINT``` for setting connection string to database for cluster is currently not mentioned in Kube-Hetzner documentation yet.

- Don't mix regions when using more than one control plane vm. The loadbalancers are single-region only and if there's a failure in that region your mult-region setup won't do anything so it's effectively useless.

- Do not use etcd, ESPECIALLY when using private networking. It's not going to end well.

- Choose k3s over RKE2. RKE2 is fantastic and proven better in many segments (security,...), but there is no [KINE](https://github.com/k3s-io/kine) support and you will really want this when running a cluster on top of Hetzner cloud.

- Do NOT enable automatic updates (for OS and for k3s). This is your own personal choice of course but it's highly recommended to update cluster manually. [The following settings are mentioned in Kube-Hetzner documentation](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner#turning-off-automatic-upgrades).

Set the following settings in ```kube.tf``` (and look ```kube.tf.example```)
```
automatically_upgrade_os = false
```
Alternatively ssh into each node and issue the following command:
```
systemctl --now disable transactional-update.timer
```
If you wish to turn off automatic k3s upgrades, you need to set:
```
automatically_upgrade_k3s = false
```

Once disabled this way you selectively can enable the upgrade by setting the node label ```k3s_update=true``` and later disable it by removing the label or set it to ```false``` again.
```
# Enable upgrade for a node (use --all for all nodes)
kubectl label --overwrite node <node-name> k3s_upgrade=true

# Later disable upgrade by removing the label (use --all for all nodes)
kubectl label node <node-name> k3s_upgrade-
```

Alternatively, you can disable the k3s automatic upgrade without individually editing the labels on the nodes. Instead, you can just delete the two system controller upgrade plans with:
```
kubectl delete plan k3s-agent -n system-upgrade
kubectl delete plan k3s-server -n system-upgrade
```

Also, note that after turning off node upgrades, you will need to manually upgrade the nodes when needed. You can do so by SSH'ing into each node and running the following commands (and don't forget to drain the node before with ```kubectl drain <node-name>```):
```
systemctl start transactional-update.service
reboot
```