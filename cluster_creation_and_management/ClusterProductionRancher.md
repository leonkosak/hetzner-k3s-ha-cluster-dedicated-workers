# General recommendations when creating Production-ready, HA cluster for Rancher

**Using dedicated cluster outside production (and other) clusters for hosting management tools it's always a good idea.**

Creating production-ready, HA cluster for Rancher on Hetzner is possible using Kube-Hetzner project with settings in ```kube.tf``` file.\
Look at ```kube.tf.example``` file for properties like ```enable_rancher```, and other ones which start with ```rancher_```.

**When hosting cluster even for management tools, follow [General recommendations for establishing HA cluster on Hetzner](/prerequirements_and_recommendations/KubeHetzner.md).**

**For Rancher, it's recommended using MySQL database (on managed HA service) which is tested the most.**

**Management tools for clusters usually do not require high hardware resources nor huge amounts of high speed storage. Therefore, using only VMs for cluster nodes are more than enough for hosting Rancher in production.**

**Using backup solution (e.g. Velero) for backing up and restoring management cluster is also highly recommended.**\
How to install and configure Velero inside cluster is written in separated article (link is provided in this article).

<hr />

**Optional: Replace MicroOS nodes whith Elemental.**<br />
Get most from Rancher in combination with Elemental.<br />
<u>It's highly recommended that node operating systems are replaced with Elemental in the early stages of creating management cluster with Rancher to prevent potential issues and outages in real production.</u>