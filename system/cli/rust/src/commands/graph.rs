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

    let mut current_key: Option<String> = None;

    for line in fm_block.lines() {
        let trimmed = line.trim();

        // Check if this line starts a new relationship key
        let mut matched_key = false;
        for key in &rel_keys {
            if let Some(rest) = trimmed.strip_prefix(&format!("{key}:")) {
                let rest = rest.trim();
                current_key = Some(key.to_string());
                matched_key = true;
                // Parse YAML inline list: [a, b, c] or single value on same line
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
                    current_key = None; // inline list complete
                } else if !rest.is_empty() {
                    rels.entry(key.to_string())
                        .or_default()
                        .push(rest.trim_matches('"').trim_matches('\'').to_string());
                    current_key = None; // single value complete
                }
                // else: empty value means YAML list follows (- item lines)
                break;
            }
        }

        // Parse YAML list items: "  - value"
        if !matched_key {
            if let Some(ref key) = current_key {
                if let Some(item) = trimmed.strip_prefix("- ") {
                    let item = item.trim().trim_matches('"').trim_matches('\'').trim();
                    if !item.is_empty() {
                        rels.entry(key.clone()).or_default().push(item.to_string());
                    }
                } else if !trimmed.is_empty() && !trimmed.starts_with('#') {
                    // Non-list, non-empty line — end of current key's list
                    current_key = None;
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

// ── Testable helpers extracted from commands ────────────────────────

/// Find orphan nodes (nodes with zero edges) in a graph.
/// Returns sorted list of orphan node keys.
fn find_orphans(graph: &SpecGraph) -> Vec<String> {
    let mut connected: HashSet<&str> = HashSet::new();
    for e in &graph.edges {
        connected.insert(&e.from);
        connected.insert(&e.to);
    }
    let mut orphans: Vec<String> = graph
        .nodes
        .keys()
        .filter(|k| !connected.contains(k.as_str()))
        .cloned()
        .collect();
    orphans.sort();
    orphans
}

/// BFS shortest path between two nodes (undirected).
/// Returns the sequence of node keys from `from` to `to`, or None.
fn bfs_path(graph: &SpecGraph, from: &str, to: &str) -> Option<Vec<String>> {
    let mut adj: HashMap<&str, Vec<&str>> = HashMap::new();
    for e in &graph.edges {
        adj.entry(e.from.as_str()).or_default().push(e.to.as_str());
        adj.entry(e.to.as_str()).or_default().push(e.from.as_str());
    }

    let mut visited: HashSet<&str> = HashSet::new();
    let mut queue: VecDeque<&str> = VecDeque::new();
    let mut parent: HashMap<&str, &str> = HashMap::new();

    visited.insert(from);
    queue.push_back(from);

    let mut found = false;
    while let Some(current) = queue.pop_front() {
        if current == to {
            found = true;
            break;
        }
        if let Some(neighbors) = adj.get(current) {
            for &next in neighbors {
                if visited.insert(next) {
                    parent.insert(next, current);
                    queue.push_back(next);
                }
            }
        }
    }

    if !found {
        return None;
    }

    let mut path = vec![to.to_string()];
    let mut cur = to;
    while let Some(&prev) = parent.get(cur) {
        path.push(prev.to_string());
        cur = prev;
    }
    path.reverse();
    Some(path)
}

/// Compute transitive closure for a specific relationship type.
/// Returns computed edges (from, to) that are transitively reachable.
fn transitive_closure(edges: &[GraphEdge], rel_type: &str) -> Vec<(String, String)> {
    let mut adj: HashMap<&str, Vec<&str>> = HashMap::new();
    for e in edges {
        if e.edge_type == rel_type && !e.computed {
            adj.entry(e.from.as_str()).or_default().push(e.to.as_str());
        }
    }

    let mut computed: Vec<(String, String)> = Vec::new();
    let mut edge_set: HashSet<(String, String)> = HashSet::new();

    // Seed edge_set with direct edges
    for e in edges {
        if e.edge_type == rel_type && !e.computed {
            edge_set.insert((e.from.clone(), e.to.clone()));
        }
    }

    for start in adj.keys().cloned().collect::<Vec<_>>() {
        let mut visited: HashSet<&str> = HashSet::new();
        let mut queue: VecDeque<&str> = VecDeque::new();
        if let Some(directs) = adj.get(start) {
            for d in directs {
                visited.insert(d);
                queue.push_back(d);
            }
        }
        while let Some(current) = queue.pop_front() {
            if let Some(nexts) = adj.get(current) {
                for n in nexts {
                    if visited.insert(n) {
                        queue.push_back(n);
                        let pair = (start.to_string(), n.to_string());
                        if edge_set.insert(pair.clone()) {
                            computed.push(pair);
                        }
                    }
                }
            }
        }
    }

    computed
}

/// Validate: detect unknown edge types not in a given set of known relationship names.
fn find_unknown_edge_types<'a>(
    edges: &'a [GraphEdge],
    known_rels: &HashSet<String>,
) -> BTreeSet<&'a str> {
    let mut unknown: BTreeSet<&str> = BTreeSet::new();
    for e in edges {
        if e.edge_type != "references" && !known_rels.contains(&e.edge_type) {
            unknown.insert(&e.edge_type);
        }
    }
    unknown
}

/// Validate: detect supersession chain gaps (target not in graph).
fn find_supersession_gaps(graph: &SpecGraph) -> Vec<(String, String)> {
    let mut gaps = Vec::new();
    for e in &graph.edges {
        if e.edge_type == "supersedes" && !e.computed && !graph.nodes.contains_key(&e.to) {
            gaps.push((e.from.clone(), e.to.clone()));
        }
    }
    gaps
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

// ── Tests ───────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // ── Helpers ─────────────────────────────────────────────────────

    fn make_graph(
        nodes: Vec<(&str, &str)>,
        edges: Vec<(&str, &str, &str, bool)>,
    ) -> SpecGraph {
        let mut node_map = BTreeMap::new();
        for (key, ntype) in nodes {
            node_map.insert(
                key.to_string(),
                GraphNode {
                    title: key.to_string(),
                    node_type: ntype.to_string(),
                    impl_files: vec![],
                },
            );
        }
        let edge_list: Vec<GraphEdge> = edges
            .into_iter()
            .map(|(from, to, etype, computed)| GraphEdge {
                from: from.to_string(),
                to: to.to_string(),
                edge_type: etype.to_string(),
                computed,
            })
            .collect();
        let node_count = node_map.len();
        let edge_count = edge_list.len();
        SpecGraph {
            generated: "test".to_string(),
            generator: "test".to_string(),
            ontology_version: "1.0".to_string(),
            nodes: node_map,
            edges: edge_list,
            stats: GraphStats {
                nodes: node_count,
                edges: edge_count,
                typed_edges: 0,
                orphans: 0,
            },
        }
    }

    fn make_ontology(
        types: Vec<(&str, Option<&str>, &str)>,
        rels: Vec<(&str, &str, bool)>,
        axioms: Vec<(&str, &str, &str)>,
    ) -> Ontology {
        Ontology {
            types: types
                .into_iter()
                .map(|(name, loc, status)| OntologyType {
                    name: name.to_string(),
                    description: String::new(),
                    location: loc.map(|s| s.to_string()),
                    status: status.to_string(),
                })
                .collect(),
            relationships: rels
                .into_iter()
                .map(|(name, status, transitive)| {
                    let props = if transitive {
                        let mut map = serde_yaml::Mapping::new();
                        map.insert(
                            serde_yaml::Value::String("transitive".into()),
                            serde_yaml::Value::Bool(true),
                        );
                        Some(serde_yaml::Value::Mapping(map))
                    } else {
                        None
                    };
                    OntologyRel {
                        name: name.to_string(),
                        description: String::new(),
                        properties: props,
                        status: status.to_string(),
                    }
                })
                .collect(),
            axioms: axioms
                .into_iter()
                .map(|(id, rule, formal)| OntologyAxiom {
                    id: id.to_string(),
                    rule: rule.to_string(),
                    formal: formal.to_string(),
                })
                .collect(),
            dimension_classes: None,
        }
    }

    // ── Frontmatter parsing ────────────────────────────────────────

    #[test]
    fn parse_frontmatter_with_typed_relationships() {
        let content = r#"---
title: Test Doc
depends_on: [14, 18]
informs: "32"
supersedes: '08'
---
# Test Doc
Body text here.
"#;
        let rels = parse_frontmatter(content);
        assert_eq!(rels.get("depends_on").unwrap(), &vec!["14", "18"]);
        assert_eq!(rels.get("informs").unwrap(), &vec!["32"]);
        assert_eq!(rels.get("supersedes").unwrap(), &vec!["08"]);
    }

    #[test]
    fn parse_frontmatter_no_frontmatter() {
        let content = "# Just a heading\nSome text.";
        let rels = parse_frontmatter(content);
        assert!(rels.is_empty());
    }

    #[test]
    fn parse_frontmatter_with_frontmatter_but_no_relationships() {
        let content = "---\ntitle: My Doc\nauthor: Test\n---\n# My Doc\nBody.";
        let rels = parse_frontmatter(content);
        assert!(rels.is_empty());
    }

    #[test]
    fn parse_frontmatter_single_value_no_brackets() {
        let content = "---\ndepends_on: 14\n---\n# Doc";
        let rels = parse_frontmatter(content);
        assert_eq!(rels.get("depends_on").unwrap(), &vec!["14"]);
    }

    #[test]
    fn parse_frontmatter_empty_list() {
        let content = "---\ndepends_on: []\n---\n# Doc";
        let rels = parse_frontmatter(content);
        // Empty list should not produce entries
        assert!(rels.get("depends_on").is_none() || rels.get("depends_on").unwrap().is_empty());
    }

    #[test]
    fn parse_frontmatter_unclosed_frontmatter() {
        let content = "---\ndepends_on: [14]\n# No closing fence";
        let rels = parse_frontmatter(content);
        assert!(rels.is_empty());
    }

    // ── Title extraction ───────────────────────────────────────────

    #[test]
    fn extract_title_from_h1() {
        assert_eq!(extract_title("# My Title\nSome text"), "My Title");
    }

    #[test]
    fn extract_title_with_frontmatter() {
        let content = "---\ntitle: fm\n---\n# Actual Title\nBody";
        assert_eq!(extract_title(content), "Actual Title");
    }

    #[test]
    fn extract_title_no_heading() {
        assert_eq!(extract_title("Just text\nno heading"), "");
    }

    #[test]
    fn extract_title_ignores_h2() {
        assert_eq!(extract_title("## Not H1\n# Real Title"), "Real Title");
    }

    // ── Link extraction ────────────────────────────────────────────

    #[test]
    fn extract_standard_markdown_links() {
        let content = "See [doc](other.md) and [another](sub/deep.md).";
        let root = Path::new("/fake/root");
        let (doc_refs, impl_files, typed) = extract_links(content, "docs/test.md", root);
        assert!(doc_refs.contains(&"other.md".to_string()));
        assert!(doc_refs.contains(&"sub/deep.md".to_string()));
        assert!(impl_files.is_empty());
        assert!(typed.is_empty());
    }

    #[test]
    fn extract_wikilinks() {
        let content = "See [[some-doc]] and [[other-doc.md]].";
        let root = Path::new("/fake/root");
        let (doc_refs, _, _) = extract_links(content, "docs/test.md", root);
        assert!(doc_refs.contains(&"some-doc.md".to_string()));
        assert!(doc_refs.contains(&"other-doc.md".to_string()));
    }

    #[test]
    fn extract_links_ignores_external_urls() {
        let content = "See [ext](https://example.com) and [http](http://foo.bar).";
        let root = Path::new("/fake/root");
        let (doc_refs, impl_files, _) = extract_links(content, "docs/test.md", root);
        assert!(doc_refs.is_empty());
        assert!(impl_files.is_empty());
    }

    #[test]
    fn extract_links_ignores_anchor_only() {
        let content = "See [section](#heading).";
        let root = Path::new("/fake/root");
        let (doc_refs, _, _) = extract_links(content, "docs/test.md", root);
        assert!(doc_refs.is_empty());
    }

    #[test]
    fn extract_links_resolves_relative_paths() {
        let content = "See [parent](../other.md).";
        let root = Path::new("/fake/root");
        let (doc_refs, _, _) = extract_links(content, "docs/sub/test.md", root);
        assert!(doc_refs.contains(&"docs/other.md".to_string()));
    }

    #[test]
    fn extract_links_skips_fenced_code() {
        let content = "Text\n```\n[link](inside-fence.md)\n```\n[real](outside.md)";
        let root = Path::new("/fake/root");
        let (doc_refs, _, _) = extract_links(content, "docs/test.md", root);
        assert!(!doc_refs.contains(&"inside-fence.md".to_string()));
        assert!(doc_refs.contains(&"outside.md".to_string()));
    }

    #[test]
    fn extract_links_system_files_go_to_impl() {
        let content = "See [hook](system/hooks/foo.sh).";
        let root = Path::new("/fake/root");
        let (doc_refs, impl_files, _) = extract_links(content, "docs/test.md", root);
        assert!(doc_refs.is_empty());
        assert!(impl_files.contains(&"system/hooks/foo.sh".to_string()));
    }

    #[test]
    fn extract_typed_markdown_links() {
        let content = "[Doc A supersedes](old-doc.md)";
        let root = Path::new("/fake/root");
        let (_, _, typed) = extract_links(content, "docs/test.md", root);
        assert_eq!(typed.len(), 1);
        assert_eq!(typed[0].0, "supersedes");
        assert_eq!(typed[0].1, "old-doc.md");
    }

    #[test]
    fn extract_links_deduplicates() {
        let content = "[a](same.md) and [b](same.md)";
        let root = Path::new("/fake/root");
        let (doc_refs, _, _) = extract_links(content, "docs/test.md", root);
        assert_eq!(doc_refs.iter().filter(|r| *r == "same.md").count(), 1);
    }

    // ── Node type detection ────────────────────────────────────────

    #[test]
    fn classify_node_dimension() {
        let ontology = make_ontology(
            vec![("Dimension", Some("brana-knowledge/dimensions/"), "active")],
            vec![],
            vec![],
        );
        assert_eq!(classify_node("brana-knowledge/dimensions/01-foo.md", &ontology), "Dimension");
    }

    #[test]
    fn classify_node_adr() {
        let ontology = make_ontology(
            vec![("ADR", Some("docs/architecture/decisions/"), "active")],
            vec![],
            vec![],
        );
        assert_eq!(classify_node("docs/architecture/decisions/001-foo.md", &ontology), "ADR");
    }

    #[test]
    fn classify_node_reflection() {
        let ontology = make_ontology(
            vec![("Reflection", Some("docs/reflections/"), "active")],
            vec![],
            vec![],
        );
        assert_eq!(classify_node("docs/reflections/31-assurance.md", &ontology), "Reflection");
    }

    #[test]
    fn classify_node_docs_root_fallback() {
        // Empty ontology types → fallback heuristics
        let ontology = make_ontology(vec![], vec![], vec![]);
        assert_eq!(classify_node("docs/18-lean-roadmap.md", &ontology), "Roadmap");
    }

    #[test]
    fn classify_node_fallback_decisions() {
        let ontology = make_ontology(vec![], vec![], vec![]);
        assert_eq!(classify_node("docs/architecture/decisions/001.md", &ontology), "ADR");
    }

    #[test]
    fn classify_node_fallback_dimensions() {
        let ontology = make_ontology(vec![], vec![], vec![]);
        assert_eq!(classify_node("brana-knowledge/dimensions/foo.md", &ontology), "Dimension");
    }

    #[test]
    fn classify_node_fallback_reflections() {
        let ontology = make_ontology(vec![], vec![], vec![]);
        assert_eq!(classify_node("docs/reflections/08-triage.md", &ontology), "Reflection");
    }

    #[test]
    fn classify_node_inactive_type_skipped() {
        let ontology = make_ontology(
            vec![("Dimension", Some("brana-knowledge/dimensions/"), "deprecated")],
            vec![],
            vec![],
        );
        // Should fall through to heuristic since the type is not active
        assert_eq!(classify_node("brana-knowledge/dimensions/01-foo.md", &ontology), "Dimension");
    }

    // ── resolve_path ───────────────────────────────────────────────

    #[test]
    fn resolve_path_absolute_style() {
        let result = resolve_path("docs/foo.md", "docs/bar.md", Path::new("/root"));
        assert_eq!(result, Some("docs/foo.md".to_string()));
    }

    #[test]
    fn resolve_path_relative_parent() {
        let result = resolve_path("../other.md", "docs/sub/test.md", Path::new("/root"));
        assert_eq!(result, Some("docs/other.md".to_string()));
    }

    #[test]
    fn resolve_path_relative_sibling() {
        let result = resolve_path("./sibling.md", "docs/test.md", Path::new("/root"));
        assert_eq!(result, Some("docs/sibling.md".to_string()));
    }

    // ── resolve_frontmatter_target ─────────────────────────────────

    #[test]
    fn resolve_frontmatter_target_by_number() {
        let mut files = BTreeMap::new();
        files.insert("docs/14-architecture.md".to_string(), PathBuf::from("/x"));
        files.insert("docs/18-roadmap.md".to_string(), PathBuf::from("/y"));
        assert_eq!(
            resolve_frontmatter_target("14", &files),
            Some("docs/14-architecture.md".to_string())
        );
    }

    #[test]
    fn resolve_frontmatter_target_by_path() {
        let files = BTreeMap::new();
        assert_eq!(
            resolve_frontmatter_target("docs/foo.md", &files),
            Some("docs/foo.md".to_string())
        );
    }

    #[test]
    fn resolve_frontmatter_target_no_match() {
        let files = BTreeMap::new();
        assert_eq!(resolve_frontmatter_target("999", &files), None);
    }

    #[test]
    fn resolve_frontmatter_target_exact_filename() {
        let mut files = BTreeMap::new();
        files.insert("docs/ARCHITECTURE.md".to_string(), PathBuf::from("/x"));
        assert_eq!(
            resolve_frontmatter_target("ARCHITECTURE", &files),
            Some("docs/ARCHITECTURE.md".to_string())
        );
    }

    // ── dedup ──────────────────────────────────────────────────────

    #[test]
    fn dedup_preserves_order() {
        let input = vec!["a".to_string(), "b".to_string(), "a".to_string(), "c".to_string()];
        assert_eq!(dedup(input), vec!["a", "b", "c"]);
    }

    #[test]
    fn dedup_empty() {
        let input: Vec<String> = vec![];
        assert!(dedup(input).is_empty());
    }

    // ── fuzzy_match_key ────────────────────────────────────────────

    #[test]
    fn fuzzy_match_exact() {
        let mut nodes = BTreeMap::new();
        nodes.insert("docs/14-arch.md".to_string(), GraphNode {
            title: "Arch".to_string(),
            node_type: "Roadmap".to_string(),
            impl_files: vec![],
        });
        assert_eq!(fuzzy_match_key("docs/14-arch.md", &nodes), Some("docs/14-arch.md".to_string()));
    }

    #[test]
    fn fuzzy_match_contains_unique() {
        let mut nodes = BTreeMap::new();
        nodes.insert("docs/14-arch.md".to_string(), GraphNode {
            title: "Arch".to_string(),
            node_type: "Roadmap".to_string(),
            impl_files: vec![],
        });
        nodes.insert("docs/18-roadmap.md".to_string(), GraphNode {
            title: "Roadmap".to_string(),
            node_type: "Roadmap".to_string(),
            impl_files: vec![],
        });
        assert_eq!(fuzzy_match_key("14-arch", &nodes), Some("docs/14-arch.md".to_string()));
    }

    #[test]
    fn fuzzy_match_ambiguous_returns_none() {
        let mut nodes = BTreeMap::new();
        nodes.insert("docs/a-test.md".to_string(), GraphNode {
            title: "A".to_string(),
            node_type: "Roadmap".to_string(),
            impl_files: vec![],
        });
        nodes.insert("docs/b-test.md".to_string(), GraphNode {
            title: "B".to_string(),
            node_type: "Roadmap".to_string(),
            impl_files: vec![],
        });
        // "test" matches both at filename level
        assert_eq!(fuzzy_match_key("test", &nodes), None);
    }

    // ── Graph operations: orphan detection ──────────────────────────

    #[test]
    fn orphan_detection_finds_isolated_nodes() {
        let graph = make_graph(
            vec![("A", "Doc"), ("B", "Doc"), ("C", "Doc")],
            vec![("A", "B", "references", false)],
        );
        let orphans = find_orphans(&graph);
        assert_eq!(orphans, vec!["C"]);
    }

    #[test]
    fn orphan_detection_no_orphans() {
        let graph = make_graph(
            vec![("A", "Doc"), ("B", "Doc")],
            vec![("A", "B", "references", false)],
        );
        let orphans = find_orphans(&graph);
        assert!(orphans.is_empty());
    }

    #[test]
    fn orphan_detection_all_orphans() {
        let graph = make_graph(
            vec![("A", "Doc"), ("B", "Doc"), ("C", "Doc")],
            vec![],
        );
        let orphans = find_orphans(&graph);
        assert_eq!(orphans, vec!["A", "B", "C"]);
    }

    #[test]
    fn orphan_detection_edge_target_not_orphan() {
        // Node referenced as edge target but not source is still connected
        let graph = make_graph(
            vec![("A", "Doc"), ("B", "Doc"), ("C", "Doc")],
            vec![("A", "C", "depends_on", false)],
        );
        let orphans = find_orphans(&graph);
        assert_eq!(orphans, vec!["B"]);
    }

    // ── Graph operations: BFS path finding ─────────────────────────

    #[test]
    fn bfs_path_direct() {
        let graph = make_graph(
            vec![("A", "Doc"), ("B", "Doc")],
            vec![("A", "B", "references", false)],
        );
        let path = bfs_path(&graph, "A", "B");
        assert_eq!(path, Some(vec!["A".to_string(), "B".to_string()]));
    }

    #[test]
    fn bfs_path_through_chain() {
        let graph = make_graph(
            vec![("A", "Doc"), ("B", "Doc"), ("C", "Doc")],
            vec![
                ("A", "B", "references", false),
                ("B", "C", "depends_on", false),
            ],
        );
        let path = bfs_path(&graph, "A", "C");
        assert_eq!(
            path,
            Some(vec!["A".to_string(), "B".to_string(), "C".to_string()])
        );
    }

    #[test]
    fn bfs_path_no_path() {
        let graph = make_graph(
            vec![("A", "Doc"), ("B", "Doc"), ("C", "Doc")],
            vec![("A", "B", "references", false)],
        );
        let path = bfs_path(&graph, "A", "C");
        assert_eq!(path, None);
    }

    #[test]
    fn bfs_path_same_node() {
        let graph = make_graph(
            vec![("A", "Doc")],
            vec![],
        );
        let path = bfs_path(&graph, "A", "A");
        assert_eq!(path, Some(vec!["A".to_string()]));
    }

    #[test]
    fn bfs_path_undirected() {
        // BFS uses undirected edges — can traverse backwards
        let graph = make_graph(
            vec![("A", "Doc"), ("B", "Doc")],
            vec![("B", "A", "references", false)],
        );
        let path = bfs_path(&graph, "A", "B");
        assert_eq!(path, Some(vec!["A".to_string(), "B".to_string()]));
    }

    // ── Graph operations: transitive closure ───────────────────────

    #[test]
    fn transitive_closure_simple_chain() {
        let edges = vec![
            GraphEdge { from: "A".into(), to: "B".into(), edge_type: "depends_on".into(), computed: false },
            GraphEdge { from: "B".into(), to: "C".into(), edge_type: "depends_on".into(), computed: false },
        ];
        let computed = transitive_closure(&edges, "depends_on");
        assert_eq!(computed.len(), 1);
        assert!(computed.contains(&("A".to_string(), "C".to_string())));
    }

    #[test]
    fn transitive_closure_longer_chain() {
        let edges = vec![
            GraphEdge { from: "A".into(), to: "B".into(), edge_type: "depends_on".into(), computed: false },
            GraphEdge { from: "B".into(), to: "C".into(), edge_type: "depends_on".into(), computed: false },
            GraphEdge { from: "C".into(), to: "D".into(), edge_type: "depends_on".into(), computed: false },
        ];
        let computed = transitive_closure(&edges, "depends_on");
        // A->C, A->D, B->D
        assert_eq!(computed.len(), 3);
        assert!(computed.contains(&("A".to_string(), "C".to_string())));
        assert!(computed.contains(&("A".to_string(), "D".to_string())));
        assert!(computed.contains(&("B".to_string(), "D".to_string())));
    }

    #[test]
    fn transitive_closure_no_chain() {
        let edges = vec![
            GraphEdge { from: "A".into(), to: "B".into(), edge_type: "depends_on".into(), computed: false },
            GraphEdge { from: "C".into(), to: "D".into(), edge_type: "depends_on".into(), computed: false },
        ];
        let computed = transitive_closure(&edges, "depends_on");
        assert!(computed.is_empty());
    }

    #[test]
    fn transitive_closure_ignores_other_rel_types() {
        let edges = vec![
            GraphEdge { from: "A".into(), to: "B".into(), edge_type: "depends_on".into(), computed: false },
            GraphEdge { from: "B".into(), to: "C".into(), edge_type: "informs".into(), computed: false },
        ];
        let computed = transitive_closure(&edges, "depends_on");
        assert!(computed.is_empty());
    }

    #[test]
    fn transitive_closure_ignores_already_computed() {
        let edges = vec![
            GraphEdge { from: "A".into(), to: "B".into(), edge_type: "depends_on".into(), computed: false },
            GraphEdge { from: "B".into(), to: "C".into(), edge_type: "depends_on".into(), computed: true },
        ];
        // B->C is computed, so it shouldn't be used as a seed for transitive chains
        let computed = transitive_closure(&edges, "depends_on");
        assert!(computed.is_empty());
    }

    // ── Validation: supersession chain gaps ────────────────────────

    #[test]
    fn supersession_gap_detected() {
        let graph = make_graph(
            vec![("A", "Doc")],
            vec![("A", "B", "supersedes", false)],
        );
        let gaps = find_supersession_gaps(&graph);
        assert_eq!(gaps.len(), 1);
        assert_eq!(gaps[0], ("A".to_string(), "B".to_string()));
    }

    #[test]
    fn supersession_no_gap_when_target_exists() {
        let graph = make_graph(
            vec![("A", "Doc"), ("B", "Doc")],
            vec![("A", "B", "supersedes", false)],
        );
        let gaps = find_supersession_gaps(&graph);
        assert!(gaps.is_empty());
    }

    #[test]
    fn supersession_computed_edges_ignored() {
        let graph = make_graph(
            vec![("A", "Doc")],
            vec![("A", "B", "supersedes", true)],
        );
        let gaps = find_supersession_gaps(&graph);
        assert!(gaps.is_empty());
    }

    // ── Validation: unknown edge types ─────────────────────────────

    #[test]
    fn unknown_edge_type_flagged() {
        let known: HashSet<String> =
            ["depends_on", "informs", "supersedes"].iter().map(|s| s.to_string()).collect();
        let edges = vec![
            GraphEdge { from: "A".into(), to: "B".into(), edge_type: "depends_on".into(), computed: false },
            GraphEdge { from: "C".into(), to: "D".into(), edge_type: "magic_link".into(), computed: false },
        ];
        let unknown = find_unknown_edge_types(&edges, &known);
        assert_eq!(unknown.len(), 1);
        assert!(unknown.contains("magic_link"));
    }

    #[test]
    fn references_edge_not_flagged_as_unknown() {
        let known: HashSet<String> = HashSet::new();
        let edges = vec![
            GraphEdge { from: "A".into(), to: "B".into(), edge_type: "references".into(), computed: false },
        ];
        let unknown = find_unknown_edge_types(&edges, &known);
        assert!(unknown.is_empty());
    }

    #[test]
    fn all_known_edges_pass() {
        let known: HashSet<String> =
            ["depends_on", "informs"].iter().map(|s| s.to_string()).collect();
        let edges = vec![
            GraphEdge { from: "A".into(), to: "B".into(), edge_type: "depends_on".into(), computed: false },
            GraphEdge { from: "C".into(), to: "D".into(), edge_type: "informs".into(), computed: false },
            GraphEdge { from: "E".into(), to: "F".into(), edge_type: "references".into(), computed: false },
        ];
        let unknown = find_unknown_edge_types(&edges, &known);
        assert!(unknown.is_empty());
    }
}
