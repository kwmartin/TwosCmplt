"""Classify SWIFT_OOO_LOG entries by what differs between the early write and
the later-stamped change it collides with."""
import sys, re, yaml
from collections import Counter

def cells(w):          # cell instances in a writer stack, e.g. CLA1_1(CLA1)
    return [p.split(' ')[0] for p in w.split(' / ') if '(' in p]
def kind(w):           # innermost activity: out-ports, in-ports, assign, always, gate
    return re.sub(r'\[.*', '', w.split(' / ')[-1].split(' ')[0])
def loop(w):
    m = re.search(r'loop-repeat (\d+)', w); return int(m.group(1)) if m else 1
def passes(w):
    return [p.split(' ')[1] for p in w.split(' / ') if '(' in p]

def classify(e):
    c = e['collides_with']
    if not c: return 'no-prior-record'
    w, cw = e['writer'], c['writer']
    if e['path'] == 'setNode-plain': tag = 'H5 plain-commit'
    else: tag = e['path']
    if c['phase'].split(' ')[:2] != e['phase'].split(' ')[:2]:
        why = 'H4 earlier sweep/sub-sweep'
    elif c['phase'] != e['phase']:
        why = 'H4 other sub-sweep'
    elif passes(w)[:1] != passes(cw)[:1]:
        why = 'H4 sync vs async pass'
    elif loop(w) != loop(cw):
        why = 'H4 loop repeat'
    elif cells(w) != cells(cw):
        why = 'H1 other writer instance'
    elif w == cw:
        why = 'same writer, same pass (re-run)'
    else:
        why = f'same cell: {kind(cw)} then {kind(w)}'
    return f'{tag} | {why} | effect {e["effect"]}'

if __name__ == "__main__":
  for f in sys.argv[1:]:
    es = yaml.safe_load(open(f)) or []
    print(f'{f.split("/")[-1]}: {len(es)} entries')
    for k, n in Counter(map(classify, es)).most_common():
        print(f'  {n:6d}  {k}')
