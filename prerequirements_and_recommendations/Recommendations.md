# Kube-Hetzner and source version control

- It's always recommended that clusters are created with a stable version of Kube-Hetzner and not what's currently on master branch.

- Having a dedicated repository or branch inside one repository inside source version control system (e.g. Git) for each provisioned cluster with Kube-Hetzner is reccomended for transfering future updates of Kube-Hetzner to specific repository/branch.

Example how to make upgrade process easier:

1) Inside repository (or branch) create two folders on top level named:\
   - Infrastructure
   - Upgrade
  
    Inside "Upgrade" folder make subfolders named:\
     - Current
     - New

2) Download compressed file with (latest) stable version of Kube-Hetzner
3) Decompress content of compressed file into "Infrastracture" folder
4) Save compressed file into Upgrade\Current folder

5) Make desired changes for creating particular cluster inside "Infrastructure" folder and provision cluster to Hetzner

6) When a newer version of Kube-Hetzner is available, download compressed file into Upgrade\New folder
7) Decompress compressed files inside Upgrade\New and Upgrade\Current and compare differences with a tool like [WinMerge](https://winmerge.org/).
8) Manually transfer changes to actual project inside "Infrastructure" folder **and make sure that your custom defined values are not accidentally rewritten**.
9) Clear the content of Upgrade\Current folder and copy compressed file with a newer version of Kube-Hetzner inside.
10) Clear the content of Upgrade\New folder
11) Test and commit to source version control system.