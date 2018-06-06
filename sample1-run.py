#!/usr/bin/env python3

#SBATCH --exclusive
#SBATCH --partition amd-longq
#SBATCH --job-name bench-sample1
#SBATCH --time 1:00:00
#SBATCH --gres=gpu:k20:1
#SBATCH --cpus-per-task 2

# Global Config
logger = None
localdir = '/home/hans/git/sac/bench-runner/results'
num_iters = 5

# Bench Config
config = {'benchsuite': 'sample', 'benchname': 'sample1', 'sources': ['source one', 'source two'], 'inputs': ['something.in', 'anotherthing.in:stdin'], 'compiler': '/usr/bin/echo', 'compvars': {'targets': ['seq', '...']}, 'build': 'logger.info("here we can specify almost anything")\nlogger.info("that spans multiple lines")\n\nlogger.info("and that has spaces/newlines")\n', 'run': 'logger.info("another example")\n', 'mode': 'auto', 'email': None, 'threads': 2, 'timelimit': '1:00:00', 'compflags': {'default': '-g -t {targets} -O3'}}

# STDLIB #

import os.path
import platform
import subprocess
import pathlib
import tarfile
import logging
import tempfile
import argparse
import itertools
import shutil
from functools import partial

import cpuinfo
import GPUtil as gputil
import psutil
import distro
import yaml

class MultiLineFormatter(logging.Formatter):
    def format(self, record):
        msg = super(MultiLineFormatter, self).format(record)
        header, footer = msg.split(record.message)
        return msg.replace('\n', '\n' + ' '*len(header))

def bytes2human(n):
    # http://code.activestate.com/recipes/578019
    # >>> bytes2human(10000)
    # '9.8K'
    # >>> bytes2human(100001221)
    # '95.4M'
    symbols = ('K', 'M', 'G', 'T', 'P', 'E', 'Z', 'Y')
    prefix = {}
    for i, s in enumerate(symbols):
        prefix[s] = 1 << (i + 1) * 10
    for s in reversed(symbols):
        if n >= prefix[s]:
            value = float(n) / prefix[s]
            return '%.1f%s' % (value, s)
    return "%sB" % n

def strpairs_to_dict(p):
    out = {}
    for l in p:
        try:
            key, val = l.split(':')
            key, val = key.strip(), val.strip()
            out[key] = val
        except:
            continue

def ntuple_to_str(nt, padding=0):
    out = []
    for name in nt._fields:
        value = getattr(nt, name)
        if name != 'percent':
            value = bytes2human(value)
        out.append('%*s: %7s' % (padding + 10, name.capitalize(), value))
    return '\n'.join(out)

def setup_logger(name, verbosity, tofile=False):
    logger = logging.getLogger(name)
    # we need to change convert to the correct level number
    logger.setLevel(30-(verbosity*10))
    fmt = MultiLineFormatter('[%(asctime)s] %(name)s (%(funcName)16s)[%(levelname)8s]: %(message)s', '%H:%M:%S %d-%m-%y')
    if tofile:
        h = logging.FileHandler(name + '.log')
    else:
        h = logging.StreamHandler()
    h.setFormatter(fmt)
    logger.addHandler(h)
    return logger

def archive_logs(name, workdir, localdir):
    logger.info('Creating TAR archive with all log data')
    tar = pathlib.Path(workdir, name + '.tar')
    local = pathlib.Path(localdir)
    t = tarfile.TarFile(tar, 'w')
    logger.info('Moving TAR achive to localdir...')
    wd = pathlib.Path(workdir)
    for f in wd.glob('*.log'):
        if f.is_file():
            t.add(f.name)
    t.close()
    if not local.is_dir():
        local.mkdir()
    shutil.move(str(tar), str(local))

def print_system_info(compiler, version_flag='--version'):
    comp = subprocess.run([compiler, version_flag], stdout=subprocess.PIPE)
    cc_compiler = subprocess.run(['cc', '--version'], stdout=subprocess.PIPE)
    nvcc_compiler = subprocess.run(['nvcc', '--version'], stdout=subprocess.PIPE)
    cmake = subprocess.run(['cmake', '--version'], stdout=subprocess.PIPE)
    gpus = gputil.getGPUs()
    cpu_info = cpuinfo.get_cpu_info()
    logger.info('''\
General Information:
      OS: {}
  Kernel: {}

Build Tools:
Compiler: {}
      CC: {}
    NVCC: {}
   CMake: {}

Hardware:
     CPU: {}
     RAM: {}
     GPU: {}
'''.format(
    ' - '.join(distro.linux_distribution()),
    platform.release(),
    comp.stdout.decode('utf-8').strip().split('\n')[0],
    cc_compiler.stdout.decode('utf-8').strip().split('\n')[0],
    nvcc_compiler.stdout.decode('utf-8').strip().split('\n')[-1],
    cmake.stdout.decode('utf-8').strip().split('\n')[0],
    cpu_info['brand'] + '\n    freq: ' + str(psutil.cpu_freq().current) + ' MHz',
    '\n' + ntuple_to_str(psutil.virtual_memory(), 6),
    '\n' + '\n'.join('[%s] %s %f (%s)' % (g.id, g.name, g.memoryTotal, g.driver) for g in gpus)
    ))

def print_state_info(stage, compiler, flags, workdir):
    if os.path.isdir(workdir):
        dir_content = os.listdir(workdir)
        logger.info('Status Information:\n STAGE = %s\n COMPILER = %s\n FLAGS = %s\n WORKDIR = %s\n* Directory Content:\n%s', stage, compiler, flags, workdir, '\n'.join('--- ' + f for f in dir_content))
    else:
        logger.warning('Workdir path `%s\' does not exist!', workdir)
        logger.info('Status Information:\n STAGE = %s\n COMPILER = %s\n FLAGS = %s', stage, compiler, flags)

def expand_formatting(string_format, fvars):
    '''
    takes a format string `'hello {something}'.format` and a `dict('something': ['cat', 'dog'])`
    and produces several permutations of the format string with the values from the dict substituted.
    Because we use `partial`, the actual value are not computed until they are accessed from the
    list. Assuming the list is stored in `i`:
        i[0]() => 'hello cat'
        i[1]() => 'hello dog'

    Note: this function with destructively access the dict() - pass in a deep copy!
    '''
    try:
        val = fvars.popitem()
    except KeyError:
        # we have exhausted all fields and assume that the format string is complete
        return [string_format()]
    expanded = [partial(string_format, **{val[0]: v}) for v in val[1]]
    # recursively expand further formatting fields
    expanded = [expand_formatting(e, fvars.copy()) for e in expanded]
    # flatten by one level
    expanded = list(itertools.chain.from_iterable(expanded))
    return expanded

def __build(compiler, compvars, compflags, sources):
    '''
    This is the default build function which can be used as a basis
    to define a custom one. The interface *must* be the same, otherwise
    backward compatability cannot be assured.
    '''
    for varient, flag in compflags.items():
        flist = expand_formatting(flag.format, compvars.copy())
        for s in sources:
            sc = pathlib.Path(s)
            logger.info('Building `%s\' varient `%s\'', s, varient)
            for f in flist:
                logger.info('  calling `%s %s %s\'...', compiler, f, s)
                c = subprocess.run([compiler, f, '-o %s' % (sc.with_suffix('.out')), s], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                print(c.stdout.decode('utf-8'))


def build(compiler, compvars, compflags, sources):
    __build(compiler, compvars, compflags, sources)

def run():
    __build(compiler, compvars, compflags, sources)

if __name__ == '__main__':
    with tempfile.TemporaryDirectory() as workdir:
        os.chdir(workdir)
        logger = setup_logger('sample1', logging.INFO, True)
        logger.info('Starting benchmark `sample1\'')
        logger.info('Created local workdir at `%s\'' % (workdir))
        logger.info('Calling build function...')
        build(config['compiler'], config['compvars'], config['compflags'], config['sources'])
        logger.info('Calling run function...')
        run()
        archive_logs('sample1', workdir, localdir)
