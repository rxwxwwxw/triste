"""Map gcov edges to source decisions, merging D template instantiations.

GCC inserts branches for D array bounds and assertions. These are invariant
checks, not recoverable application decisions. CFG trap blocks identify them;
raw reports are retained. Compiler exception-dispatch machinery is excluded just
like gcov throw edges. Every application decision remains counted, including
unseen errors and conditionals in exception handlers.
"""
import re
from pathlib import Path

class FunctionCFG:
    def __init__(self):
        self.blocks = {}

    def decisions(self):
        traps = {number for number, text in self.blocks.items()
                 if re.search(r'__builtin_trap(?:D\.\d+)?\s*\(', text) or '_d_assert' in text or '_d_arraybounds' in text}
        result = {}
        contract_locations = set()
        for number, text in self.blocks.items():
            # GDC emits eh_dispatch for destructor cleanup, even for C calls in
            # nothrow functions. It has no application predicate or normal edge.
            if re.search(r'(?:^|\])\s*eh_dispatch\s+\d+\b', text, re.M):
                result[number] = None
                continue
            targets = [int(n) for n in re.findall(r'goto <bb (\d+)>', text)]
            locations = re.findall(r'\[([^\]\n]+):(\d+):(\d+)(?: discrim \d+)?\]', text)
            location = locations[-1] if locations else ('', '0', '0')
            if any(target in traps for target in targets):
                contract_locations.add(location)
                result[number] = None
                continue
            if targets:
                # GCC emits the true target before the false target in a conditional.
                result[number] = (location, {target: i for i, target in enumerate(targets)})
            else:
                cases = re.findall(r'(default|case [^:<>]+): <L(\d+)>', text)
                if cases:
                    result[number] = (location, {label: case for case, label in cases})
        # Slice-assignment checks can use several short-circuit blocks at one
        # source location before reaching the common invariant-failure block.
        for number, decision in list(result.items()):
            if decision is not None and decision[0] in contract_locations: result[number] = None
        return result

def read_cfg(paths):
    functions = {}
    for path in paths:
        current = None
        current_name = None
        block = None
        last_location = ''
        with Path(path).open() as stream:
            for line in stream:
                if line.startswith(';; Function '):
                    match = re.match(r';; Function .* \(([^,]+), funcdef_no=', line)
                    if match:
                        if current is not None: functions[current_name] = current.decisions()
                        current_name = match[1]
                        current = FunctionCFG()
                        block = None
                        continue
                match = re.match(r'(?:  <bb (\d+)>|;;\s+basic block (\d+),)', line)
                if match and current is not None:
                    block = int(match[1] or match[2]); current.blocks[block] = ''
                    last_location = ''
                if current is None or block is None: continue
                if line.strip() == '}':
                    functions[current_name] = current.decisions()
                    current = None
                    block = None
                    continue
                locations = re.findall(r'\[[^\]\n]+:\d+:\d+(?: discrim \d+)?\]', line)
                if locations: last_location = locations[-1]
                if ('if (' in line or 'switch (' in line or 'goto <bb ' in line or
                    '__builtin_trap' in line or '_d_assert' in line or '_d_arraybounds' in line or
                    re.search(r'\beh_dispatch\s+\d+\b', line)):
                    current.blocks[block] += (last_location + ' ' if not locations else '') + line
        if current is not None: functions[current_name] = current.decisions()
    return functions

def unittest_lines(path):
    """Match dfmt's closing brace at the unittest's indentation, including version blocks."""
    lines = Path(path).read_text().splitlines()
    result = set()
    indentation = None
    for i, line in enumerate(lines, 1):
        match = re.match(r'^(\s*)(?:@[\w()]+\s+|nothrow\s+|pure\s+)*unittest\b', line)
        if match: indentation = match[1]
        if indentation is not None:
            result.add(i)
            if line == indentation + '}': indentation = None
    return result

def source_edges(source, cfg, excluded):
    """Return coverage keyed by source location and conditional outcome."""
    result = {}
    for line in source.get('lines', []):
        function = line.get('function_name', '')
        if re.search(r'(?:9__xtoHash|11__xopEquals|10__xopCmp)', function):
            continue
        if line['line_number'] in excluded:
            continue
        decisions = cfg.get(line.get('function_name'), {})
        for index, branch in enumerate(line.get('branches', [])):
            if branch.get('throw', False): continue
            block = branch.get('source_block_id')
            if block in decisions and decisions[block] is None: continue
            location, targets = decisions.get(block, (('', str(line['line_number']), '0'), {}))
            # Missing CFG mappings remain counted; they are never silently exempted.
            outcome = targets.get(branch.get('destination_block_id'), index)
            identity = (line['line_number'], location[2], outcome)
            result[identity] = result.get(identity, False) or branch.get('count', 0) > 0
    return result
