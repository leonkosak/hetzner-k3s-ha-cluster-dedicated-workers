# Build a production-ready, upgradable, future-proof, Highly Available k3s cluster on Hetzner with dedicated worker servers (and VMs)

This article shows how to build enterprise-grade, production-ready, highly-availyble, future-proof (upgradable) k3s cluster on Hetzner cloud provider.

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