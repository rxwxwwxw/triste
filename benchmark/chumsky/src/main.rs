use chumsky::prelude::*;
use serde::{Deserialize, Serialize};
use std::{
    alloc::{GlobalAlloc, Layout, System},
    cell::Cell,
    env, fs,
    hint::black_box,
    process,
    time::Instant,
};

#[derive(Clone, Copy, Default)]
struct AllocationStats {
    calls: u64,
    payload_bytes: u64,
}
thread_local! {
    static ALLOCATIONS: Cell<Option<AllocationStats>> = const { Cell::new(None) };
}
struct CountingAllocator;
fn account(bytes: usize, success: bool) {
    ALLOCATIONS.with(|cell| {
        if let Some(mut stats) = cell.get() {
            stats.calls += 1;
            if success {
                stats.payload_bytes += bytes as u64;
            }
            cell.set(Some(stats));
        }
    });
}
unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let ptr = unsafe { System.alloc(layout) };
        account(layout.size(), !ptr.is_null());
        ptr
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let ptr = unsafe { System.alloc_zeroed(layout) };
        account(layout.size(), !ptr.is_null());
        ptr
    }
    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let ptr = unsafe { System.realloc(ptr, layout, new_size) };
        account(new_size, !ptr.is_null());
        ptr
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe { System.dealloc(ptr, layout) };
    }
}
#[global_allocator]
static ALLOCATOR: CountingAllocator = CountingAllocator;

#[derive(Debug)]
struct Node {
    kind: u64,
    begin: usize,
    end: usize,
    children: Vec<Node>,
}

fn node(kind: u64, span: SimpleSpan, children: Vec<Node>) -> Node {
    Node {
        kind,
        begin: span.start,
        end: span.end,
        children,
    }
}

fn parser<'a>() -> impl Parser<'a, &'a str, Node, extra::Err<EmptyErr>> {
    let ws = one_of(" \t\r\n").repeated().ignored();
    let digit = one_of("0123456789");
    let hex = one_of("0123456789abcdefABCDEF");
    let escape = just('\\').ignore_then(choice((
        one_of("\"\\/bfnrt").ignored(),
        just('u').ignore_then(hex.repeated().exactly(4)).ignored(),
    )));
    let string = choice((
        escape,
        any()
            .filter(|c: &char| *c >= ' ' && *c != '"' && *c != '\\')
            .ignored(),
    ))
    .repeated()
    .delimited_by(just('"'), just('"'))
    .map_with(|_, e| node(2, e.span(), vec![]));
    let integer = choice((
        just('0').ignored(),
        one_of("123456789").then(digit.repeated()).ignored(),
    ));
    let number = just('-')
        .or_not()
        .then(integer)
        .then(just('.').ignore_then(digit.repeated().at_least(1)).or_not())
        .then(
            one_of("eE")
                .then(one_of("+-").or_not())
                .then(digit.repeated().at_least(1))
                .or_not(),
        )
        .ignored()
        .map_with(|_, e| node(3, e.span(), vec![]));
    recursive(|value| {
        let array = value
            .clone()
            .padded_by(ws)
            .separated_by(just(','))
            .collect::<Vec<_>>()
            .delimited_by(just('[').then(ws), just(']'))
            .map_with(|children, e| node(1, e.span(), children));
        let pair = string
            .clone()
            .padded_by(ws)
            .then_ignore(just(':'))
            .then(value.clone().padded_by(ws));
        let object = pair
            .separated_by(just(','))
            .collect::<Vec<_>>()
            .delimited_by(just('{').then(ws), just('}'))
            .map_with(|pairs, e| {
                let children = pairs
                    .into_iter()
                    .flat_map(|(key, value)| [key, value])
                    .collect();
                node(0, e.span(), children)
            });
        choice((
            object,
            array,
            string,
            number,
            just("true").map_with(|_, e| node(4, e.span(), vec![])),
            just("false").map_with(|_, e| node(5, e.span(), vec![])),
            just("null").map_with(|_, e| node(6, e.span(), vec![])),
        ))
    })
    .padded_by(ws)
    .then_ignore(end())
}

fn ambiguous_parser<'a>() -> impl Parser<'a, &'a str, Node, extra::Err<EmptyErr>> {
    just('a')
        .repeated()
        .then_ignore(just('b'))
        .or(just('a').repeated().then_ignore(just('c')))
        .map_with(|_, e| node(2, e.span(), vec![]))
        .then_ignore(end())
}

// This is also the D output schema. Spans use no parent; tree uses preorder indices.
type Record = [u64; 4];
fn project(node: &Node, tree: bool, parent: u64, records: &mut Vec<Record>) {
    let mut next_parent = parent;
    if tree || node.kind >= 2 {
        next_parent = records.len() as u64;
        records.push([
            node.kind,
            node.begin as u64,
            node.end as u64,
            if tree { parent } else { u64::MAX },
        ]);
    }
    for child in &node.children {
        project(child, tree, next_parent, records);
    }
}
fn fingerprint(records: &[Record]) -> u64 {
    records
        .iter()
        .flatten()
        .fold(14695981039346656037u64, |hash, word| {
            (hash ^ word).wrapping_mul(1099511628211)
        })
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Case {
    name: String,
    grammar: String,
    input: String,
    expected_accepted: bool,
    iterations: usize,
    timed: bool,
    expected_spans: Vec<Record>,
    expected_tree: Vec<Record>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Row {
    name: String,
    engine: &'static str,
    output: String,
    execution: &'static str,
    input_bytes: usize,
    iterations: usize,
    samples: usize,
    mean_ms: f64,
    min_ms: f64,
    max_ms: f64,
    #[serde(rename = "MBps")]
    mbps: f64,
    expected_accepted: bool,
    output_hash: u64,
    output_nodes: usize,
    allocator_measured: bool,
    allocation_scope: &'static str,
    allocator_calls_per_op: u64,
    payload_bytes_per_op: u64,
    // System allocator metadata/usable capacity are not portable measurements.
    reserved_bytes_per_op: Option<u64>,
    gc_bytes_per_op: u64,
    sample_ms: Vec<f64>,
}

fn run() -> Result<(), String> {
    let args: Vec<_> = env::args().collect();
    if args.len() != 5 {
        return Err(
            "Usage: triste-chumsky-benchmark CORPUS.json validation|spans|tree ITERATIONS SAMPLES"
                .into(),
        );
    }
    let mode = &args[2];
    if !["validation", "spans", "tree"].contains(&mode.as_str()) {
        return Err("Invalid output mode".into());
    }
    let override_iterations: usize = args[3].parse().map_err(|_| "Invalid iterations")?;
    let samples: usize = args[4].parse().map_err(|_| "Invalid samples")?;
    if samples == 0 {
        return Err("Samples must be positive".into());
    }
    let corpus: Vec<Case> = serde_json::from_slice(&fs::read(&args[1]).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())?;
    let parser = parser().boxed(); // Parser construction is outside every timed interval.
    let ambiguous = ambiguous_parser().boxed();
    let mut rows = vec![];
    let mut checksum = 0u64;
    for case in &corpus {
        let selected_parser = match case.grammar.as_str() {
            "json" => &parser,
            "ambiguous" => &ambiguous,
            _ => return Err("Unknown corpus grammar".into()),
        };
        let observe = || {
            if mode == "validation" {
                let accepted = selected_parser
                    .check(black_box(case.input.as_str()))
                    .has_output();
                (accepted, if accepted { fingerprint(&[]) } else { 0 }, 0)
            } else {
                let parsed = selected_parser
                    .parse(black_box(case.input.as_str()))
                    .into_result();
                match parsed {
                    Ok(node) => {
                        let mut records = vec![];
                        project(&node, mode == "tree", u64::MAX, &mut records);
                        (true, fingerprint(&records), records.len())
                    }
                    Err(_) => (false, 0, 0),
                }
            }
        };
        let (accepted, output_hash, output_nodes) = observe();
        if accepted != case.expected_accepted {
            return Err(format!(
                "Acceptance mismatch: {} input={:?}",
                case.name, case.input
            ));
        }
        // Full record equality before timing, including offsets and parent indices.
        if mode != "validation" && accepted {
            let node = selected_parser
                .parse(case.input.as_str())
                .into_result()
                .map_err(|_| "Parse failed")?;
            let mut records = vec![];
            project(&node, mode == "tree", u64::MAX, &mut records);
            let expected = if mode == "tree" {
                &case.expected_tree
            } else {
                &case.expected_spans
            };
            if &records != expected {
                return Err(format!("Output record mismatch: {}", case.name));
            }
        }
        if !case.timed {
            continue;
        }
        let iterations = if override_iterations > 0 {
            override_iterations
        } else {
            case.iterations
        };
        if iterations == 0 {
            return Err("Iterations must be positive".into());
        }
        ALLOCATIONS.with(|cell| cell.set(Some(AllocationStats::default())));
        black_box(observe());
        let allocation_stats = ALLOCATIONS.with(|cell| cell.replace(None).unwrap());
        let mut times = vec![];
        for sample in 0..=samples {
            let start = Instant::now();
            for _ in 0..iterations {
                let (accepted, hash, nodes) = black_box(observe());
                checksum = checksum
                    .wrapping_mul(33)
                    .wrapping_add(if accepted { 1 } else { 2 })
                    .wrapping_add(hash)
                    .wrapping_add(nodes as u64);
                black_box(checksum);
            }
            let elapsed = start.elapsed().as_secs_f64() * 1000.0;
            if sample > 0 {
                times.push(elapsed);
            }
        }
        let mean_ms = times.iter().sum::<f64>() / samples as f64;
        rows.push(Row {
            name: case.name.clone(),
            engine: "Chumsky",
            output: mode.clone(),
            execution: if mode == "validation" {
                "check"
            } else {
                "native-tree-projection"
            },
            input_bytes: case.input.len(),
            iterations,
            samples,
            mean_ms,
            min_ms: times.iter().copied().fold(f64::INFINITY, f64::min),
            max_ms: times.iter().copied().fold(0.0, f64::max),
            mbps: if mean_ms > 0.0 {
                case.input.len() as f64 * iterations as f64 / (mean_ms * 1000.0)
            } else {
                0.0
            },
            expected_accepted: accepted,
            output_hash,
            output_nodes,
            allocator_measured: true,
            allocation_scope: "parser+output",
            allocator_calls_per_op: allocation_stats.calls,
            payload_bytes_per_op: allocation_stats.payload_bytes,
            reserved_bytes_per_op: None,
            gc_bytes_per_op: 0,
            sample_ms: times,
        });
    }
    println!(
        "{}",
        serde_json::json!({"schemaVersion":2,"benchmarks":rows,"checksum":checksum})
    );
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn syntax_and_spans() {
        let parser = parser();
        for input in [
            "{}",
            "[]",
            "null",
            "-0.995e+2",
            " \t[0]\r\n",
            r#"{"a":[true,false,null,"\u0041\n\/",-12.5E-2]}"#,
        ] {
            assert!(parser.check(input).has_output(), "{input}");
        }
        for input in [
            "",
            "01",
            "1.",
            "1e",
            "+1",
            "[1,]",
            r#"{"a":1,}"#,
            r#""\q""#,
            "\"raw\nnewline\"",
            "{}garbage",
            "[",
            r#""\u123""#,
        ] {
            assert!(!parser.check(input).has_output(), "{input}");
        }
        let node = parser.parse(" [null] ").into_result().unwrap();
        let mut records = vec![];
        project(&node, true, u64::MAX, &mut records);
        assert_eq!(records, vec![[1, 1, 7, u64::MAX], [6, 2, 6, 0]]);
    }
}
