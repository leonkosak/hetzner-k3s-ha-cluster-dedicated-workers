# Build a production-ready, upgradable, future-proof, Highly Available k3s cluster on Hetzner with dedicated worker servers (and VMs)

This article shows how to build enterprise-grade, production-ready, highly-availyble, future-proof (upgradable) k3s cluster on Hetzner cloud provider.\
It's based on **Kube-Hetzner** project with some changes, which cannot be fully automated but are usually required in production-ready cluster.

## FAQ
### What makes described installation of cluster enterprise-grade, production-ready and future-proof?
The whole technology stack is based on software ecosystem from company **[SUSE](https://www.suse.com/)**.\
SUSE is actively developing all software components (operating systems, tools,...) described in this article.

### Why would you use technology stack that is mentioned in this article?
Because technology stack from SUSE is **opensource**, **complete**, **actively maintained** with the strong company behind.\
Using described technology stack gives independency of underlying hosting platform (cloud provider, hypervisor type 1 on dedicated server,...).

### Why Hetzner is a great choice for establishing such environment?
Hetzner shines in the following areas:
- unbeatable price/performance ratio for compute and storage resources (shared infrastructure is also pretty fast)
- reliable with high uptime
- excellent customer support (fast, informative and in case of incidents - they are resolved fast most of the time)
- "DIY-yourself-first" approach of infrastructure in the first place (which highly affects costs)
- known and strong company with long history in server and datacenter industry
- datacenters in multiple regions over the world
- dedicated servers and shared infrastructire (VMs) with variety of predefined and custom options (extensibility and replaceability of hardware,...)

### Is Hetzner supported by Rancher management system?
As of Rancher v2.9.x (starting August 2024), there is no support for creating (provisioning) of clusters from Rancher on Hetzner.\
However, this might change in the future.

### Why hosting for Rancher on Hetzner is a good idea?

Hosting HA cluster with Rancher only on Hetzner has the following advantages:

- one of the cheapest options to establish and host HA cluster (which is recommended to have production-ready instance of Rancher)
- shared infrastructure is fast enough
- Provisioning and management of k3s or RKE2 clusters from Rancher on other cloud providers (e.g. Digital Ocean) is also possible

### Why Kube-Hetzner project is not good enough for creating real production-ready clusters on Hetzner?
Kube-Hetzner obviously creates production-ready clusters without any doubt. The problem starts to show when **a lot of fast storage is required**.

Local storage in VM on Hetzner is fast but it cannot be extended over default size. Even the most poverful VM options could have pretty limited size of local storage.\
Therefore, cases for using fast storage (e.g. hosting databases) with decent sizes are mandatory.\
[Hetzner Volumes](https://docs.hetzner.com/cloud/volumes/overview/) (network block storage) which can be appended to VMs or clusters is appealing option because of HA by default and much larger sizes than local storage on VMs, but the performance (especially latency) is not so great (because of network - underlying storage technology is still very fast (NVMe drives)).

Using Hetzner Volumes for hosting databases is possible in good enough for small databases with light queries and not too many requests.

The only option for having a lot of fast (and low-latency) storage is dedicated server (optionally with additional payment for larger drives).

The second reason could be that dedicated servers for worker nodes in cluster are computationally more performant than VMs. This is maybe less relevant for most clusters (even production-grade) if there is no high demanding processing tasks on application layer.

### Why not to create cluster with Kube-Hetzner and use dedicated servers (e.g. for hosting databases) outside cluster?
This scenario is certainly possible and maybe even recommended if processing tasks on databases are intensive.\
However, having databases on one server does not mean that you HA can be ensured. Establishing HA cluster on database level (multiple servers) is usually noticeable harder to implement compared to database operators in containerized environment.

Having databases inside containerized environment using operators usually means less complicated way to establish HA on database level (especially for [CloudNativePG](https://cloudnative-pg.io/) operator - Postgres).\
For most scenarios, databases inside containers with proper and automated backup are reliable option nowadays.

Also - having all components inside containerized environment streamlines processes, monitoring, alerting and more.


### RKE2 is preferred option compared to k3s (security reasons,...) - why create k3s cluster and not RKE2?
Some people reported issues with etcd over some time running clusters on Hetzner ([reddit discussion](https://www.reddit.com/r/hetzner/comments/1cwgg7l/ha_k3s_or_rke2_cluster_with_rancher_management_on/)) and not when using reliable managed external DB.\
Using database for cluster storage is only possible for k3s and not RKE2.

Using database for cluster storage has also advantage of simplicity.

**It is important to use HA database for cluster storage to ensure HA for cluster.**

There are many reliable managed services for hosting databases (like [Aiven](https://aiven.io/)) with free tier to start with.


### What could production-ready cluster look like on Hetzner?
The base could always be created with Kube-Hetzner with highly-optimized defaults and networking.\
There is no need in most cases that master nodes (control planes) should be installed on dedicated servers.

For worker nodes, the following combinations are possible:

- only VMs are needed (and will be also in the future)\
If there is no need for large amounts of fast storage and/or intensive computation power, using fully automated Kube-Hetzner is the best option to create HA production-ready cluster.

- Large amounts of fast storage is required and/or high processing power
Creating the base for cluster (master nodes with networking) with Kube-Hetzner and then setting worker pool nodes to 0.
Master nodes can be modified (number of nodes or more powerfull nodes) via Kube-Hetzner (Terraform) and worker nodes should be created and added to cluster manually.\
Worker nodes can be only dedicated servers or mixed (dedicated servers and VMs).\
To achieve HA for fast storage in the cluster, at least three dedicated servers should be added to worker nodes.\
Adding VMs to worker nodes usually means adding more price/performance-oriented compute power to the cluster.\
One possible scenario is to have three dedicated servers with desired amount of fast local storage and minimal compute resources and then VMs for processing power.\
Hetzner Volume can also be added to the cluster for less-performant HA storage (e.g. filesystem).


### Should cluster with Rancher be standalone or inside actual cluster itself?
It is recommended that dedicated cluster for Rancher is created with Kube-Hetzner (by default, Rancher installation inside cluster is disabled) and other clusters are imported or created with Rancher.



## Table of Contents
**Prerequirements & Recommendations**
- Recommendations
  - [General](/prerequirements_and_recommendations/General.md)
  - [Kube-Hetzner](/prerequirements_and_recommendations/KubeHetzner.md)

**Cluster creation and management**
- [Cluster (HA, production-ready) for Rancher (Management cluster)](/cluster_creation_and_management/ClusterProductionRancher.md)
- [Production-ready cluster](/cluster_creation_and_management/ClusterProductionGeneral.md)
  - [VMs-only cluster]()
  - [Mixed clusters (dedicated servers and VMs)]()
    - [Create, prepare and add dedicated server worker node to cluster]()
    - [Create, prepare and add VM worker node to cluster]()
- [Import Kube-Hetzner-created cluster to Rancher]()

**Cluster Backup & Restore**
- [Velero]() #Link to: /leonkosak/establish-ha-software-components-containerized-environment to exact location

**Security**
- [Access to Rancher]()

**Upgrading - cluster components**
- [Upgrading node OS (MicroOS)]()
- [Upgrading Rancher]()

**Upgrading - hardware layer**
- [Scale-up: master nodes]()
- [Scale-up: worker nodes]()
  - [dedicated server]()
  - [VM]()
- [Upgrading storage: dedicated server]()
- [Upgrading storage: Hetzner Volume]()

**Troubleshooting**
- [Cluster issues (running)]()


## Special Thanks
The beginning of writing this article would not have been possible without the help of software engineers and enthusiasts from Slovenia:

- Mitja Gros
- Leon Košak
- Aleš Pestotnik
- Luka Gričar

## Honorable mention
The most important project, which is the hearth of everything is **[Kube-Hetzner](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner)**.\
This project creates highly optimized HA k3s cluster on Hetzner environment.

## Support and Contribution
The original authors of this article would be highly grateful for additional contributions that would further improve the establishment, maintenance, and upgradability of such clusters.