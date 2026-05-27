# makeTB.py: make simple verilog testbench adding clock, input signals, and display nodes
# To Run: >vdb makeTB.py QD_DDFS5 with the testbench configured by /home/martin/.xschem/modules/QD_DDFS5.yml
import sys
import os
import argparse
import yaml
import json
import re
from string import Template
from math import *
import glob
from pathlib import Path

import lib.glbls as glbls

import logging
loggerDct = logging.root.manager.loggerDict
loggers = [logging.getLogger(name) for name in loggerDct]
for lggr in loggers:
  lggr.disable = True

logger = logging.getLogger('makeTB')
logger.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(asctime)s %(levelname)s: %(lineno)d: %(filename)s::: %(message)s')
ch = logging.StreamHandler()
ch.setLevel(logging.DEBUG)
ch.setFormatter(formatter)
logger.addHandler(ch)
logger.propogate = False
lggr = logger.debug

import pprint
pppp = pprint.PrettyPrinter(indent=2)
def pr(obj):
    pppp.pprint(obj)

sp = lambda n : ' '*n
setTmpl = lambda tmpl, dct : Template(tmpl).substitute(dct) 

class PrettySafeLoader(yaml.SafeLoader):
    def construct_python_tuple(self, node):
        return tuple(self.construct_sequence(node))

PrettySafeLoader.add_constructor(
    u'tag:yaml.org,2002:python/tuple',
    PrettySafeLoader.construct_python_tuple)

class NoAliasDumper(yaml.SafeDumper):
    def ignore_aliases(self, data):
        return True

# All of the important templates are defined in lib.testBenchTmplts
from lib.testBenchTmplts import *

re1 = (r'(.*){ VDD,VSS}(.*)', r'\1VDD, VSS\2') # remove concat braces around {VDD, VSS}
re2 = (r'^(.*)(\w+)\?(.*)\);', r'\1\2\3);') # remove '?' left from viewdraw schematics

def substitute_ln(ln, re1):
    ln2 = re.sub(re1[0], re1[1], ln)
    ln3 = re.sub(re2[0], re2[1], ln2)
    # ln4 = ln3.replace('{', '')
    # ln5 = ln4.replace('}', '')
    return ln3

def _build_fmt_vals(nd_list, include_time):
    fmt = '"'
    vals = ''
    if include_time:
        fmt += '%t'
        vals = '$realtime'
        space = '   '
    else:
        space = ' '
    for nd_spec in nd_list:
        nd = nd_spec['name']
        frmt = nd_spec['format']
        is_signed = frmt.lower() == 's'
        fmt += space + ('%d' if is_signed else f'%{frmt}')
        vals += (', ' if vals else '') + (f'$signed({nd})' if is_signed else nd)
        space = ' ' * len(nd)
    fmt += '"'
    return fmt, vals

def gen_display_code(input_spcs, dsplyFile):
    per = input_spcs['Constants'].get('PER', 0)
    dsplyIncr = input_spcs.get('DisplayIncr', per)
    dsplyNds = input_spcs.get('DisplayNds')
    if not dsplyIncr or not dsplyNds:
        return ''
    lggr("Adding Display Loop")
    hdrStr = '"    time     ' + ''.join(' ' + nd['name'] for nd in dsplyNds) + '"'
    fmtStr, vals = _build_fmt_vals(dsplyNds, include_time=True)
    dsplyLines = setTmpl(dsplyLinesTmplt, {'fmt': fmtStr, 'vals': vals})
    return setTmpl(displayLoop, {
        'displayFile': dsplyFile,
        'headerStr':   hdrStr,
        'dsplyIncr':   dsplyIncr,
        'dsplyLines':  dsplyLines,
    })

def gen_save_code(input_spcs, dsplyFile):
    per = input_spcs['Constants'].get('PER', 0)
    dsplyIncr = input_spcs.get('DisplayIncr', per)
    saveNds = input_spcs.get('SaveNds')
    if not saveNds:
        return ''
    lggr("Adding SaveNds section")
    fmtStr, vals = _build_fmt_vals(saveNds, include_time=False)
    dsplyLines = setTmpl(fdsplyLineTmplt, {'fmt': fmtStr, 'vals': vals})
    return setTmpl(saveLoop, {
        'displayFile': dsplyFile,
        'dsplyIncr':   dsplyIncr,
        'dsplyLines':  dsplyLines,
    })

def gen_time_spcs_code(input_spcs, hasClock):
    tmSpcs = input_spcs.get('TimeSpcs')
    if not tmSpcs:
        return ''
    lggr("Adding TimeSpcs section")
    lastTm = 0
    tmSpcLns = ''
    for spc in tmSpcs:
        spcTm = parseTm(spc['tm'])
        deltaTm = spcTm - lastTm
        spcStr = f'    #({deltaTm})\n'
        for vl in spc['vls']:
            spcStr += f'    {vl[0]}={parseVl(str(vl[1]))};\n'
        tmSpcLns += spcStr
        lastTm = spcTm
    if 'FinishTime' in input_spcs:
        endTime = parseTm(input_spcs['FinishTime'])
    elif hasClock:
        clk0 = input_spcs['Clock'][0]
        endTime = parseTm(clk0['per']) * clk0['nmbPers']
    else:
        endTime = parseTm('1*PER')
    return setTmpl(inSpcs, {
        'specLines': tmSpcLns[:-1],
        'endTime':   endTime - lastTm,
    })

def gen_code_loop(input_spcs):
    vals = input_spcs.get('CodeLoop')
    if not vals:
        return ''
    lggr("Adding CodeLoop section")
    return setTmpl(codeLoop, {
        'var':      vals['var'],
        'varInit':  vals['init'],
        'nmbIters': vals['final'],
        'timeIncr': parseTm(vals['timeIncr']),
        'varIncr':  parseTm(vals['varIncr']),
    })

def gen_code_block(input_spcs):
    blck = input_spcs.get('CodeBlock')
    if not blck:
        return ''
    lggr("Adding CodeBlock section")
    lines = ['  ' + ln for ln in blck.split('\n')]
    return '\n' + '\n'.join(lines)

def gen_clk_code(input_spcs):
    clk_spcs = input_spcs.get('Clock')
    if not clk_spcs:
        return False, ''
    lggr("Adding Clock section")
    code = ''
    for clk in clk_spcs:
        per = parseTm(clk['per'])
        if 'nmbPers' not in clk:
            assert 'FinishTime' in input_spcs, 'Error: FinishTime not specified'
            clk['nmbPers'] = round(parseTm(input_spcs['FinishTime']) / per)
        code += setTmpl(clkTmplt, {
            'clkNm':   clk['clkNm'],
            'initVal': clk.get('initVal', 0),
            'halfPer': per / 2,
            'delay':   clk.get('delay', 0),
            'nmbPers': clk['nmbPers'],
        })
    return True, code

def parseTm(tm):
    rtrn = tm
    if isinstance(tm,str):
        input_spcs = glbls.input_spcs
        if tm in input_spcs['Constants']:
            rtrn = input_spcs['Constants'][tm]
        else:
            mtch1 = re.match(r'(\d+\.?\d*)\*(\w+)', str(tm))
            mtch2 = re.match(r'(\w+)\*(\d+\.?\d*)', str(tm))
            if mtch1:
                vl = f"{float(mtch1.group(1))*input_spcs['Constants'][mtch1.group(2)]}"
                rtrn = floor(float(vl))
            elif mtch2:
                vl = f"{float(mtch2.group(2))*input_spcs['Constants'][mtch2.group(1)]}"
                rtrn = floor(float(vl))
            else:
                rtrn = input_spcs['Constants']['PER']
    return rtrn

def parseVl(vl1):
    rtrn = vl1
    mtch1 = re.match(r'(\d+)([h,d,o,b,H,D,O,B,s,S])([a-f,A-F,0-9]+)', vl1)
    if mtch1:
        if mtch1.group(2) == 's' or mtch1.group(2) == 'S':
            rtrn = '$signed(' + mtch1.group(1) + "'" + 'd' + mtch1.group(3) + ')'
        else:
            rtrn = mtch1.group(1) + "'" + mtch1.group(2) + mtch1.group(3)
    return rtrn

def main(tst_bnch):
    if not __name__ == '__main__':
        sys.argv = [os.path.basename(__file__)]

    #with open(glbls.input_spcs_file, 'r') as infp:
    base_name = os.path.splitext(os.path.basename(tst_bnch))[0]
    glbls.base_name = base_name

    glbls.input_spcs_file = glbls.spcs_dir + base_name + '.yml'
    with open(glbls.input_spcs_file, 'r') as infp:
        input_spcs = yaml.load(infp, Loader=PrettySafeLoader)
        glbls.input_spcs = input_spcs

    lib_dir = glbls.lib_dir

    module = base_name
    assert input_spcs['module'] == module, \
        f"yml module '{input_spcs['module']}' != argument '{module}'"

    if 'PER' in input_spcs['Constants']:
        per = input_spcs['Constants']['PER']
        input_spcs['Constants'].setdefault('HLF_PER', per // 2)
        input_spcs['Constants'].setdefault('TWO_PER', 2 * per)

    inFile    = input_spcs.get('inFile',     'TB_' + module + '.v')
    vcdFile   = input_spcs.get('vcdFile',    module + '_tb.vcd')
    dsplyFile = input_spcs.get('Displayfile', module + '.out')
    dumpModule = input_spcs.get('DumpModule', 'TB_' + module)

    inputNetLst = glbls.sim_dir + inFile
    with open(inputNetLst, 'r') as infp:
        net_lst_orig = infp.read()

    dct = {"ntLstDir": glbls.sim_dir,
           "projDir":  glbls.proj_dir,
           "verLib":   glbls.ver_dir,
           "libDir":   lib_dir,
           "base":     module}

    inCmds = setTmpl(inCmd, dct)
    inCmdFile = glbls.sim_dir + 'in_files'
    with open(inCmdFile, 'w') as fp:
        fp.write(inCmds)

    # tst_bnch_code = modDef
    tst_bnch_code = ''

    hasClock, clk_code = gen_clk_code(input_spcs)
    tst_bnch_code += clk_code

    tst_bnch_code += gen_display_code(input_spcs, dsplyFile)
    tst_bnch_code += gen_save_code(input_spcs, dsplyFile)

    dct = {
        "vcdFile": vcdFile,
        "dumpModule": dumpModule,
    }
    code = setTmpl(dumpBlk, dct)
    tst_bnch_code = tst_bnch_code + code

    tst_bnch_code += gen_time_spcs_code(input_spcs, hasClock)
    tst_bnch_code += gen_code_loop(input_spcs)
    tst_bnch_code += gen_code_block(input_spcs)

    # Add tst_bnch_code to test bench
    tb_hdr = ''
    for key,val in input_spcs['Constants'].items():
        tb_hdr = tb_hdr + '`define ' + key + ' ' + str(val) + '\n'

    nt_lst_lns = net_lst_orig.split('\n')
    trnsfrmd_lns = []
    for ln in nt_lst_lns:
        ln2 = substitute_ln(ln, re1)
        trnsfrmd_lns.append(ln2)
    net_lst = '\n'.join(trnsfrmd_lns)

    tb_str = setTmpl(net_lst, {'TB_HEADER': tb_hdr, 'TB_BODY': tst_bnch_code})
    tb_str = re.sub(r'"([^"/]+\.mem)"', lambda m: f'"{glbls.sim_dir}{m.group(1)}"', tb_str)

    out_file = glbls.sim_dir + module + '_tb.v'
    with open(out_file, 'w') as outfp:
        outfp.write(tb_str)

    runCmd = setTmpl(runTmplt, {"in_files": inCmdFile, "base": glbls.base_name.lower()})
    print(runCmd)

    os.system(runCmd)

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("test_bench", help="Specify base of testbench",
                        action="store")
    defOutFl = glbls.out_file
    parser.add_argument("-o", "--output",
        default=defOutFl, help="Directs the output to a netlist file of your choice")
    args = parser.parse_args()
    glbls.out_file = args.output
    glbls.yml_spcs_file = args.test_bench + '.yml'
    glbls.input_spcs_file = glbls.spcs_dir + glbls.yml_spcs_file

    rtrnDir = os.getcwd()
    os.chdir(glbls.sim_dir)

    main(args.test_bench)
    os.chdir(rtrnDir)
