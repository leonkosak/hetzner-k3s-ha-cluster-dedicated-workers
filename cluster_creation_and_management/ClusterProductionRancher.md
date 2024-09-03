# General recommendations when creating Production-ready, HA cluster for Rancher

**Using dedicated cluster outside production (and other) clusters for hosting management tools it's always a good idea.**

Creating production-ready, HA cluster for Rancher on Hetzner is possible using Kube-Hetzner project with settings in ```kube.tf``` file.\
Look at ```kube.tf.example``` file for properties like ```enable_rancher```, and other ones which start with ```rancher_```.

**When hosting cluster even for management tools, use external managed HA database (preferred Postgres) for cluster storage with all advised setting described in [General recommendations for establishing HA cluster on Hetzner](/prerequirements_and_recommendations/KubeHetzner.md).**

**For Rancher, it's recommended using MySQL database (on managed HA service) which is tested the most.**

**Management tools for clusters usually do not require high hardware resources nor huge amounts of high speed storage. Therefore, using only VMs for cluster nodes are more than enough for hosting Rancher in production.**

**Using backup solution (e.g. Velero) for backing up and restoring management cluster is also highly recommended.**\
How to install and configure Velero inside cluster is written in separated article (link is provided in this article).

# How to establish production-ready, HA cluster on Hetzner using Kube-Hetzner
TODO