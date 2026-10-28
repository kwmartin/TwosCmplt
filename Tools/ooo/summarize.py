"""Totals over every SWIFT_OOO_LOG file in a directory: per testbench, the
early writes that change history, by path and cause (classify.py), and the
harmless ones (effect none). Streams lines, so large logs are fine."""
import sys, re, glob, yaml
from collections import Counter, defaultdict
sys.path.insert(0, __import__("os").path.dirname(__file__))
from classify import classify

per_tb = defaultdict(Counter); causes = Counter(); none = Counter(); examples = {}
for f in glob.glob(sys.argv[1] + '/ooo_*.yml'):
    for line in open(f):
        if 'effect: none' in line:
            none[re.search(r'tb: (\S+),', line).group(1)] += 1
            continue
        e = yaml.safe_load(line)[0]
        k = classify(e)
        per_tb[e['tb']][k] += 1; causes[k] += 1
        examples.setdefault((e['tb'], k), e)
print('history-changing early writes, by cause:')
for k, n in causes.most_common(): print(f'  {n:6d}  {k}')
print(f'harmless (effect none): {sum(none.values())} in {len(none)} testbenches')
print('\nper testbench:')
for tb in sorted(per_tb, key=lambda t: -sum(per_tb[t].values())):
    print(f'  {tb}: {sum(per_tb[tb].values())}  ' + '; '.join(f'{n} {k}' for k, n in per_tb[tb].most_common()))
print('\nfirst example of each (testbench, cause):')
for (tb, k), e in sorted(examples.items()):
    cw = e['collides_with'] or {}
    print(f'  {tb} [{k}] {e["node"]} new {e["new_tm"]}={e["new_val"]} after {e["cur_tm"]}={e["cur_val"]} | phase {e["phase"]}'
          f'\n      writer: {e["writer"]}\n      earlier record by: {cw.get("writer")} ({cw.get("phase")})')
