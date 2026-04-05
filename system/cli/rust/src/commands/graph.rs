//! `brana graph` — ontology-aware knowledge graph builder.
//!
//! Replaces system/scripts/spec_graph.py with a native Rust implementation.
//! Reads brana-ontology.yaml, walks markdown docs, extracts frontmatter
//! relationships and markdown links, produces typed nodes + typed edges
//! in docs/spec-graph.json.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};

use chrono::Utc;
use serde::{Deserialize, Serialize};

use crate::cli::GraphCmd;
use crate::util::find_project_root;

// ── Ontology types ───────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct Ontology {
    types: Vec<OntologyType>,
    relationships: Vec<OntologyRel>,
    axioms: Vec<OntologyAxiom>,
    #[allow(dead_code)]
    dimension_classes: Option<serde_yaml::Value>,
}

#[derive(Debug, Deserialize)]
struct OntologyType {
    name: String,
    #[allow(dead_code)]
    description: String,
    location: Option<String>,
    status: String,
}

#[derive(Debug, Deserialize)]
struct OntologyRel {
    name: String,
    #[allow(dead_code)]
    description: String,
    properties: Option<serde_yaml::Value>,
    status: String,
}

#[derive(Debug, Deserialize)]
struct OntologyAxiom {
    id: String,
    rule: String,
    #[allow(dead_code)]
    formal: String,
}

// ── Graph JSON types ─────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
struct SpecGraph {
    generated: String,
    generator: String,
    ontology_version: String,
    nodes: BTreeMap<String, GraphNode>,
    edges: Vec<GraphEdge>,
    stats: GraphStats,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct GraphNode {
    title: String,
    #[serde(rename = "type")]
    node_type: String,
    impl_files: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct GraphEdge {
    from: String,
    to: String,
    #[serde(rename = "type")]
    edge_type: String,
    computed: bool,
}

#[derive(Debug, Serialize, Deserialize)]
struct GraphStats {
    nodes: usize,
    edges: usize,
    typed_edges: usize,
    orphans: usize,
}

// ── Entry point ──────────────────────────────────────────────────────

pub fn cmd_graph(cmd: GraphCmd) {
    match cmd {
        GraphCmd::Build { output } => cmd_build(output),
        GraphCmd::Orphans => cmd_orphans(),
        GraphCmd::Query { node_type, rel } => cmd_query(node_type, rel),
        GraphCmd::Path { from, to } => cmd_path(&from, &to),
        GraphCmd::Stats => cmd_stats(),
        GraphCmd::Validate => cmd_validate(),
    }
}

// ── Build ────────────────────────────────────────────────────────────

fn require_root() -> PathBuf {
    find_project_root().unwrap_or_else(|| {
        eprintln!("Not in a git repo");
        std::process::exit(1);
    })
}

fn cmd_build(output: Option<PathBuf>) {
    let root = require_root();
    let ontology = load_ontology(&root);
    let graph = build_graph(&root, &ontology);

    let out_path = output.unwrap_or_else(|| root.join("docs/spec-graph.json"));
    let json = serde_json::to_string_pretty(&graph).expect("JSON serialize");
    fs::write(&out_path, format!("{json}\n")).unwrap_or_else(|e| {
        eprintln!("Failed to write {}: {e}", out_path.display());
        std::process::exit(1);
    });

    println!(
        "spec-graph: {} nodes, {} edges ({} typed), {} orphans -> {}",
        graph.stats.nodes,
        graph.stats.edges,
        graph.stats.typed_edges,
        graph.stats.orphans,
        out_path.display()
    );
}

fn load_ontology(root: &Path) -> Ontology {
    let path = root.join("docs/brana-ontology.yaml");
    let content = fs::read_to_string(&path).unwrap_or_else(|e| {
        eprintln!("Cannot read ontology at {}: {e}", path.display());
        std::process::exit(1);
    });
    serde_yaml::from_str(&content).unwrap_or_else(|e| {
        eprintln!("Cannot parse ontology YAML: {e}");
        std::process::exit(1);
    })
}

/// Classify a doc path into an ontology type name.
fn classify_node(path: &str, ontology: &Ontology) -> String {
    // Match based on ontology type locations
    for t in &ontology.types {
        if t.status != "active" {
            continue;
        }
        if let Some(loc) = &t.location {
            // Normalize: location may be like "docs/reflections/" or "brana-knowledge/dimensions/"
            if path.contains(loc.trim_end_matches('/')) {
                return t.name.clone();
            }
        }
    }
    // Fallback heuristics
    if path.contains("dimensions/") || path.contains("brana-knowledge/") {
        return "Dimension".to_string();
    }
    if path.contains("reflections/") {
        return "Reflection".to_string();
    }
    if path.contains("decisions/") || path.starts_with("docs/architecture/decisions/") {
        return "ADR".to_string();
    }
    if path.contains("architecture/") {
        return "Roadmap".to_string();
    }
    "Roadmap".to_string()
}

/// Extract title from first `# ...` line in content.
fn extract_title(content: &str) -> String {
    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("# ") {
            return rest.trim().to_string();
        }
    }
    String::new()
}

/// Parse YAML frontmatter between `---` markers.
/// Returns (key, values) pairs for relationship fields.
fn parse_frontmatter(content: &str) -> HashMap<String, Vec<String>> {
    let mut rels: HashMap<String, Vec<String>> = HashMap::new();

    let trimmed = content.trim_start();
    if !trimmed.starts_with("---") {
        return rels;
    }

    // Find second ---
    let after_first = &trimmed[3..];
    let end = match after_first.find("\n---") {
        Some(i) => i,
        None => return rels,
    };
    let fm_block = &after_first[..end];

    let rel_keys = ["depends_on", "informs", "supersedes", "contradicts", "implements", "blocked_by"];

    for line in fm_block.lines() {
        let line = line.trim();
        for key in &rel_keys {
            if let Some(rest) = line.strip_prefix(&format!("{key}:")) {
                let rest = rest.trim();
                // Parse YAML inline list: [a, b, c] or single value
                if rest.starts_with('[') {
                    let inner = rest.trim_start_matches('[').trim_end_matches(']');
                    for item in inner.split(',') {
                        let item = item.trim().trim_matches('"').trim_matches('\'').trim();
                        if !item.is_empty() {
                            rels.entry(key.to_string())
                                .or_default()
                                .push(item.to_string());
                        }
                    }
                } else if !rest.is_empty() {
                    rels.entry(key.to_string())
                        .or_default()
                        .push(rest.trim_matches('"').trim_matches('\'').to_string());
                }
            }
        }
    }

    rels
}

/// Extract markdown links [text](path) and [[wikilinks]] from content, skipping fenced code.
/// Returns (doc_refs, impl_files, typed_edges).
fn extract_links(
    content: &str,
    source_path: &str,
    root: &Path,
) -> (Vec<String>, Vec<String>, Vec<(String, String)>) {
    let link_re = regex_lite::Regex::new(r"\[([^\]]*)\]\(([^)]+)\)").unwrap();
    let wikilink_re = regex_lite::Regex::new(r"\[\[([^\]]+)\]\]").unwrap();
    let system_re = regex_lite::Regex::new(r#"system/[^\s,)}\]"']+"#).unwrap();
    // Typed link: [Label type](path.md)
    let typed_re = regex_lite::Regex::new(
        r"\[([^\]]+)\s+(assumes|implements|informs|enriches|supersedes)\]\(([^)]+)\)",
    )
    .unwrap();

    let mut doc_refs: Vec<String> = Vec::new();
    let mut impl_files: Vec<String> = Vec::new();
    let mut typed_edges: Vec<(String, String)> = Vec::new(); // (rel_type, target)

    let mut in_fence = false;

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("```") || trimmed.starts_with("~~~") {
            in_fence = !in_fence;
            continue;
        }
        if in_fence {
            continue;
        }

        // Typed links first
        for cap in typed_re.captures_iter(line) {
            let rel_type = cap.get(2).unwrap().as_str().to_string();
            let raw_target = cap.get(3).unwrap().as_str().trim();
            if raw_target.starts_with("http://") || raw_target.starts_with("https://") || raw_target.starts_with('#') {
                continue;
            }
            let target = raw_target.split('#').next().unwrap_or("");
            if target.is_empty() {
                continue;
            }
            if let Some(resolved) = resolve_path(target, source_path, root) {
                typed_edges.push((rel_type, resolved));
            }
        }

        // Standard markdown links
        for cap in link_re.captures_iter(line) {
            let raw_target = cap.get(2).unwrap().as_str().trim();
            if raw_target.starts_with("http://") || raw_target.starts_with("https://") || raw_target.starts_with('#') {
                continue;
            }
            let target = raw_target.split('#').next().unwrap_or("");
            if target.is_empty() || target.contains('*') || target.contains('{') {
                continue;
            }
            if let Some(resolved) = resolve_path(target, source_path, root) {
                if resolved.contains("system/") {
                    impl_files.push(resolved);
                } else {
                    doc_refs.push(resolved);
                }
            }
        }

        // Wikilinks
        for cap in wikilink_re.captures_iter(line) {
            let target = cap.get(1).unwrap().as_str().trim();
            if !target.is_empty() {
                // Wikilinks are usually just filenames — add .md if needed
                let t = if target.ends_with(".md") {
                    target.to_string()
                } else {
                    format!("{target}.md")
                };
                doc_refs.push(t);
            }
        }

        // Inline system/ mentions
        for m in system_re.find_iter(line) {
            let s = m.as_str();
            // Skip if already captured inside a markdown link
            if line.contains(&format!("]({s})")) {
                continue;
            }
            let cleaned = s.trim_end_matches(|c: char| ".,;:!?\"'`~\\".contains(c));
            if !cleaned.is_empty() && !cleaned.contains('*') {
                impl_files.push(cleaned.to_string());
            }
        }
    }

    // Dedup preserving order
    doc_refs = dedup(doc_refs);
    impl_files = dedup(impl_files);

    (doc_refs, impl_files, typed_edges)
}

fn dedup(items: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
    items
        .into_iter()
        .filter(|i| seen.insert(i.clone()))
        .collect()
}

/// Resolve a link target to a repo-root-relative path.
fn resolve_path(target: &str, source_path: &str, root: &Path) -> Option<String> {
    if target.starts_with('~') {
        // Expand ~ paths
        let home = std::env::var("HOME").unwrap_or_default();
        let expanded = target.replacen('~', &home, 1);
        let expanded = PathBuf::from(&expanded);
        let root_resolved = root.canonicalize().unwrap_or_else(|_| root.to_path_buf());
        if let Ok(rel) = expanded.strip_prefix(&root_resolved) {
            return Some(rel.to_string_lossy().to_string());
        }
        // Check if it's in brana-knowledge
        let bk = root_resolved.parent()?.join("brana-knowledge");
        if let Ok(rel) = expanded.strip_prefix(&bk) {
            return Some(format!("brana-knowledge/{}", rel.to_string_lossy()));
        }
        return None;
    }

    if !target.starts_with('.') {
        // Already repo-root-relative or dimensions/...
        return Some(target.to_string());
    }

    // Relative path: resolve from source file's parent
    let source_dir = Path::new(source_path).parent().unwrap_or(Path::new(""));
    let joined = source_dir.join(target);
    // Normalize (collapse ..)
    let mut parts: Vec<&str> = Vec::new();
    for component in joined.components() {
        match component {
            std::path::Component::ParentDir => {
                parts.pop();
            }
            std::path::Component::CurDir => {}
            std::path::Component::Normal(s) => {
                parts.push(s.to_str().unwrap_or(""));
            }
            _ => {}
        }
    }
    if parts.is_empty() {
        None
    } else {
        Some(parts.join("/"))
    }
}

/// Collect all markdown files from docs/ and brana-knowledge/dimensions/.
fn collect_markdown_files(root: &Path) -> BTreeMap<String, PathBuf> {
    let mut found: BTreeMap<String, PathBuf> = BTreeMap::new();

    let scan_dirs = [
        ("docs", root.join("docs")),
        (
            "brana-knowledge/dimensions",
            root.parent()
                .unwrap_or(root)
                .join("brana-knowledge/dimensions"),
        ),
    ];

    for (prefix, dir) in &scan_dirs {
        if !dir.exists() {
            continue;
        }
        walk_md(dir, dir, prefix, &mut found);
    }

    // Also follow the docs/dimensions symlink if it exists
    let dim_link = root.join("docs/dimensions");
    if dim_link.exists() && dim_link.is_symlink() {
        if let Ok(real) = dim_link.canonicalize() {
            walk_md(&real, &real, "docs/dimensions", &mut found);
        }
    }

    found
}

fn walk_md(
    dir: &Path,
    base: &Path,
    prefix: &str,
    out: &mut BTreeMap<String, PathBuf>,
) {
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            walk_md(&path, base, prefix, out);
        } else if path.extension().is_some_and(|e| e == "md") {
            if let Ok(rel) = path.strip_prefix(base) {
                let key = format!("{prefix}/{}", rel.to_string_lossy());
                out.entry(key).or_insert(path);
            }
        }
    }
}

fn build_graph(root: &Path, ontology: &Ontology) -> SpecGraph {
    let md_files = collect_markdown_files(root);

    let mut nodes: BTreeMap<String, GraphNode> = BTreeMap::new();
    let mut edges: Vec<GraphEdge> = Vec::new();
    let mut edge_set: HashSet<(String, String, String)> = HashSet::new();

    // Active relationship names from ontology
    let active_rels: HashSet<String> = ontology
        .relationships
        .iter()
        .filter(|r| r.status == "active")
        .map(|r| r.name.clone())
        .collect();

    // Transitive relationships
    let transitive_rels: HashSet<String> = ontology
        .relationships
        .iter()
        .filter(|r| {
            r.properties
                .as_ref()
                .and_then(|p| p.as_mapping())
                .and_then(|m| m.get(serde_yaml::Value::String("transitive".into())))
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
        })
        .map(|r| r.name.clone())
        .collect();

    for (key, md_path) in &md_files {
        let content = match fs::read_to_string(md_path) {
            Ok(c) => c,
            Err(_) => continue,
        };

        let title = extract_title(&content);
        let node_type = classify_node(key, ontology);
        let fm_rels = parse_frontmatter(&content);
        let (doc_refs, impl_files, typed_links) = extract_links(&content, key, root);

        nodes.insert(
            key.clone(),
            GraphNode {
                title,
                node_type,
                impl_files,
            },
        );

        // Edges from frontmatter relationships
        for (rel_type, targets) in &fm_rels {
            if !active_rels.contains(rel_type) {
                continue;
            }
            for target in targets {
                // Target may be a bare number (e.g., "14") — try to resolve to a doc path
                let resolved = resolve_frontmatter_target(target, &md_files);
                if let Some(to) = resolved {
                    let triple = (key.clone(), to.clone(), rel_type.clone());
                    if edge_set.insert(triple) {
                        edges.push(GraphEdge {
                            from: key.clone(),
                            to,
                            edge_type: rel_type.clone(),
                            computed: false,
                        });
                    }
                }
            }
        }

        // Edges from typed markdown links
        for (rel_type, target) in &typed_links {
            if !active_rels.contains(rel_type) {
                continue;
            }
            let triple = (key.clone(), target.clone(), rel_type.clone());
            if edge_set.insert(triple) {
                edges.push(GraphEdge {
                    from: key.clone(),
                    to: target.clone(),
                    edge_type: rel_type.clone(),
                    computed: false,
                });
            }
        }

        // Untyped edges from markdown links
        for target in &doc_refs {
            let triple = (key.clone(), target.clone(), "references".to_string());
            if edge_set.insert(triple) {
                edges.push(GraphEdge {
                    from: key.clone(),
                    to: target.clone(),
                    edge_type: "references".to_string(),
                    computed: false,
                });
            }
        }
    }

    // Compute transitive closure for transitive relationships
    let mut computed_edges: Vec<GraphEdge> = Vec::new();
    for rel in &transitive_rels {
        // Build adjacency for this rel type
        let mut adj: HashMap<String, Vec<String>> = HashMap::new();
        for e in &edges {
            if &e.edge_type == rel && !e.computed {
                adj.entry(e.from.clone()).or_default().push(e.to.clone());
            }
        }
        // For each node with this rel, find all transitive targets
        for start in adj.keys().cloned().collect::<Vec<_>>() {
            let mut visited: HashSet<String> = HashSet::new();
            let mut queue: VecDeque<String> = VecDeque::new();
            // Seed with direct targets
            if let Some(directs) = adj.get(&start) {
                for d in directs {
                    visited.insert(d.clone());
                    queue.push_back(d.clone());
                }
            }
            while let Some(current) = queue.pop_front() {
                if let Some(nexts) = adj.get(&current) {
                    for n in nexts {
                        if visited.insert(n.clone()) {
                            queue.push_back(n.clone());
                            // This is a computed transitive edge
                            let triple = (start.clone(), n.clone(), rel.clone());
                            if edge_set.insert(triple) {
                                computed_edges.push(GraphEdge {
                                    from: start.clone(),
                                    to: n.clone(),
                                    edge_type: rel.clone(),
                                    computed: true,
                                });
                            }
                        }
                    }
                }
            }
        }
    }
    edges.extend(computed_edges);

    // Sort edges for deterministic output
    edges.sort_by(|a, b| {
        a.edge_type
            .cmp(&b.edge_type)
            .then(a.from.cmp(&b.from))
            .then(a.to.cmp(&b.to))
    });

    // Stats — compute before moving nodes/edges into SpecGraph
    let node_count = nodes.len();
    let edge_count = edges.len();
    let typed_count = edges.iter().filter(|e| e.edge_type != "references").count();

    let node_keys: HashSet<&String> = nodes.keys().collect();
    let mut nodes_with_edges: HashSet<&String> = HashSet::new();
    for e in &edges {
        if node_keys.contains(&e.from) {
            nodes_with_edges.insert(&e.from);
        }
        if node_keys.contains(&e.to) {
            nodes_with_edges.insert(&e.to);
        }
    }
    let orphan_count = node_count - nodes_with_edges.len();

    SpecGraph {
        generated: Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        generator: "brana graph build".to_string(),
        ontology_version: "1.5".to_string(),
        nodes,
        edges,
        stats: GraphStats {
            nodes: node_count,
            edges: edge_count,
            typed_edges: typed_count,
            orphans: orphan_count,
        },
    }
}

/// Resolve a frontmatter target like "14" or "knowledge-architecture" to a doc key.
fn resolve_frontmatter_target(
    target: &str,
    md_files: &BTreeMap<String, PathBuf>,
) -> Option<String> {
    // If it already looks like a path, return as-is
    if target.contains('/') || target.ends_with(".md") {
        return Some(target.to_string());
    }

    // Try to match by dimension number prefix (e.g., "14" matches "docs/dimensions/14-*.md")
    // or by name (e.g., "knowledge-architecture" matches that filename)
    for key in md_files.keys() {
        let filename = Path::new(key)
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("");

        // Exact filename match
        if filename == target {
            return Some(key.clone());
        }

        // Number prefix match: "14" matches "14-mastermind-architecture"
        if let Some(prefix) = filename.split('-').next() {
            if prefix == target {
                return Some(key.clone());
            }
        }
    }

    None
}

// ── Read existing graph ──────────────────────────────────────────────

fn load_graph() -> SpecGraph {
    let root = require_root();
    let path = root.join("docs/spec-graph.json");
    let content = fs::read_to_string(&path).unwrap_or_else(|e| {
        eprintln!("Cannot read {}: {e}", path.display());
        eprintln!("Run `brana graph build` first.");
        std::process::exit(1);
    });
    serde_json::from_str(&content).unwrap_or_else(|e| {
        eprintln!("Cannot parse spec-graph.json: {e}");
        std::process::exit(1);
    })
}

// ── Orphans ──────────────────────────────────────────────────────────

fn cmd_orphans() {
    let graph = load_graph();
    let mut connected: HashSet<&str> = HashSet::new();
    for e in &graph.edges {
        connected.insert(&e.from);
        connected.insert(&e.to);
    }

    let mut orphans: Vec<(&str, &GraphNode)> = graph
        .nodes
        .iter()
        .filter(|(k, _)| !connected.contains(k.as_str()))
        .map(|(k, v)| (k.as_str(), v))
        .collect();
    orphans.sort_by_key(|(k, _)| *k);

    if orphans.is_empty() {
        println!("No orphan nodes found.");
        return;
    }

    println!("\n  \x1b[1mOrphan nodes ({}):\x1b[0m\n", orphans.len());
    for (key, node) in &orphans {
        println!(
            "  \x1b[33m{}\x1b[0m  [{}]  {}",
            key, node.node_type, node.title
        );
    }
    println!();
}

// ── Query ────────────────────────────────────────────────────────────

fn cmd_query(node_type: Option<String>, rel: Option<String>) {
    let graph = load_graph();

    if let Some(ref nt) = node_type {
        let nt_lower = nt.to_lowercase();
        let matches: Vec<_> = graph
            .nodes
            .iter()
            .filter(|(_, v)| v.node_type.to_lowercase() == nt_lower)
            .collect();
        println!(
            "\n  \x1b[1mNodes of type '{}' ({}):\x1b[0m\n",
            nt,
            matches.len()
        );
        for (key, node) in &matches {
            println!("  {}  {}", key, node.title);
        }
        println!();
    }

    if let Some(ref r) = rel {
        let r_lower = r.to_lowercase();
        let matches: Vec<_> = graph
            .edges
            .iter()
            .filter(|e| e.edge_type.to_lowercase() == r_lower)
            .collect();
        println!(
            "\n  \x1b[1mEdges of type '{}' ({}):\x1b[0m\n",
            r,
            matches.len()
        );
        for e in &matches {
            let suffix = if e.computed { " (computed)" } else { "" };
            println!("  {} -> {}{}", e.from, e.to, suffix);
        }
        println!();
    }

    if node_type.is_none() && rel.is_none() {
        eprintln!("Provide --type and/or --rel to filter.");
        std::process::exit(1);
    }
}

// ── Path (BFS) ───────────────────────────────────────────────────────

fn cmd_path(from: &str, to: &str) {
    let graph = load_graph();

    // Fuzzy match node keys
    let from_key = fuzzy_match_key(from, &graph.nodes);
    let to_key = fuzzy_match_key(to, &graph.nodes);

    let from_key = from_key.unwrap_or_else(|| {
        eprintln!("No node matching '{from}'");
        std::process::exit(1);
    });
    let to_key = to_key.unwrap_or_else(|| {
        eprintln!("No node matching '{to}'");
        std::process::exit(1);
    });

    // Build undirected adjacency
    let mut adj: HashMap<&str, Vec<(&str, &str)>> = HashMap::new(); // node -> [(neighbor, edge_type)]
    for e in &graph.edges {
        adj.entry(e.from.as_str())
            .or_default()
            .push((e.to.as_str(), e.edge_type.as_str()));
        adj.entry(e.to.as_str())
            .or_default()
            .push((e.from.as_str(), e.edge_type.as_str()));
    }

    // BFS
    let mut visited: HashSet<&str> = HashSet::new();
    let mut queue: VecDeque<&str> = VecDeque::new();
    let mut parent: HashMap<&str, (&str, &str)> = HashMap::new(); // node -> (prev, edge_type)

    visited.insert(from_key.as_str());
    queue.push_back(from_key.as_str());

    let mut found = false;
    while let Some(current) = queue.pop_front() {
        if current == to_key {
            found = true;
            break;
        }
        if let Some(neighbors) = adj.get(current) {
            for &(next, etype) in neighbors {
                if visited.insert(next) {
                    parent.insert(next, (current, etype));
                    queue.push_back(next);
                }
            }
        }
    }

    if !found {
        println!("No path from '{from_key}' to '{to_key}'.");
        return;
    }

    // Reconstruct path
    let mut path_nodes: Vec<&str> = vec![to_key.as_str()];
    let mut path_edges: Vec<&str> = Vec::new();
    let mut cur = to_key.as_str();
    while let Some(&(prev, etype)) = parent.get(cur) {
        path_nodes.push(prev);
        path_edges.push(etype);
        cur = prev;
    }
    path_nodes.reverse();
    path_edges.reverse();

    println!("\n  \x1b[1mPath ({} hops):\x1b[0m\n", path_edges.len());
    for (i, node) in path_nodes.iter().enumerate() {
        let title = graph
            .nodes
            .get(*node)
            .map(|n| n.title.as_str())
            .unwrap_or("");
        println!("  \x1b[36m{node}\x1b[0m  {title}");
        if i < path_edges.len() {
            println!("    \x1b[33m--[{}]-->\x1b[0m", path_edges[i]);
        }
    }
    println!();
}

fn fuzzy_match_key(query: &str, nodes: &BTreeMap<String, GraphNode>) -> Option<String> {
    // Exact match first
    if nodes.contains_key(query) {
        return Some(query.to_string());
    }
    // Contains match
    let matches: Vec<&String> = nodes.keys().filter(|k| k.contains(query)).collect();
    if matches.len() == 1 {
        return Some(matches[0].clone());
    }
    // Filename-only match
    let matches: Vec<&String> = nodes
        .keys()
        .filter(|k| {
            Path::new(k.as_str())
                .file_name()
                .is_some_and(|f| f.to_string_lossy().contains(query))
        })
        .collect();
    if matches.len() == 1 {
        return Some(matches[0].clone());
    }
    if matches.len() > 1 {
        eprintln!("Ambiguous match for '{query}':");
        for m in &matches[..matches.len().min(5)] {
            eprintln!("  {m}");
        }
        return None;
    }
    None
}

// ── Stats ────────────────────────────────────────────────────────────

fn cmd_stats() {
    let graph = load_graph();

    // Counts by node type
    let mut type_counts: BTreeMap<&str, usize> = BTreeMap::new();
    for node in graph.nodes.values() {
        *type_counts.entry(&node.node_type).or_default() += 1;
    }

    // Counts by edge type
    let mut edge_counts: BTreeMap<&str, usize> = BTreeMap::new();
    let mut computed_count = 0usize;
    for edge in &graph.edges {
        *edge_counts.entry(&edge.edge_type).or_default() += 1;
        if edge.computed {
            computed_count += 1;
        }
    }

    println!("\n  \x1b[1mSpec Graph Statistics\x1b[0m");
    println!("  Generated: {}", graph.generated);
    println!("  Ontology:  v{}", graph.ontology_version);
    println!();
    println!("  \x1b[1mNodes ({}):\x1b[0m", graph.stats.nodes);
    for (t, count) in &type_counts {
        println!("    {t:<20} {count}");
    }
    println!();
    println!("  \x1b[1mEdges ({}):\x1b[0m", graph.stats.edges);
    for (t, count) in &edge_counts {
        println!("    {t:<20} {count}");
    }
    if computed_count > 0 {
        println!("    (computed)          {computed_count}");
    }
    println!();
    println!("  Orphans: {}", graph.stats.orphans);
    println!();
}

// ── Validate ─────────────────────────────────────────────────────────

fn cmd_validate() {
    let root = require_root();
    let ontology = load_ontology(&root);
    let graph = load_graph();
    let mut issues: Vec<String> = Vec::new();

    // 1. Orphan detection (axiom: orphan_detection)
    {
        let mut connected: HashSet<&str> = HashSet::new();
        for e in &graph.edges {
            connected.insert(&e.from);
            connected.insert(&e.to);
        }
        let orphan_count = graph
            .nodes
            .keys()
            .filter(|k| !connected.contains(k.as_str()))
            .count();
        if orphan_count > 0 {
            issues.push(format!(
                "orphan_detection: {orphan_count} nodes have zero edges"
            ));
        }
    }

    // 2. Supersession chain completeness (axiom: supersession_chain)
    {
        let supersedes_edges: Vec<_> = graph
            .edges
            .iter()
            .filter(|e| e.edge_type == "supersedes" && !e.computed)
            .collect();
        for e in &supersedes_edges {
            // The superseded doc should not itself be a source of non-computed supersedes
            // unless there's a chain (which is valid). Check that the target exists.
            if !graph.nodes.contains_key(&e.to) {
                issues.push(format!(
                    "supersession_chain: {} supersedes {} but target not in graph",
                    e.from, e.to
                ));
            }
        }
    }

    // 3. Transitivity: check that depends_on has computed transitive edges
    {
        let has_computed = graph
            .edges
            .iter()
            .any(|e| e.edge_type == "depends_on" && e.computed);
        let has_direct = graph
            .edges
            .iter()
            .any(|e| e.edge_type == "depends_on" && !e.computed);
        // Only warn if there are direct edges but no computed ones — might indicate
        // build was run without transitivity
        if has_direct && !has_computed {
            // Check if there are actual chains
            let mut adj: HashMap<&str, Vec<&str>> = HashMap::new();
            for e in &graph.edges {
                if e.edge_type == "depends_on" && !e.computed {
                    adj.entry(e.from.as_str())
                        .or_default()
                        .push(e.to.as_str());
                }
            }
            let mut has_chain = false;
            for targets in adj.values() {
                for t in targets {
                    if adj.contains_key(t) {
                        has_chain = true;
                        break;
                    }
                }
                if has_chain {
                    break;
                }
            }
            if has_chain {
                issues.push(
                    "transitivity: depends_on chains exist but no computed transitive edges found"
                        .to_string(),
                );
            }
        }
    }

    // 4. Unknown edge types (not in ontology)
    {
        let known_rels: BTreeSet<String> = ontology
            .relationships
            .iter()
            .map(|r| r.name.clone())
            .collect();
        let mut unknown: BTreeSet<&str> = BTreeSet::new();
        for e in &graph.edges {
            if e.edge_type != "references" && !known_rels.contains(&e.edge_type) {
                unknown.insert(&e.edge_type);
            }
        }
        for u in &unknown {
            issues.push(format!("unknown_relationship: edge type '{u}' not in ontology"));
        }
    }

    // Report
    if issues.is_empty() {
        println!("\n  \x1b[32mAll axiom checks passed.\x1b[0m\n");
    } else {
        println!(
            "\n  \x1b[1mValidation issues ({}):\x1b[0m\n",
            issues.len()
        );
        for issue in &issues {
            println!("  \x1b[33m!\x1b[0m {issue}");
        }
        println!();

        // Print axiom reference
        println!("  \x1b[2mAxioms checked:\x1b[0m");
        for axiom in &ontology.axioms {
            println!("  \x1b[2m  {}: {}\x1b[0m", axiom.id, axiom.rule);
        }
        println!();
    }
}
