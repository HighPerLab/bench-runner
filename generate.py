#!/usr/bin/env python3
'''
Here we generated Python scripts to execute a series of commands
'''

#%# START #%#
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
                c = subprocess.run([compiler, f, '-o %s' % (sc.with_suffix('out')), s], stdout=subprocess.PIPE)
                print(c.stdout.decode('utf-8'))

#%# END #%#

# this is the body of the default build and run functions
DEFAULT_BUILD = '''\
__build(compiler, compvars, compflags, sources)'''


DEFAULT_RUN = '''\
pass'''

def check_config(config):
    # these keys *must* be present
    nkeys = ['benchsuite', 'benchname', 'sources', 'compiler', 'compflags']
    # these keys are optional
    # build and run are explicitly excluded...
    okeys = {'mode': 'auto', 'email': None, 'inputs': None, 'threads': 2, 'timelimit': '1:00:00','compvars': None}

    if not all(k in config.keys() for k in nkeys):
        logger.error('Please make sure to have the required keys: %s'.format(nkeys))

    for key, val in okeys.items():
        # set default values
        if key not in config.keys():
            config[key] = val

    # make sure compflags is correctly formatted
    try:
        check = config['compflags']['default']
    except TypeError:
        flags = config.pop('compflags')
        config['compflags'] = {'default': flags}

def load_config(config_file):
    output = None
    try:
        with open(config_file, 'r') as f:
            output = yaml.safe_load(f)
    except yaml.YAMLError as e:
        logger.exception('Config YAML has caused an error: %s', e)
    check_config(output)
    return output

def read_file_section(file_name, start_marker='#%# START #%#', end_marker='#%# END #%#'):
    '''
    Read in text from file that is between two markers
    '''
    text = ''
    with open(file_name, 'r') as f:
        read = False
        for line in f:
            if line.strip() == start_marker:
                read = True
            elif line.strip() == end_marker:
                break
            elif read:
                text += line
    return text

def add_config(bench_config):
    text = '# Global Config\n'
    text += 'logger = None\n'
    text += 'localdir = \'%s\'\n' % (os.path.join(os.getcwd(), 'results'))
    text += 'num_iters = 5\n'
    text += '\n# Bench Config\n'
    text += 'config = %s\n' % (str(bench_config))
    return text

def add_stdlib():
    text = '\n# STDLIB #\n\n'
    # we read this script
    text += read_file_section(__file__)
    return text

def indent_string(string, lvl=1):
    return '\n'.join((lvl * 4 * ' ') + i for i in string.splitlines() if i)

def add_main(name):
    text = '\nif __name__ == \'__main__\':\n'
    text += indent_string('with tempfile.TemporaryDirectory() as workdir:')+ '\n'
    text += indent_string('os.chdir(workdir)', 2)+ '\n'
    text += indent_string('logger = setup_logger(\'%s\', logging.INFO, True)' % (name), 2) + '\n'
    text += indent_string('logger.info(\'Starting benchmark `%s\\\'\')' % (name), 2) + '\n'
    text += indent_string('logger.info(\'Created local workdir at `%s\\\'\' % (workdir))', 2) + '\n'
    text += indent_string('logger.info(\'Calling build function...\')', 2) + '\n'
    text += indent_string('build(config[\'compiler\'], config[\'compvars\'], config[\'compflags\'], config[\'sources\'])', 2) + '\n'
    text += indent_string('logger.info(\'Calling run function...\')', 2) + '\n'
    text += indent_string('run()', 2) + '\n'
    text += indent_string('archive_logs(\'%s\', workdir, localdir)' % (name), 2) + '\n'
    return text

def add_function(name, body, args=None, lvl=1):
    if args and isinstance(args, list):
        text = '\n%sdef %s(%s):\n' % ((lvl-1) * 4 * ' ', name, ', '.join(args))
    else:
        text = '\n%sdef %s():\n' % ((lvl-1) * 4 * ' ', name)
    # we assume 4 space tabs and remove empty lines
    text += indent_string(body, lvl) + '\n'
    return text

def add_slurm_conf(name, timelimit, email, threads):
    text = '''\
#SBATCH --exclusive
#SBATCH --partition amd-longq
#SBATCH --job-name bench-{}
#SBATCH --time {}
#SBATCH --gres=gpu:k20:1
#SBATCH --cpus-per-task {}
'''.format(name, timelimit, threads)
    if email:
       text += '''\
#SBATCH --mail-type=FAIL
#SBATCH --mail-user={}
'''.format(email)
    text += '\n'
    return text

if __name__ == '__main__':
    argp = argparse.ArgumentParser(description='Generate Benchmarking Job scripts for SLURM')
    argp.add_argument('file', metavar='FILE', nargs='+', help='Configuration file from which to generate job script')
    argp.add_argument('-f', '--force', action='store_true', help='Force overwrite existing scripts')
    argp.add_argument('-l', '--log-to-file', action='store_true', help='Log to file instead')
    argp.add_argument('-v', dest='verbose', action='count', default=0, help='Set verbosity level - may be repeated for more output')
    argp.add_argument('-V', '--version', action='version', version='%(prog)s 1.0.0')

    args = argp.parse_args()

    # set default logging level
    logger = setup_logger('generator', args.verbose, args.log_to_file)

    #print_system_info('sac2c_d', '-V')

    logger.info('loading and parsing YAML config file(s)')

    for conf in args.file:
        logger.info('handling file `%s\'', conf)
        config = load_config(conf)
        filename = config['benchname'] + '-run.py'

        out = "#!/usr/bin/env python3\n\n"
        out += add_slurm_conf(config['benchname'], config['timelimit'], config['email'], config['threads'])
        out += add_config(config)
        out += add_stdlib()

        if config['mode'] == 'manual':
            try:
                out += add_function('build', config['build'], args=['compiler', 'compvars', 'compflags', 'sources'])
                out += add_function('run', config['run'])
            except:
                logger.exception('for manual mode you need to define `build\' and `run\' functions')
        else: # 'auto'
            out += add_function('build', DEFAULT_BUILD, args=['compiler', 'compvars', 'compflags', 'sources'])
            out += add_function('run', DEFAULT_RUN)

        out += add_main(config['benchname'])

        if os.path.isfile(filename) and not args.force:
            logger.warning('File `%s\' exists, skipping...', filename)
        else:
            with open(filename, 'w') as out_file:
                logger.info('Writing file `%s\'...', filename)
                out_file.write(out)
