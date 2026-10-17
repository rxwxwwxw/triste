"""Dependency conclusions require complete, well-formed bounded traces."""
import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('memo_dependencies',Path(__file__).resolve().parents[1]/'scripts/memo-dependencies.py')
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def events(items):
    return [dict(sequence=str(i),kind=str(kind),caller=str(caller),entry=str(entry),
                 position=str(position),rule=rule,end='1',successful='1')
            for i,(kind,caller,entry,position,rule) in enumerate(items)]


class DependencyTests(unittest.TestCase):
    def cached(self):
        return events([(0,0,1,0,'head'),(1,1,1,0,''),(2,1,1,0,''),
                       (0,1,2,0,'callee'),(1,2,2,0,''),(2,2,1,0,''),(6,2,2,0,''),
                       (0,1,3,0,'wrapper'),(1,3,3,0,''),(3,3,2,0,''),(6,3,3,0,''),
                       (4,1,1,0,''),(5,1,2,0,''),(5,1,3,0,''),(6,1,1,0,''),(7,0,0,0,'')])

    def test_cached_transitive_reads(self):
        result=module.analyze(self.cached())
        self.assertIn((3,1),result['edges'])
        self.assertEqual(result['dependentRetirements'],2)
        self.assertEqual(result['directOnlyMisses'],1)
        self.assertEqual(result['cachedReads'],[(3,2,[1])])

    def test_incomplete_and_unstable(self):
        with self.assertRaisesRegex(ValueError,'missing case terminator'):
            module.analyze(self.cached()[:-1])
        rows=self.cached()
        rows[0]['entry']='2'
        with self.assertRaisesRegex(ValueError,'unstable entry'):
            module.analyze(rows)

    def test_active_seed_is_not_retired(self):
        rows=events([(0,0,1,0,'head'),(5,1,1,0,''),(7,0,0,0,'')])
        with self.assertRaisesRegex(ValueError,'retired active seed'):
            module.analyze(rows)

    def test_nested_same_and_distinct_positions(self):
        for position in (0,1):
            rows=events([(0,0,1,0,'outer'),(2,1,1,0,''),(0,1,2,position,'inner'),
                         (2,2,2,position,''),(6,2,2,position,''),(6,1,1,0,''),(7,0,0,0,'')])
            result=module.analyze(rows)
            self.assertEqual(result['maxActiveHeads'],2)
            self.assertEqual(result['samePositionHeads'],position==0)
            self.assertEqual(result['distinctPositionHeads'],position==1)

    def test_nonmemoized_root_can_reuse_a_completed_entry(self):
        rows=events([(0,0,1,0,'rule'),(6,1,1,0,''),(3,0,1,0,''),(7,0,0,0,'')])
        self.assertEqual(module.analyze(rows)['cachedReads'],[(0,1,[])])


if __name__=='__main__':unittest.main()
