#!/usr/bin/env python3
"""
vcd_sample_at_times.py

Sample one or more hierarchical signals from a VCD file at fixed periodic times.

Sampling rule
-------------
You provide:
  * a VCD file
  * one or more hierarchical signal names via --signal
  * a clock period via --clock-period
  * a sampling offset via --offset

The first sampling time is:
    offset + clock_period

Subsequent sampling times are:
    offset + 2*clock_period
    offset + 3*clock_period
    ...

At each sampling time, the script returns the most recent value for each requested
signal at or before that time.

Typical usage
-------------
Write sampled values to a CSV file:

    python3 vcd_sample_at_times.py sim.vcd \
        --signal tb.dut.out \
        --signal tb.dut.state \
        --clock-period 10ns \
        --offset 2ns \
        --output samples.csv

Write sampled values to standard output:

    python3 vcd_sample_at_times.py sim.vcd \
        --signal tb.top.result \
        --clock-period 20ns \
        --offset 5ns \
        --output -

Limit the number of samples:

    python3 vcd_sample_at_times.py sim.vcd \
        --signal tb.dut.out \
        --clock-period 10ns \
        --offset 0ns \
        --samples 100 \
        --output samples.csv

Stop sampling at or before a specified absolute time:

    python3 vcd_sample_at_times.py sim.vcd \
        --signal tb.dut.out \
        --clock-period 10ns \
        --offset 0ns \
        --until 2us \
        --output samples.csv

Command-line arguments
----------------------
Positional:
  vcd
      Input VCD file path.

Required options:
  --signal NAME
      Hierarchical VCD signal name to sample. Repeat this option for each signal.

  --clock-period TIME
      Sampling period. Examples: 10ns, 0.5us, 1ps.

  --offset TIME
      Sampling offset. The first sample occurs at offset + clock_period.

Optional:
  --samples N
      Maximum number of samples to emit.

  --until TIME
      Stop sampling at or before this absolute time.

  --output PATH
      Output CSV path. Use '-' to write to standard output.

Time units
----------
The script accepts these time units:
    s, ms, us, ns, ps, fs

Output format
-------------
The script writes CSV with these leading columns:
    sample_index
    sample_time_ticks
    sample_time_seconds

Additional columns are added for each requested signal.

Notes
-----
* Signal names must exactly match the hierarchical names present in the VCD.
* Scalar values are written as 0, 1, x, or z.
* Vector values are written as raw VCD bit strings such as 1010 or x1z0.
* If a signal has no known value yet at a sampling time, the script writes x.
"""

import argparse
import csv
import re
import sys
from bisect import bisect_right

TIME_UNITS = {
    's': 1.0,
    'ms': 1e-3,
    'us': 1e-6,
    'ns': 1e-9,
    'ps': 1e-12,
    'fs': 1e-15,
}

VCD_UNITS = {
    '1': 1.0,
    's': 1.0,
    'ms': 1e-3,
    'us': 1e-6,
    'ns': 1e-9,
    'ps': 1e-12,
    'fs': 1e-15,
}


def parse_time_value(text):
    m = re.fullmatch(r'\s*([0-9]*\.?[0-9]+)\s*([a-zA-Z]+)?\s*', text)
    if not m:
        raise ValueError(f"Invalid time value: {text!r}")
    value = float(m.group(1))
    unit = (m.group(2) or 's').lower()
    if unit not in TIME_UNITS:
        raise ValueError(f"Unsupported time unit {unit!r}; use one of {sorted(TIME_UNITS)}")
    return value * TIME_UNITS[unit]


def format_logic_value(value):
    if value is None:
        return 'x'
    return value


def parse_vcd(vcd_path, wanted_signals):
    code_to_name = {}
    signal_changes = {}
    timescale_seconds = None
    current_time = 0
    scope_stack = []
    in_definitions = True

    wanted = set(wanted_signals)

    with open(vcd_path, 'r', encoding='utf-8', errors='replace') as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue

            if in_definitions:
                if line.startswith('$timescale'):
                    ts_parts = [line]
                    while '$end' not in ts_parts[-1]:
                        ts_parts.append(next(f).strip())
                    ts_text = ' '.join(ts_parts)
                    m = re.search(r'\$timescale\s+([0-9]+)\s*([a-zA-Z]+)?\s+\$end', ts_text)
                    if not m:
                        raise ValueError('Could not parse $timescale from VCD')
                    mag = float(m.group(1))
                    unit = (m.group(2) or 's').lower()
                    if unit not in VCD_UNITS:
                        raise ValueError(f'Unsupported VCD timescale unit: {unit}')
                    timescale_seconds = mag * VCD_UNITS[unit]
                    continue

                if line.startswith('$scope'):
                    parts = line.split()
                    if len(parts) >= 3:
                        scope_stack.append(parts[2])
                    continue

                if line.startswith('$upscope'):
                    if scope_stack:
                        scope_stack.pop()
                    continue

                if line.startswith('$var'):
                    parts = line.split()
                    if len(parts) < 5:
                        continue
                    code = parts[3]
                    refname = parts[4]
                    full_name = '.'.join(scope_stack + [refname]) if scope_stack else refname
                    code_to_name[code] = full_name
                    if full_name in wanted:
                        signal_changes[full_name] = []
                    continue

                if line.startswith('$enddefinitions'):
                    in_definitions = False
                    continue

                continue

            if line.startswith('#'):
                current_time = int(line[1:])
                continue

            if line[0] in '01xXzZ':
                code = line[1:]
                name = code_to_name.get(code)
                if name in signal_changes:
                    signal_changes[name].append((current_time, line[0].lower()))
                continue

            if line[0] in 'bBrR':
                parts = line.split()
                if len(parts) != 2:
                    continue
                value = parts[0][1:].lower()
                code = parts[1]
                name = code_to_name.get(code)
                if name in signal_changes:
                    signal_changes[name].append((current_time, value))
                continue

    if timescale_seconds is None:
        raise ValueError('VCD file did not contain a $timescale directive')

    missing = [sig for sig in wanted_signals if sig not in signal_changes]
    return timescale_seconds, signal_changes, missing


def sample_signal(changes, sample_tick):
    if not changes:
        return None
    times = [t for t, _ in changes]
    idx = bisect_right(times, sample_tick) - 1
    if idx < 0:
        return None
    return changes[idx][1]


def main():
    ap = argparse.ArgumentParser(description='Sample specified VCD signals at periodic times.')
    ap.add_argument('vcd', help='Input VCD file')
    ap.add_argument('--signal', action='append', required=True,
                    help='Hierarchical signal name to sample; repeat for multiple signals')
    ap.add_argument('--clock-period', required=True,
                    help='Sampling period, e.g. 10ns, 0.5us')
    ap.add_argument('--offset', required=True,
                    help='Sampling offset time; first sample occurs at offset + clock_period')
    ap.add_argument('--samples', type=int, default=None,
                    help='Maximum number of samples to emit')
    ap.add_argument('--until', default=None,
                    help='Stop sampling at or before this absolute time, e.g. 1us')
    ap.add_argument('--output', default='-',
                    help='Output CSV path, or - for stdout')

    args = ap.parse_args()

    period_sec = parse_time_value(args.clock_period)
    offset_sec = parse_time_value(args.offset)
    until_sec = parse_time_value(args.until) if args.until is not None else None

    if period_sec <= 0:
        raise SystemExit('clock period must be > 0')

    timescale_seconds, signal_changes, missing = parse_vcd(args.vcd, args.signal)

    if missing:
        raise SystemExit('Missing requested signals:\n  ' + '\n  '.join(missing) + '\n')

    max_tick = 0
    for changes in signal_changes.values():
        if changes:
            max_tick = max(max_tick, changes[-1][0])

    start_sec = offset_sec + period_sec
    sample_tick = round(start_sec / timescale_seconds)
    step_tick = round(period_sec / timescale_seconds)
    if step_tick <= 0:
        raise SystemExit('clock period is smaller than one VCD timescale tick')

    until_tick = round(until_sec / timescale_seconds) if until_sec is not None else max_tick

    rows = []
    sample_index = 0
    while sample_tick <= max_tick and sample_tick <= until_tick:
        row = {
            'sample_index': sample_index,
            'sample_time_ticks': sample_tick,
            'sample_time_seconds': f'{sample_tick * timescale_seconds:.18g}',
        }
        for sig in args.signal:
            row[sig] = format_logic_value(sample_signal(signal_changes[sig], sample_tick))
        rows.append(row)
        sample_index += 1
        if args.samples is not None and sample_index >= args.samples:
            break
        sample_tick += step_tick

    out_fh = sys.stdout if args.output == '-' else open(args.output, 'w', newline='', encoding='utf-8')
    try:
        writer = csv.DictWriter(out_fh, fieldnames=['sample_index', 'sample_time_ticks', 'sample_time_seconds'] + args.signal)
        writer.writeheader()
        writer.writerows(rows)
    finally:
        if out_fh is not sys.stdout:
            out_fh.close()


if __name__ == '__main__':
    main()
