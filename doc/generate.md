Name
----

generate - generate a SLURM-compatible script from a bench-runner profile

Synopsis
--------

generate [-h|-f|-v...] [-T target] [-V variant] [-d directory]

Description
-----------

A bench-runner profile encodes basic data on how to compile and run a given
piece of source code. The general formatting of a profile can be found in
the specific documentation file.

`generate` reads the profile, and given a template, generates a script that
can be run through SLURM.

Options
-------

    -h         print usage message and exit
    -f         force; overwrite existing scripts
    -v...      increase verbosity (can be given multiple times)
    -T target  specify which targets to encode (overrides profile); can be given
               multiple times
    -V variant specify which variants to encode (overrides profile) can be given
               multiple times
    -d dir     specify directory where to read bench-runner profile files from,
               otherwise look in current working directory

Author
------

Hans-Nikolai Viessmann <hans AT viess.mn>
