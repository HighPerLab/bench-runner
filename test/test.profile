# This is a basic profile file which describes how to build/run
# a benchmark

# It is made up of KEY='value' pairs and comments.
# Comments are given by the hash (#) symbol which you can override
# with \# if you need to.

# Any key can be added here and it will appear in the generated
# script file. The following keys though have special meanings and
# are treated differently from any other key:

BENCHSUITE='test'
BENCHNAME='1'
#MODE='AUTO'      # optional, choices: AUTO, MANUAL; default is AUTO
COMPILER='sac2c' # set the compiler to use
#TIMELIMIT='40'   # optional, set SLURM time limit; default is 60 minutes
SOURCES=('test/test.sac')
INPUTS=('test/test.inp') # optional, if give all data is copied to temp
TARGETS=('seq' 'mt_pth' 'cuda')  # optional, defaults to TARGETS = ('seq')
#VARIENTS=('default') # optional, defaults to VARIENTS = ('default')
BUILDFLAGS=('-v2 -g') # is converted to BUILDFLAGS_default
                  #  or BUILDFLAGS_varient = ()
#RUNFLAGS=        # optional
STDINS='test.inp' # optional

# when we build with MANUAL we *must* define BUILD and RUN
# functions (in AUTO these are ignored and not placed into
# the sbatch script). These keys-values represent the body of
# generated functions `build' and `run'. Newlines are given by
# the backslash '\'.

BUILD='\
this is a line;\
this to'
RUN='\
wow bang boom'
