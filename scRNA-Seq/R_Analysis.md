---
title: R Analysis
layout: page
permalink: /scRNA-Seq/R_Analysis
---

Copy the tarball containing analysis results to your local machine.

```
/data/containers/seurat.tar.gz
```

Using `scp`, transfer the file to your own bactsrv account:

```bash
scp seurat.tar.gz USERNAME@bactsrv.nuigalway.ie:/home/USERNAME
```

Close the connection to lugh and move to your local machine. Create a directory in your home directory and move there:

```bash
mkdir ~/scRNA-Seq/
cd ~/scRNA-Seq
```

Now download the tar file and unzip it.

```bash
scp USERNAME@bactsrv.nuigalway.ie:/home/USERNAME/seurat.tar.gz ./ && tar -xvf seurat.tar.gz
```
