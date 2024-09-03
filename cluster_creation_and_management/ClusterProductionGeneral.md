# Important decision when making production-ready, HA cluster on Hetzner using Kube-Hetzner
The most important decision when creation new production-ready HA cluster on Hetzner is requirement for larger amounts of local, low-latency fast storage (e.g. NVMe).
This decision should be carefully chosen in advance and should be future-proof for such cluster.

1) If there is no requirement (<u>and there will never be!</u>) for large amounts of fast (local) storage, the following advantages for hosting and creating cluster are given:

- fully-automated creation and also upgradability of production-ready cluster using Kube-Hetzner (master and worker nodes)
- cheaper hosting (using shared infrastructure - VMs and Hetzner Volumea)

---

2) There is requirement (<u>or it will be in the future with high possibility</u>) for having large amounts of fast, low-latency storage, the following disadvantages appear:

- worker nodes should not be created and modified automatically via Terraform\
Each worker node (dedicated server or VM) should be created manually and added to cluster.
- Dedicated servers have worse price/performance ratio compared to VMs (shared infrastructure)

However, there are also advantages going semi-automated way when creating cluster on Hetzner:

- Kube-Hetzner is still used for creating master nodes (planes) with all required networking,...
- creating nodes on dedicated server gives additional computing power for havier calculation tasks and on Hetzner still priced well
- ability to have large amounts of local, low-latency, high-bandwidth storage at reasonable price
- attaching lower-performance, but redundant storage - Hetzner Volume to cluster