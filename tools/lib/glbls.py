import os,sys
import importlib
from pathlib import Path
import yaml

# Project root: two levels up from this file (lib/ → tools/ → project root)
PROJECT_ROOT = Path(__file__).parent.parent.parent
from ruyaml import YAML
from ruyaml.representer import RoundTripRepresenter
import fcntl

def wrt_wth_lck(flnm, data):
  # Open the file in write mode
  with open(flnm, "a") as fp:
    # Acquire exclusive lock on the file
    fcntl.flock(fp.fileno(), fcntl.LOCK_EX)

    # Perform operations on the file
    fp.seek(0)
    fp.truncate()
    fp.write(data)

    # Release the lock
    fcntl.flock(fp.fileno(), fcntl.LOCK_UN)
  aa=0

class PrettySafeLoader(yaml.SafeLoader):
    def construct_python_tuple(self, node):
        return tuple(self.construct_sequence(node))

class SingleQuotedDumper(yaml.SafeDumper):
    def ignore_aliases(self, data):
        return True

def single_quoted_str_representer(dumper, data):
    # Always use single-quoted style
    return dumper.represent_scalar('tag:yaml.org,2002:str', data, style="'")

SingleQuotedDumper.add_representer(str, single_quoted_str_representer)

class NonAliasingRTRepresenter(RoundTripRepresenter):
    def ignore_aliases(self, data):
        return True

def imprt_fl(flnm,  nm):
  modname = Path(flnm).stem
  import importlib.util, sys
  spec = importlib.util.spec_from_file_location(modname, flnm)
  module = importlib.util.module_from_spec(spec)
  sys.modules[nm] = module
  spec.loader.exec_module(module)
  return module

def rd_yml(flnm):
  with open(flnm, 'r') as fp:
    dct = yaml.load(fp, Loader=PrettySafeLoader)
  return dct

def wrt_yml(flnm, data):
    yaml = YAML()
    yaml.default_flow_style = False
    yaml.indent(mapping=4, sequence=4, offset=2)
    yaml.Representer = NonAliasingRTRepresenter
    yaml.explicit_start = False

    with open(flnm, "w") as fp:
        yaml.dump(data, fp)


def wrt_file(flnm, data):
  wrt_wth_lck(flnm, data)
  aa=0

def rd_file(flnm):
  with open(flnm, 'r') as fp:
    #print(f"Just opened {flnm} at position {fp.tell()}")
    fp.seek(0)
    data = fp.read().rstrip()
  return(data)

__all__=['imprt_fl', 'rd_yml', 'wrt_yml', 'wrt_file', 'wrt_wth_lck', 'rd_file', 'PROJECT_ROOT']
