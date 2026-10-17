#!/usr/bin/env python3
"""Summarize recursion CSV medians and adjacent-size growth; no pass threshold."""
import csv
import statistics
import sys
from collections import defaultdict


def summarize(stream):
    groups = defaultdict(list)
    for row in csv.DictReader(stream):
        key = (row['grammar'], row['mode'], int(row['valid']), int(row['terms']))
        groups[key].append(row)
    previous = {}
    result = []
    for key, rows in sorted(groups.items()):
        if len(rows) != 7 or {int(r['sample']) for r in rows} != set(range(7)):
            raise ValueError(f'incomplete samples for {key}')
        elapsed = statistics.median(int(r['ns']) for r in rows)
        requested = statistics.median(int(r['requested_bytes']) for r in rows)
        prior = previous.get(key[:3])
        result.append((*key, elapsed, requested,
                       elapsed / prior[0] if prior else '',
                       requested / prior[1] if prior and prior[1] else ''))
        previous[key[:3]] = (elapsed, requested)
    expected = {(grammar, mode, valid, terms)
                for grammar in ('LeftChain', 'IndirectChain')
                for mode in ('validation', 'records', 'tree')
                for valid in (0, 1)
                for terms in (8, 16, 32, 64, 128, 256, 512)}
    if set(groups) != expected:
        raise ValueError(f'expected 84 known grammar/mode/validity/size groups, got {len(result)}')
    return result


if __name__ == '__main__':
    with open(sys.argv[1], newline='') as stream:
        rows = summarize(stream)
    writer = csv.writer(sys.stdout)
    writer.writerow(('grammar', 'mode', 'valid', 'terms', 'median_ns',
                     'median_requested_bytes', 'time_growth', 'payload_growth'))
    writer.writerows(rows)
