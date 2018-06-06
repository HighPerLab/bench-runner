Bench-Runner
============

A SLURM-centric set of scripts that provide a consistent and manageable
framework for run benchmarks (and other applications) on HPC systems.

About
-----

For my work I tend to have to run a variety of benchmarks on a SLURM based
cluster of computers. I need to run the benchmarks multiple times with
different compile-time parameters, different input, and on different
bits of hardware (e.g. GPUs). So far most of the time I have relied on
ad-hoc solutions to achieve this. This work makes use of a lot of the
stuff I have learned along the way.

**These scripts and templates are very alpha-stage - they work for me
though. You have been WARNED**

General Layout
--------------

The underlying concept for how my framework is this:

- we encode within a _profile_ the basic attributes of the benchmark,
  such as source files, compilation flags, etc. An example of such
  a profile file is provided (further examples can be see in my other
  [repo][1]. The repo is a bit of a mess as I am using to store data
  as well).
- profiles have two _modes_ of operation, which affects how the script
  actually works. In mode `MANUAL` the user is asked to define a `build`
  and `run` function which are used directly in the batch script. In mode
  `AUTO` we use a default `build` and `run` functions.
- the batch script file is based upon a template script file,
  `run.sh.template` which includes a host of functions including default
  a `build` function and a `run` function.
- we then use the `generate.sh` script to generate a batch script file
  (which include SLURM `sbatch` style comment pragmas) which encodes
  the _profile_ in a series of stages. These stage _copy_ the source
  files and input files to a temporary directory, _compile_ the source
  files with the various compilation flags, _run_ the binaries with
  the various input files/parameters, and finally _archives_ all the
  generated log output and stored this on a shared partition (we delete
  the temporary directory.

External Resources
------------------

For system information I use the [ixni][10] tool, as it provides a
rich amount of detail concisely.

[1]: https://www.macs.hw.ac.uk/gitlab/hans/benchmark-profiles
[10]: https://github.com/smxi/inxi
