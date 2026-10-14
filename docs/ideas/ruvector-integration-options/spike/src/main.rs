//! Spike: does ruvector-core (HNSW, Turbo4) return the same answers as brana's exact cosine scan
//! over the real knowledge.db vectors, and at what speed / memory cost?
use ruvector_core::types::{DbOptions, HnswConfig, QuantizationConfig};
use ruvector_core::{DistanceMetric, SearchQuery, VectorDB, VectorEntry};
use std::collections::HashSet;
use std::time::Instant;

const DB: &str = "/home/martineserios/.claude/jobs/8e7be6c0/tmp/home/.claude/memory/knowledge.db";
const QUERIES: &str = "/home/martineserios/.claude/jobs/8e7be6c0/tmp/rv-spike/queries.json";
const DIM: usize = 384;

fn blob_to_vec(b: &[u8]) -> Option<Vec<f32>> {
    if b.len() != DIM * 4 {
        return None;
    }
    Some(b.chunks_exact(4).map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]])).collect())
}

fn cosine(a: &[f32], b: &[f32]) -> f32 {
    let (mut d, mut na, mut nb) = (0.0f32, 0.0f32, 0.0f32);
    for (x, y) in a.iter().zip(b) {
        d += x * y;
        na += x * x;
        nb += y * y;
    }
    let den = na.sqrt() * nb.sqrt();
    if den == 0.0 { 0.0 } else { d / den }
}

fn rss_mb() -> f64 {
    std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|s| s.lines().find(|l| l.starts_with("VmRSS")).map(|l| l.to_string()))
        .and_then(|l| l.split_whitespace().nth(1).and_then(|n| n.parse::<f64>().ok()))
        .map(|kb| kb / 1024.0)
        .unwrap_or(0.0)
}

fn median(mut v: Vec<f64>) -> f64 {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    v[v.len() / 2]
}

struct Row {
    key: String,
    vec: Vec<f32>,
}

fn main() {
    let conn = rusqlite::Connection::open_with_flags(
        DB,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    )
    .expect("open knowledge.db");
    let mut stmt = conn.prepare("SELECT key, vec FROM knowledge").unwrap();
    let rows: Vec<Row> = stmt
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Vec<u8>>(1)?)))
        .unwrap()
        .filter_map(|r| r.ok())
        .filter_map(|(key, b)| blob_to_vec(&b).map(|vec| Row { key, vec }))
        .collect();
    println!("loaded {} vectors (dim {DIM}), baseline RSS {:.0} MB", rows.len(), rss_mb());

    let qs: Vec<(i64, Vec<f32>)> = serde_json::from_str::<Vec<serde_json::Value>>(
        &std::fs::read_to_string(QUERIES).unwrap(),
    )
    .unwrap()
    .into_iter()
    .map(|q| {
        (
            q["n"].as_i64().unwrap(),
            q["vector"].as_array().unwrap().iter().map(|x| x.as_f64().unwrap() as f32).collect(),
        )
    })
    .collect();

    // Ground truth: exact cosine top-10 per query, and its latency.
    let mut truth: Vec<Vec<String>> = Vec::new();
    let mut exact_lat = Vec::new();
    for (_, q) in &qs {
        let t = Instant::now();
        let mut s: Vec<(f32, &str)> = rows.iter().map(|r| (cosine(q, &r.vec), r.key.as_str())).collect();
        s.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap());
        exact_lat.push(t.elapsed().as_secs_f64() * 1e6);
        truth.push(s.iter().take(10).map(|x| x.1.to_string()).collect());
    }
    println!("{:<26} build {:>7}   query p50 {:>8.0} us   overlap@5 20/20-ish = 1.000  overlap@10 = 1.000   (ground truth)",
        "exact (brana today)", "-", median(exact_lat));

    let variants: Vec<(&str, Option<HnswConfig>, Option<QuantizationConfig>)> = vec![
        ("rv flat (no HNSW)", None, None),
        ("rv HNSW efs=50", Some(hn(50)), None),
        ("rv HNSW efs=100", Some(hn(100)), None),
        ("rv HNSW efs=200", Some(hn(200)), None),
        (
            "rv HNSW + Turbo4",
            Some(hn(100)),
            Some(QuantizationConfig::Turbo4 {
                rotation_seed: 42,
                rescore_multiplier: 4,
                policy: Default::default(),
                search_quantization: Default::default(),
            }),
        ),
    ];

    for (name, hnsw, quant) in variants {
        let dir = format!("/home/martineserios/.claude/jobs/8e7be6c0/tmp/rv-spike/db-{}", name.replace([' ', '=', '+'], "_"));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let rss0 = rss_mb();
        let t = Instant::now();
        let db = match VectorDB::new(DbOptions {
            dimensions: DIM,
            distance_metric: DistanceMetric::Cosine,
            storage_path: format!("{dir}/rv.db"),
            hnsw_config: hnsw,
            quantization: quant,
        }) {
            Ok(d) => d,
            Err(e) => {
                println!("{name:<26} CREATE FAILED: {e}");
                continue;
            }
        };
        let entries: Vec<VectorEntry> = rows
            .iter()
            .map(|r| VectorEntry { id: Some(r.key.clone()), vector: r.vec.clone(), metadata: None })
            .collect();
        if let Err(e) = db.insert_batch(entries) {
            println!("{name:<26} INSERT FAILED: {e}");
            continue;
        }
        let build = t.elapsed().as_secs_f64();
        let rss = rss_mb() - rss0;

        let (mut o5, mut o10, mut lat) = (0.0, 0.0, Vec::new());
        let mut failed = 0;
        for (i, (_, q)) in qs.iter().enumerate() {
            let t = Instant::now();
            let res = db.search(SearchQuery { vector: q.clone(), k: 10, filter: None, ef_search: None });
            lat.push(t.elapsed().as_secs_f64() * 1e6);
            let Ok(res) = res else { failed += 1; continue };
            let got: Vec<&str> = res.iter().map(|r| r.id.as_str()).collect();
            let t5: HashSet<&str> = truth[i].iter().take(5).map(|s| s.as_str()).collect();
            let t10: HashSet<&str> = truth[i].iter().map(|s| s.as_str()).collect();
            o5 += got.iter().take(5).filter(|g| t5.contains(**g)).count() as f64 / 5.0;
            o10 += got.iter().take(10).filter(|g| t10.contains(**g)).count() as f64 / 10.0;
        }
        let n = qs.len() as f64;
        println!(
            "{name:<26} build {build:>5.1}s   query p50 {:>8.0} us   overlap@5 = {:.3}  overlap@10 = {:.3}   +{:.0} MB RSS{}",
            median(lat), o5 / n, o10 / n, rss,
            if failed > 0 { format!("   ({failed} queries errored)") } else { String::new() }
        );
        drop(db);
        let _ = std::fs::remove_dir_all(&dir);
    }
}

fn hn(ef_search: usize) -> HnswConfig {
    HnswConfig { m: 16, ef_construction: 100, ef_search, max_elements: 50_000 }
}
