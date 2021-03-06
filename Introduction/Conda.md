---
title:
layout: page
permalink: /Introduction/Conda
---

<center>
<img src="https://raw.githubusercontent.com/BarryDigby/BarryDigby.github.io/master/_images/week1/anaconda_horizontal.png" width="100%" height="100%"/>
</center>

Conda quickly installs, runs and updates packages and their dependencies. Conda can create and switch between environments on your computer, resolving dependency conflicts that might arise due to package requirements.

Jump to:
- [Install Packages](#install)
- [YAML file](#yaml)

# Install Packages {#install}
***
Let's first activate the base environment for conda:

```bash
conda activate base
```

You should see the `(base)` prefix before your username on the terminal.

Now let's install the package `fastqc`. First, look up the package in the Anaconda repository: [https://anaconda.org/bioconda/fastqc](https://anaconda.org/bioconda/fastqc).

```bash
conda install -c bioconda fastqc
```

*or*

```bash
conda install bioconda::fastqc
```

If we wanted to specify the version of the tool, we can 'pin' the version in the install command:

```bash
conda install bioconda::fastqc=0.11.9
```

### To Do:
1. Check that `fastqc` has been installed correctly by prompting the help message.
2. Check where `fastqc` was installed (hint: use `whereis`).

# YAML file {#yaml}
***
We have seen how simple it is to install tools using the `conda install` command.

In reality, we will want to install multiple packages at once for an analysis and create a clean environment for the packages. This can be simplified using a `.yml` file. The strucutre of a `.yml` file is:

1. Name: The name of the environment to be created.
2. Channels: Specifiy which channels conda should search when attempting to install packages.
3. Dependencies: Which packages you want to install (supports pinned version numbers).

In this weeks tutorial we want to create an environment for the quality control of sequencing reads. We will need `fastqc` and `multiqc` to generate HTML reports of sequencing statistics and a tool to perform adapter trimming and read filtering.

Choosing a trimming tool is highly subjective however, I like the flexibility of `bbduk`, part of the `bbtools` suite.

Please save the below block as `week1.yml`. 

```
name: QC
channels:
  - agbiome
  - bioconda
  - conda-forge
  - defaults
dependencies:
  - fastqc
  - multiqc
  - bbtools
```

To create a conda environment using the `.yml` file, run the following command in the terminal:

```bash
conda env create -f week1.yml && conda clean -a
```

Conda should install the three packages under the environment `QC`.

### To Do:
1. Activate the environment.
2. Check all 3 tools have been installed correctly.
3. Print the path of the environments bin.
4. Export the environment using `conda env export > QC.yml`.
