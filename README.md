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

**Also the scripts are tightly coupled to the [SaC compiler][3] so
some parts might need changing to make it truly generic.**

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

Documentation
-------------

Documentation of some of the scripts (and their internals) can be found
under the `doc/` directory. This is written in [scdoc][5] format, and so
can be generated into manpages if desired.

External Resources
------------------

For system information I use the [ixni][10] tool, as it provides a
rich amount of detail concisely.

The default template makes use of [environment-module][11] to expose
some of the underlying binaries that are used. If your system/cluster
does not use this, don't forget to remove/edit them.

Ideas
-----

- In short, BASH is really not the best way of doing this. My initial
  plan for the whole system was very minimal, but as time has
  progressed, I find that I need/want to do more advanced things but
  am strongly limited by what BASH is capable of doing. I have already
  worked on a basic implementation in Python, which among other things
  seriously improves upon how profiles are decoded.
- The profile format is very restrictive (understandably) but not in the
  right way - for instance defining functions is pretty nasty. Clearly
  I could go and try something like a PKGBUILD-style file (as used by
  the ArchLinux community) which in essences is a script that is sourced
  and run directly. This needs a lot of boiler plating around this though
  to make sure its **safe** - `makepkg` script (which is BASH, but uses
  a lot of external tools) has about 500+ lines of commands designed to
  sanities the PKGBUILD file before running anything, and even then it
  is assumed that is isn't safe, so everything is run within a fakeroot
  and its own environment. I'm not sure I want to implement 500+ lines
  of code just so I have a more free-form profile format.

[1]: https://www.macs.hw.ac.uk/gitlab/hans/benchmark-profiles
[3]: https://www.sac-home.org/
[5]: https://git.sr.ht/~sircmpwn/scdoc
[10]: https://github.com/smxi/inxi
[11]: http://modules.sourceforge.net/
