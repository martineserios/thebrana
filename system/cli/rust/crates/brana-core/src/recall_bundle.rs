//! The recall bundle (t-3537, ADR-099): at most 8 typed pointers for one task.
//! Design: docs/architecture/features/recall-bundle.md §"Bundle assembly".
//!
//! `compute_bundle` refreshes the index, queries the two memory legs and runs the pure
//! stages in [`assemble`]. A pointer is a note's file stem plus its `description` line,
//! never the body. Everything fails open: a bundle can be empty or partial, and the
//! result says which legs and checks degraded.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use serde::Serialize;

use crate::memory::{
    FreshnessReport, MemoryFileRef, list_memory_listing, memory_file_identity, memory_file_stamp,
    refresh_fts_dirs,
};
use crate::search::{DocRef, HybridProvider, LegStatus, RecallScope, SearchHit};

/// Pointers in a bundle at most.
pub const MAX_POINTERS: usize = 8;
/// Pointers of one type at most (v1; tuning only through the gates).
pub const MAX_PER_TYPE: usize = 3;
/// Characters in a gist at most.
pub const GIST_MAX_CHARS: usize = 160;
/// Characters in the query at most.
pub const QUERY_MAX_CHARS: usize = 500;
/// Candidates fetched from each leg.
const CANDIDATE_POOL: usize = 40;
/// Weight of a note with a derived supersession signal.
const DERIVED_SUPERSEDED_WEIGHT: f64 = 0.5;
/// Longest `superseded by [[x]]` target accepted; longer or odd-looking ones are ignored.
pub const SUPERSEDED_TARGET_MAX_CHARS: usize = 80;
/// Most bytes read from one note: frontmatter is at the top, and a huge file must not be
/// pulled into memory once per candidate.
pub const NOTE_READ_CAP_BYTES: usize = 64 * 1024;

// ── input ────────────────────────────────────────────────────────────────────

/// What the bundle needs to know about a task. Description, context and notes are
/// deliberately absent: the v1 query is subject + tags only (gates-v1), so a ticket's
/// own pointer text cannot leak into retrieval.
#[derive(Debug, Clone)]
pub struct BundleTask {
    pub id: String,
    pub subject: String,
    pub tags: Vec<String>,
}

/// The v1 query: the subject, then the tags, space-separated, capped.
pub fn build_query(task: &BundleTask) -> String {
    let mut parts: Vec<&str> = vec![task.subject.trim()];
    parts.extend(task.tags.iter().map(|t| t.trim()));
    let joined = parts.into_iter().filter(|p| !p.is_empty()).collect::<Vec<_>>().join(" ");
    joined.chars().take(QUERY_MAX_CHARS).collect::<String>().trim_end().to_string()
}

// ── note parsing ─────────────────────────────────────────────────────────────

/// The few frontmatter fields (and one body signal) the bundle reads from a note.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct NoteMeta {
    /// The note opens with a `---` frontmatter block.
    pub has_frontmatter: bool,
    /// `metadata.type`, else the top-level `type`.
    pub type_: Option<String>,
    pub description: Option<String>,
    pub status: Option<String>,
    /// `to:` of every `type: supersedes` relation.
    pub supersedes: Vec<String>,
    /// Targets of `superseded by [[x]]` in the body.
    pub superseded_by: Vec<String>,
}

/// A frontmatter value as plain text: a quoted value ends at its closing quote (anything
/// after it is a comment); a plain value ends at ` #`.
fn plain(v: &str) -> &str {
    let v = v.trim();
    for q in ['"', '\''] {
        if let Some(rest) = v.strip_prefix(q)
            && let Some(end) = rest.find(q)
        {
            return &rest[..end];
        }
    }
    match v.find(" #") {
        Some(i) => v[..i].trim_end(),
        None => v,
    }
}

/// The frontmatter fields the bundle reads, whichever reader produced them.
#[derive(Default)]
struct Front {
    type_: Option<String>,
    status: Option<String>,
    description: Option<String>,
    supersedes: Vec<String>,
}

/// Frontmatter larger than this goes to the line reader, not the YAML parser.
const FRONT_YAML_MAX_BYTES: usize = 16 * 1024;

/// Whether `text` holds a YAML anchor (`&x`) or alias (`*x`) at a token start. Nested
/// aliases can expand a few hundred bytes into gigabytes (the "billion laughs" document),
/// and every alias hop re-expands the anchored subtree, so frontmatter holding one never
/// reaches the YAML parser (notes are untrusted text). Name characters are libyaml's:
/// letters, digits, `_` and `-`. `*` and `&` in ordinary prose (`**bold**`, `AT&T`) are not
/// at a token start and do not count; text like `*Important*` that the parser would reject
/// anyway goes to the line reader either way.
pub(crate) fn has_yaml_alias(text: &str) -> bool {
    let mut prev: Option<char> = None;
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if (c == '&' || c == '*')
            && chars.peek().is_some_and(|n| n.is_alphanumeric() || matches!(n, '_' | '-'))
            && prev.is_none_or(|p| p.is_whitespace() || matches!(p, ':' | '[' | '{' | ',' | '-' | '?'))
        {
            return true;
        }
        prev = Some(c);
    }
    false
}

/// Every scalar in `v`, flattening lists (and nested lists) and looking through tags.
/// Maps carry no scalar of their own.
fn yaml_scalars(v: &serde_yaml::Value, out: &mut Vec<String>) {
    use serde_yaml::Value;
    let one = match v {
        Value::String(s) => s.trim().to_string(),
        Value::Number(n) => n.to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Sequence(items) => {
            items.iter().for_each(|i| yaml_scalars(i, out));
            return;
        }
        Value::Tagged(t) => {
            yaml_scalars(&t.value, out);
            return;
        }
        _ => return,
    };
    if !one.is_empty() {
        out.push(one);
    }
}

/// The first scalar of `v`.
fn yaml_scalar(v: Option<&serde_yaml::Value>) -> Option<String> {
    let mut all = Vec::new();
    yaml_scalars(v?, &mut all);
    all.into_iter().next()
}

/// Every scalar of `v`: `to: [a, b]` and `to: [[a], [b]]` name several notes.
fn yaml_links(v: Option<&serde_yaml::Value>) -> Vec<String> {
    let mut all = Vec::new();
    if let Some(v) = v {
        yaml_scalars(v, &mut all);
    }
    all
}

/// A status counts as superseded if any scalar in it says so (`[superseded]`, `!tag superseded`).
fn yaml_status(v: Option<&serde_yaml::Value>) -> Option<String> {
    let mut all = Vec::new();
    yaml_scalars(v?, &mut all);
    if let Some(hit) = all.iter().find(|s| s.eq_ignore_ascii_case("superseded")) {
        return Some(hit.clone());
    }
    all.into_iter().next()
}

/// The frontmatter read as real YAML. `None` when the block is not valid YAML (an unquoted
/// colon in a description is common), is too big, or holds anchors or aliases; the caller
/// then uses the tolerant line reader.
fn front_from_yaml(text: &str) -> Option<Front> {
    use serde_yaml::Value;
    if text.len() > FRONT_YAML_MAX_BYTES || has_yaml_alias(text) {
        return None;
    }
    let v: Value = serde_yaml::from_str(text).ok()?;
    if v.is_null() {
        return Some(Front::default());
    }
    let top = v.as_mapping()?;
    let meta = top.get("metadata").and_then(Value::as_mapping);
    let in_meta = |k: &str| meta.and_then(|m| yaml_scalar(m.get(k)));
    let mut supersedes = Vec::new();
    if let Some(Value::Sequence(items)) = top.get("relations") {
        for it in items {
            let Some(m) = it.as_mapping() else { continue };
            let supersedes_edge =
                yaml_scalar(m.get("type")).is_some_and(|k| k.eq_ignore_ascii_case("supersedes"));
            if supersedes_edge {
                supersedes.extend(yaml_links(m.get("to")));
            }
        }
    }
    Some(Front {
        type_: in_meta("type").or_else(|| yaml_scalar(top.get("type"))),
        status: yaml_status(top.get("status"))
            .or_else(|| yaml_status(meta.and_then(|m| m.get("status")))),
        description: yaml_scalar(top.get("description")).or_else(|| in_meta("description")),
        supersedes,
    })
}

/// A key with its quotes removed (`"status"` and `'status'` are the key `status`).
fn unquote_key(k: &str) -> &str {
    k.trim().trim_matches(['"', '\''])
}

/// The notes a `to:` value names: `a`, `[a, b]`, `[[a]], [[b]]` (a list in any bracket style).
fn split_targets(to: &str) -> Vec<String> {
    to.split(',')
        .map(|t| t.trim().trim_matches(['[', ']', '"', '\'', ' ']))
        .filter(|t| !t.is_empty())
        .map(str::to_string)
        .collect()
}

/// A status value as text. `[superseded]`, `[draft, Superseded]` and `!tag superseded` all
/// say superseded; anything else is returned cleaned of brackets.
fn status_text(v: &str) -> String {
    let v = v.trim();
    let v = match v.strip_prefix('!') {
        Some(rest) => rest.split_once(char::is_whitespace).map_or("", |(_, r)| r),
        None => v,
    };
    let parts: Vec<&str> =
        v.split(',').map(|p| p.trim().trim_matches(['[', ']', '"', '\'', ' '])).filter(|p| !p.is_empty()).collect();
    match parts.iter().find(|p| p.eq_ignore_ascii_case("superseded")) {
        Some(hit) => hit.to_string(),
        None => parts.join(", "),
    }
}

/// The `{…}` groups of a flow-style list (`[{a: 1}, {b: 2}]`), quote-aware.
fn flow_groups(v: &str) -> Vec<&str> {
    let (mut out, mut depth, mut start, mut quote) = (Vec::new(), 0usize, 0usize, None::<char>);
    for (i, c) in v.char_indices() {
        match (quote, c) {
            (Some(q), c) if c == q => quote = None,
            (Some(_), _) => {}
            (None, '"' | '\'') => quote = Some(c),
            (None, '{') => {
                if depth == 0 {
                    start = i;
                }
                depth += 1;
            }
            (None, '}') if depth > 0 => {
                depth -= 1;
                if depth == 0 {
                    out.push(&v[start..=i]);
                }
            }
            _ => {}
        }
    }
    out
}

#[derive(Clone, Copy, PartialEq)]
enum Section {
    None,
    Metadata,
    Relations,
}

/// One `relations:` list item, collected field by field in any order.
#[derive(Default)]
struct RelItem {
    kind: Option<String>,
    to: Option<String>,
}

impl RelItem {
    /// End the item: keep its target if it is a `supersedes` edge.
    fn flush(&mut self, out: &mut Vec<String>) {
        let item = std::mem::take(self);
        if item.kind.as_deref().is_some_and(|k| k.eq_ignore_ascii_case("supersedes"))
            && let Some(to) = item.to
        {
            out.extend(split_targets(&to));
        }
    }

    fn set(&mut self, key: &str, value: &str) {
        match unquote_key(key) {
            "type" => self.kind = Some(plain(value).to_string()),
            "to" => self.to = Some(plain(value).to_string()),
            _ => {}
        }
    }

    /// One payload: `key: value`, or an inline `{key: value, key: value}` map.
    fn apply(&mut self, payload: &str) {
        let p = payload.trim();
        if let Some(inner) = p.strip_prefix('{').and_then(|r| r.strip_suffix('}')) {
            for part in inner.split(',') {
                if let Some((k, v)) = part.split_once(':') {
                    self.set(k.trim(), v);
                }
            }
        } else if let Some((k, v)) = p.split_once(':') {
            self.set(k.trim(), v);
        }
    }
}

/// The tolerant fallback reader for frontmatter that is not valid YAML. Blank lines and
/// comments never end a section; only the first indent level of `metadata:` and the item's
/// own fields are read, so nested maps and lists are not mistaken for them.
fn front_from_lines(lines: &[&str]) -> Front {
    let mut front = Front::default();
    let (mut top_type, mut meta_type) = (None::<String>, None::<String>);
    let (mut top_status, mut meta_status) = (None::<String>, None::<String>);
    let (mut top_desc, mut meta_desc) = (None::<String>, None::<String>);
    let mut section = Section::None;
    let mut item = RelItem::default();
    let (mut item_dash, mut item_key) = (None::<usize>, None::<usize>);
    let mut meta_indent: Option<usize> = None;
    let mut fold: Option<String> = None; // description: > / |
    for line in lines {
        let indent = line.len() - line.trim_start_matches([' ', '\t']).len();
        let t = line.trim();
        if let Some(buf) = fold.as_mut() {
            if indent > 0 || t.is_empty() {
                if !t.is_empty() {
                    if !buf.is_empty() {
                        buf.push(' ');
                    }
                    buf.push_str(t);
                }
                continue;
            }
            if !buf.is_empty() {
                top_desc = Some(std::mem::take(buf));
            }
            fold = None;
        }
        if t.is_empty() || t.starts_with('#') {
            continue;
        }
        let is_dash = t == "-" || (t.starts_with('-') && t[1..].starts_with(char::is_whitespace));
        if section == Section::Relations && is_dash {
            if item_dash.is_some_and(|d| indent > d) {
                continue; // a list inside the current item
            }
            item.flush(&mut front.supersedes);
            let rest = &t[1..];
            let payload = rest.trim_start();
            item_dash = Some(indent);
            item_key = Some(indent + 1 + (rest.len() - payload.len()));
            item.apply(payload);
            continue;
        }
        if indent > 0 {
            match section {
                Section::Metadata => {
                    let first = *meta_indent.get_or_insert(indent);
                    if indent == first
                        && let Some((k, v)) = t.split_once(':')
                    {
                        let v = plain(v);
                        if !v.is_empty() {
                            match unquote_key(k) {
                                "type" => meta_type = Some(v.to_string()),
                                "status" => meta_status = Some(status_text(v)),
                                "description" if !(v.starts_with('>') || v.starts_with('|')) => {
                                    meta_desc = Some(v.to_string())
                                }
                                _ => {}
                            }
                        }
                    }
                }
                Section::Relations => {
                    // The item's own fields line up with its first key; deeper lines belong
                    // to a nested value.
                    if indent > item_dash.unwrap_or(0) && item_key.is_some_and(|k| indent <= k) {
                        item.apply(t);
                    }
                }
                Section::None => {}
            }
            continue;
        }
        item.flush(&mut front.supersedes);
        (section, item_dash, item_key, meta_indent) = (Section::None, None, None, None);
        let Some((k, v)) = t.split_once(':') else { continue };
        let vp = plain(v);
        match unquote_key(k) {
            "type" if !vp.is_empty() => top_type = Some(vp.to_string()),
            "status" if !vp.is_empty() => top_status = Some(status_text(vp)),
            "description" if vp.starts_with('>') || vp.starts_with('|') => fold = Some(String::new()),
            "description" if !vp.is_empty() => top_desc = Some(vp.to_string()),
            "metadata" => section = Section::Metadata,
            "relations" => {
                section = Section::Relations;
                // `relations: [{type: supersedes, to: old}, …]` on one line.
                for group in flow_groups(v.trim()) {
                    item.apply(group);
                    item.flush(&mut front.supersedes);
                }
            }
            _ => {}
        }
    }
    item.flush(&mut front.supersedes);
    if let Some(buf) = fold.take()
        && !buf.is_empty()
    {
        top_desc = Some(buf);
    }
    front.type_ = meta_type.or(top_type);
    front.status = top_status.or(meta_status);
    front.description = top_desc.or(meta_desc);
    front
}

/// Parse a note's frontmatter and body. A note that does not open with a closed `---` block
/// has no frontmatter, so no field is read from it; the body signal is still read. `type`,
/// `status` and `description` come from the top level and from the `metadata:` block (the
/// top level wins, except `type`, where `metadata.type` wins); `relations` items may list
/// their fields in any order. The block is read as YAML; when it is not valid YAML (or holds
/// anchors or aliases) the tolerant line reader takes over.
pub fn parse_note(content: &str) -> NoteMeta {
    // A byte-order mark (some editors and sync tools add one) must not hide the `---`.
    let content = content.strip_prefix('\u{feff}').unwrap_or(content);
    let mut meta = NoteMeta::default();
    let mut body_from = 0usize;
    let mut lines = content.lines();
    if lines.next().map(str::trim) == Some("---") {
        let mut block: Vec<&str> = Vec::new();
        let mut closed = false;
        let mut consumed = 1usize;
        for line in lines {
            consumed += 1;
            if line.trim() == "---" {
                closed = true;
                break;
            }
            block.push(line);
        }
        // An unclosed block is not frontmatter: the whole text is body.
        if closed {
            let front = front_from_yaml(&block.join("\n")).unwrap_or_else(|| front_from_lines(&block));
            meta.has_frontmatter = true;
            meta.type_ = front.type_;
            meta.status = front.status;
            meta.description = front.description;
            meta.supersedes = front.supersedes;
            body_from = consumed;
        }
    }
    let body: String = content.lines().skip(body_from).collect::<Vec<_>>().join("\n");
    meta.superseded_by = superseded_by_targets(&body);
    meta
}

/// Targets of `superseded by [[x]]` (case-insensitive), at most 3, in order.
fn superseded_by_targets(body: &str) -> Vec<String> {
    const NEEDLE: &str = "superseded by";
    // ASCII-only folding keeps byte offsets identical to `body`.
    let lower = body.to_ascii_lowercase();
    let mut out: Vec<String> = Vec::new();
    let mut from = 0usize;
    while let Some(i) = lower[from..].find(NEEDLE) {
        let after = from + i + NEEDLE.len();
        // Skip markdown decoration between the phrase and the link (`**`, `_`, backticks,
        // a colon); the link target is the part before any `|alias` or `#section`.
        let rest = body
            .get(after..)
            .unwrap_or("")
            .trim_start_matches(|c: char| c.is_whitespace() || matches!(c, '*' | '_' | '`' | ':'));
        if let Some(inner) = rest.strip_prefix("[[")
            && let Some(end) = inner.find("]]")
        {
            let t = bare_name(inner[..end].split(['|', '#']).next().unwrap_or(""));
            if is_plain_ref(&t) && !out.contains(&t) {
                out.push(t);
            }
        }
        from = after;
        if out.len() >= 3 {
            break;
        }
    }
    out
}

/// Whether a file is a memory entry: it has a type (frontmatter or filename prefix) or at
/// least a frontmatter block. Logs and state files (`sessions.md`, `session-handoff.md`,
/// `event-log.md`) have neither. The same idea as `memory.rs` ("no frontmatter at all is not a
/// memory entry"), applied to every file rather than only to names without a `_` prefix (user
/// decision 2026-10-15).
pub fn is_memory_entry(file_type: &str, meta: &NoteMeta) -> bool {
    meta.has_frontmatter || meta.type_.is_some() || !file_type.is_empty()
}

/// A reference printed back to the worker must look like a note name: short, and only
/// letters, digits, `_`, `-`, `.`. Note bodies are untrusted text.
fn is_plain_ref(t: &str) -> bool {
    !t.is_empty()
        && t.chars().count() <= SUPERSEDED_TARGET_MAX_CHARS
        && t.chars().all(|c| c.is_alphanumeric() || matches!(c, '_' | '-' | '.'))
}

/// Control characters (escape sequences, bells), invisible format characters (zero-width,
/// tag block), line/paragraph separators and bidirectional overrides: never printed.
fn is_unsafe_char(c: char) -> bool {
    (c.is_control() && !c.is_whitespace())
        || matches!(
            c,
            '\u{00AD}' // soft hyphen
            | '\u{061C}' | '\u{180E}'
            | '\u{200B}'..='\u{200F}' // zero-width characters, joiners, direction marks
            | '\u{2028}'..='\u{202E}' // line and paragraph separators, bidi embeddings and overrides
            | '\u{2060}'..='\u{206F}' // word joiner, invisible operators, bidi isolates
            | '\u{FEFF}'
            | '\u{E0000}'..='\u{E007F}' // tag characters: invisible text
        )
}

/// `s` with every unsafe character and every line break removed, for single-line output.
fn clean(s: &str) -> String {
    s.chars().filter(|c| !is_unsafe_char(*c) && !c.is_control()).collect()
}

/// One line, whitespace collapsed, at most [`GIST_MAX_CHARS`] characters (159 + `…`).
pub fn make_gist(description: Option<&str>) -> Option<String> {
    // Whitespace (including line breaks) becomes a space; escape sequences and bidi
    // overrides are dropped. Descriptions are untrusted text from note files.
    let safe: String = description?
        .chars()
        .filter_map(|c| if c.is_whitespace() { Some(' ') } else if is_unsafe_char(c) { None } else { Some(c) })
        .collect();
    let collapsed = safe.split_whitespace().collect::<Vec<_>>().join(" ");
    if collapsed.is_empty() {
        return None;
    }
    if collapsed.chars().count() <= GIST_MAX_CHARS {
        return Some(collapsed);
    }
    let mut cut: String = collapsed.chars().take(GIST_MAX_CHARS - 1).collect();
    cut.push('…');
    Some(cut)
}

// ── stages ───────────────────────────────────────────────────────────────────

/// A retrieved note, read and parsed, before the stages.
#[derive(Debug, Clone)]
pub struct Candidate {
    pub path: PathBuf,
    /// The file stem: the pointer's `ref`.
    pub stem: String,
    pub slug: String,
    /// The type from the filename prefix (`""` when there is none).
    pub file_type: String,
    pub rrf: f64,
    pub meta: NoteMeta,
}

/// One entry of a bundle.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Pointer {
    #[serde(rename = "type")]
    pub ptype: String,
    #[serde(rename = "ref")]
    pub ref_: String,
    pub gist: Option<String>,
    pub rank: usize,
    pub flags: Vec<String>,
}

/// `(file type, slug)` → `(newest stamp, that file's stem)`, over the scope's folders.
pub type NewestStamps = HashMap<(String, String), (String, String)>;

/// The newest dated file per `(type, slug)` among `files` (undated files have no stamp).
pub fn newest_stamps(files: &[MemoryFileRef]) -> NewestStamps {
    let mut out: NewestStamps = HashMap::new();
    for f in files {
        let Some(stem) = f.path.file_stem().and_then(|s| s.to_str()) else { continue };
        let Some(stamp) = memory_file_stamp(stem) else { continue };
        let key = (f.mtype.clone(), f.slug.clone());
        if out.get(&key).is_none_or(|(s, _)| stamp > s.as_str()) {
            out.insert(key, (stamp.to_string(), stem.to_string()));
        }
    }
    out
}

/// A `supersedes`/`superseded by` reference reduced to a bare name: last path segment,
/// no `.md`, no `[[ ]]`.
fn bare_name(r: &str) -> String {
    let r = r.trim().trim_start_matches("[[").trim_end_matches("]]").trim();
    let last = r.rsplit('/').next().unwrap_or(r);
    last.strip_suffix(".md").unwrap_or(last).to_string()
}

/// The stages of ADR-099 on already-read candidates: scope, type, supersession, order,
/// quota and cut, gist. Pure.
pub fn assemble(cands: Vec<Candidate>, scope: &RecallScope, newest: &NewestStamps) -> Vec<Pointer> {
    // 1 scope
    let cands: Vec<Candidate> = cands.into_iter().filter(|c| scope.allows(&c.path)).collect();

    // 3 supersession, authoritative part: the ADR-057 status and supersedes-targets. A
    // target naming a full stem removes exactly that note. A slug-only target removes
    // notes of the superseding note's own type and that slug, except that when the
    // superseding note is itself a twin of that slug (a new version superseding its
    // older ones) the newest dated twin is the live one and stays. A slug-only target
    // from an unrelated note replaces every note of that slug, dated or not
    // (decision confirmed 2026-10-15).
    struct Edge {
        by_stem: String,
        by_type: String,
        by_slug: String,
        name: String,
    }
    let edges: Vec<Edge> = cands
        .iter()
        .flat_map(|c| {
            c.meta.supersedes.iter().map(|t| Edge {
                by_stem: c.stem.clone(),
                by_type: c.file_type.clone(),
                by_slug: c.slug.clone(),
                name: bare_name(t),
            })
        })
        .collect();
    let is_newest_twin = |c: &Candidate| {
        memory_file_stamp(&c.stem)
            .zip(newest.get(&(c.file_type.clone(), c.slug.clone())))
            .is_some_and(|(stamp, (newest_stamp, _))| stamp == newest_stamp.as_str())
    };
    let cands: Vec<Candidate> = cands
        .into_iter()
        .filter(|c| {
            let dead = c.meta.status.as_deref().is_some_and(|s| s.trim().eq_ignore_ascii_case("superseded"));
            let targeted = edges.iter().any(|e| {
                let by_a_twin = e.by_slug == c.slug && e.by_type == c.file_type;
                e.by_stem != c.stem
                    && (e.name == c.stem
                        || (e.name == c.slug && e.by_type == c.file_type && !(by_a_twin && is_newest_twin(c))))
            });
            !dead && !targeted
        })
        .collect();

    // 3 supersession, derived part: down-weight and flag, never drop
    let mut scored: Vec<(f64, Candidate, Vec<String>)> = cands
        .into_iter()
        .map(|c| {
            let mut flags: Vec<String> = Vec::new();
            if let Some(stamp) = memory_file_stamp(&c.stem)
                && let Some((newest_stamp, newer_stem)) = newest.get(&(c.file_type.clone(), c.slug.clone()))
                && stamp < newest_stamp.as_str()
            {
                flags.push(format!("derived-superseded:{newer_stem}"));
            }
            for by in &c.meta.superseded_by {
                flags.push(format!("derived-superseded:{}", bare_name(by)));
            }
            let weight = if flags.is_empty() { 1.0 } else { DERIVED_SUPERSEDED_WEIGHT };
            (c.rrf * weight, c, flags)
        })
        .collect();

    // 4 order
    scored.sort_by(|a, b| {
        b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal).then_with(|| a.1.stem.cmp(&b.1.stem))
    });

    // 2 type, 5 quota and cut, 6 gist
    let mut per_type: HashMap<String, usize> = HashMap::new();
    let mut out: Vec<Pointer> = Vec::new();
    for (_, c, flags) in scored {
        if out.len() >= MAX_POINTERS {
            break;
        }
        // Spelling variants (`Pattern`, ` pattern `) are one type for the quota.
        let ptype = c
            .meta
            .type_
            .as_deref()
            .map(|t| t.trim().to_lowercase())
            .filter(|t| !t.is_empty())
            .or_else(|| (!c.file_type.is_empty()).then(|| c.file_type.to_lowercase()))
            .unwrap_or_else(|| "note".to_string());
        let n = per_type.entry(ptype.clone()).or_insert(0);
        if *n >= MAX_PER_TYPE {
            continue;
        }
        *n += 1;
        out.push(Pointer {
            ptype,
            ref_: c.stem,
            gist: make_gist(c.meta.description.as_deref()),
            rank: out.len() + 1,
            flags,
        });
    }
    out
}

// ── orchestration ────────────────────────────────────────────────────────────

/// Everything `compute_bundle` needs from its surroundings; the CLI builds it from the
/// real paths, tests from fixtures and stub legs.
pub struct BundleEnv<'a> {
    pub scope: RecallScope,
    /// The project folder name (`-home-…-repo`), for the output only.
    pub project: Option<String>,
    /// The scope's `(label, folder)` pairs, for the freshness check and twin detection.
    pub dirs: Vec<(String, PathBuf)>,
    pub knowledge_db: PathBuf,
    pub fts_db: PathBuf,
    pub provider: &'a HybridProvider,
    pub refresh_budget: Duration,
    pub unembedded_wait: Duration,
}

#[derive(Debug, Clone, Serialize)]
pub struct BundleScope {
    pub project: Option<String>,
    pub global: bool,
}

/// Per-leg outcome in the bundle's own words: `fts` is the keyword leg, `vector` the
/// memory-vector leg.
#[derive(Debug, Clone, Serialize)]
pub struct BundleLegs {
    pub fts: LegStatus,
    pub vector: LegStatus,
}

#[derive(Debug, Clone, Serialize)]
pub struct BundleFreshness {
    #[serde(flatten)]
    pub report: FreshnessReport,
    /// In-scope notes without a current vector; `None` when it could not be counted.
    pub unembedded: Option<usize>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Bundle {
    pub task: String,
    pub scope: BundleScope,
    pub shown: bool,
    pub legs: BundleLegs,
    pub pointers: Vec<Pointer>,
    /// Candidates that could not be read as text and were left out.
    pub skipped_unreadable: usize,
    /// Candidates that are logs or state files, not memory entries, and were left out.
    pub skipped_non_entries: usize,
    pub elapsed_ms: u64,
    pub freshness: BundleFreshness,
}

/// Refresh the index, query the legs, read the candidates, run the stages. Never fails:
/// every problem shows up in `legs`, `freshness` or `skipped_unreadable`.
pub fn compute_bundle(task: &BundleTask, env: &BundleEnv) -> Bundle {
    let started = Instant::now();

    let report = refresh_fts_dirs(&env.dirs, &env.fts_db, env.refresh_budget);

    let query = build_query(task);
    let (hits, status) = env.provider.query_with_status(&query, CANDIDATE_POOL);

    let listing = list_memory_listing(&env.dirs);
    let newest = newest_stamps(&listing.files);

    let (cands, skipped_unreadable, skipped_non_entries) = read_candidates(hits, &env.scope);
    let pointers = assemble(cands, &env.scope, &newest);

    let unembedded =
        crate::memory_vectors::unembedded_count(&env.knowledge_db, &listing.files, env.unembedded_wait).ok();

    Bundle {
        task: task.id.clone(),
        scope: BundleScope { project: env.project.clone(), global: true },
        shown: true,
        legs: BundleLegs { fts: status.keyword, vector: status.semantic },
        pointers,
        skipped_unreadable,
        skipped_non_entries,
        elapsed_ms: started.elapsed().as_millis() as u64,
        freshness: BundleFreshness { report, unembedded },
    }
}

/// The first [`NOTE_READ_CAP_BYTES`] of a note as text. A cut inside a multi-byte character
/// is not an error; invalid UTF-8 anywhere inside the cap is.
pub fn read_note_head(path: &Path) -> std::io::Result<String> {
    use std::io::Read;
    let mut buf = Vec::new();
    fs::File::open(path)?.take(NOTE_READ_CAP_BYTES as u64 + 1).read_to_end(&mut buf)?;
    let truncated = buf.len() > NOTE_READ_CAP_BYTES;
    buf.truncate(NOTE_READ_CAP_BYTES);
    match String::from_utf8(buf) {
        Ok(s) => Ok(s),
        Err(e) if truncated && e.utf8_error().error_len().is_none() => {
            let valid = e.utf8_error().valid_up_to();
            let mut bytes = e.into_bytes();
            bytes.truncate(valid);
            String::from_utf8(bytes)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
        }
        Err(e) => Err(std::io::Error::new(std::io::ErrorKind::InvalidData, e)),
    }
}

/// Memory-file hits only (knowledge-store rows are out in v1), each read once. A note
/// that cannot be read as text is counted, never treated as empty.
fn read_candidates(hits: Vec<SearchHit>, scope: &RecallScope) -> (Vec<Candidate>, usize, usize) {
    let mut seen: HashSet<PathBuf> = HashSet::new();
    let mut out = Vec::new();
    let (mut skipped, mut non_entries) = (0usize, 0usize);
    for h in hits {
        let DocRef::MemoryFile { path, .. } = h.doc else { continue };
        // Scope is proven before a byte is read: a file that cannot be shown to be in scope
        // (another project's note behind a planted symlink) is never opened.
        if !scope.allows(&path) || !seen.insert(path.clone()) {
            continue;
        }
        let Some(stem) = path.file_stem().and_then(|s| s.to_str()).map(str::to_string) else { continue };
        let Ok(content) = read_note_head(&path) else {
            skipped += 1;
            continue;
        };
        let (file_type, slug) = memory_file_identity(&stem);
        let meta = parse_note(&content);
        if !is_memory_entry(&file_type, &meta) {
            non_entries += 1;
            continue;
        }
        out.push(Candidate { meta, path, stem, slug, file_type, rrf: h.rrf_score });
    }
    (out, skipped, non_entries)
}

/// The human format: one line per pointer, grouped by type, flagged notes marked.
pub fn format_human(b: &Bundle) -> String {
    let mut out = format!(
        "Recall bundle for {} — {} pointer(s) (fts {}, vector {})\n",
        clean(&b.task),
        b.pointers.len(),
        b.legs.fts.as_str(),
        b.legs.vector.as_str()
    );
    let mut types: Vec<&str> = Vec::new();
    for p in &b.pointers {
        if !types.contains(&p.ptype.as_str()) {
            types.push(&p.ptype);
        }
    }
    for t in types {
        out.push_str(&format!("{}\n", clean(t)));
        for p in b.pointers.iter().filter(|p| p.ptype == t) {
            out.push_str(&format!("  {}. {}", p.rank, clean(&p.ref_)));
            if let Some(g) = &p.gist {
                out.push_str(&format!(" — {}", clean(g)));
            }
            if !p.flags.is_empty() {
                let flags: Vec<String> = p.flags.iter().map(|f| clean(f)).collect();
                out.push_str(&format!("  [{}]", flags.join(", ")));
            }
            out.push('\n');
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::memory::{list_memory_listing, reindex_fts_dirs};
    use crate::search::{
        DocRef, HybridProvider, LegStatus, RecallScope, SearchHit, SearchProvider,
    };
    use crate::vector::{EMBED_DIM, Embedder};
    use std::collections::HashMap;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::Arc;
    use std::time::Duration;
    use tempfile::tempdir;

    // ── builders ──────────────────────────────────────────────────────────────

    fn meta() -> NoteMeta {
        NoteMeta::default()
    }

    /// A real scope folder for the pure-stage tests: `allows` refuses a path it cannot check,
    /// so the fixture notes must exist on disk (t-3542).
    fn mem_dir() -> &'static PathBuf {
        static DIR: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();
        DIR.get_or_init(|| {
            let d = tempfile::tempdir().unwrap().keep();
            std::fs::create_dir_all(d.join("archive")).unwrap();
            d
        })
    }

    fn cand(stem: &str, rrf: f64, m: NoteMeta) -> Candidate {
        let (file_type, slug) = crate::memory::memory_file_identity(stem);
        let path = mem_dir().join(format!("{stem}.md"));
        std::fs::write(&path, "").unwrap();
        Candidate {
            path,
            stem: stem.to_string(),
            slug,
            file_type,
            rrf,
            meta: m,
        }
    }

    fn scope() -> RecallScope {
        RecallScope::Dirs(vec![mem_dir().clone()])
    }

    fn refs(p: &[Pointer]) -> Vec<&str> {
        p.iter().map(|x| x.ref_.as_str()).collect()
    }

    // ── query (user decision 2026-10-15: subject + tags only) ─────────────────

    #[test]
    fn query_is_subject_and_tags_only() {
        let t = BundleTask {
            id: "t-1".into(),
            subject: "Fix reindex TEMPFAIL".into(),
            tags: vec!["ruflo".into(), "scheduler".into()],
        };
        assert_eq!(build_query(&t), "Fix reindex TEMPFAIL ruflo scheduler");
    }

    #[test]
    fn query_with_no_subject_and_no_tags_is_empty() {
        let t = BundleTask { id: "t-1".into(), subject: "  ".into(), tags: vec![] };
        assert_eq!(build_query(&t), "");
    }

    #[test]
    fn query_is_capped() {
        let t = BundleTask { id: "t-1".into(), subject: "word ".repeat(400), tags: vec![] };
        assert!(build_query(&t).chars().count() <= QUERY_MAX_CHARS);
    }

    // ── note parsing ─────────────────────────────────────────────────────────

    #[test]
    fn type_from_a_flat_top_level_field() {
        let m = parse_note("---\nname: x\ntype: pattern\ndescription: d\n---\nbody");
        assert_eq!(m.type_.as_deref(), Some("pattern"));
        assert_eq!(m.description.as_deref(), Some("d"));
    }

    #[test]
    fn type_from_the_metadata_block_and_it_wins_over_a_top_level_field() {
        let m = parse_note("---\nname: x\ntype: reference\nmetadata:\n  type: feedback\n---\nbody");
        assert_eq!(m.type_.as_deref(), Some("feedback"));
    }

    #[test]
    fn a_note_without_frontmatter_has_no_type_and_no_description() {
        let m = parse_note("just text\n---\ntype: pattern\n---\n");
        assert_eq!((m.type_, m.description), (None, None));
    }

    #[test]
    fn description_quoted_and_folded() {
        let q = parse_note("---\ndescription: \"quoted: with colon\"\n---\n");
        assert_eq!(q.description.as_deref(), Some("quoted: with colon"));
        let folded = parse_note("---\ndescription: >\n  first line\n  second line\nname: x\n---\n");
        assert_eq!(folded.description.as_deref(), Some("first line second line"));
    }

    #[test]
    fn status_and_supersedes_relations_are_read() {
        let m = parse_note(
            "---\nstatus: Superseded\nrelations:\n  - type: supersedes\n    to: atoms/pattern_old.md\n  - type: informs\n    to: pattern_other\n---\n",
        );
        assert_eq!(m.status.as_deref(), Some("Superseded"));
        assert_eq!(m.supersedes, vec!["atoms/pattern_old.md"]);
    }

    #[test]
    fn prose_superseded_by_is_read_from_the_body_only() {
        let body = parse_note("---\nname: x\n---\nThis was superseded by [[pattern_new]] in 2026.");
        assert_eq!(body.superseded_by, vec!["pattern_new"]);
        let fm_only = parse_note("---\nname: superseded by [[pattern_new]]\n---\nclean body");
        assert!(fm_only.superseded_by.is_empty());
    }

    #[test]
    fn a_byte_order_mark_does_not_hide_the_frontmatter() {
        let m = parse_note("\u{feff}---\ntype: pattern\ndescription: with bom\n---\nbody");
        assert!(m.has_frontmatter);
        assert_eq!((m.type_.as_deref(), m.description.as_deref()), (Some("pattern"), Some("with bom")));
    }

    #[test]
    fn has_frontmatter_tells_notes_from_logs() {
        assert!(parse_note("---\nname: x\n---\nbody").has_frontmatter);
        assert!(!parse_note("# a log\nplain text").has_frontmatter);
        assert!(!parse_note("").has_frontmatter);
    }

    #[test]
    fn a_memory_entry_has_a_type_or_a_frontmatter_block() {
        let none = parse_note("plain");
        let fm = parse_note("---\nname: x\n---\n");
        let typed = parse_note("---\ntype: pattern\n---\n");
        assert!(!is_memory_entry("", &none), "no prefix, no frontmatter: a log");
        assert!(is_memory_entry("pattern", &none), "prefix types it even without frontmatter");
        assert!(is_memory_entry("", &fm), "frontmatter without a type: still a note");
        assert!(is_memory_entry("", &typed));
    }

    #[test]
    fn prose_superseded_by_survives_characters_whose_lowercase_changes_length() {
        // 'İ' lowercases to two chars; offsets from a lowercased copy would drift.
        let body = parse_note("---\nname: x\n---\nİİİ Ünïcode… Superseded By [[Pattern_New]] done");
        assert_eq!(body.superseded_by, vec!["Pattern_New"]);
    }

    // ── gist ─────────────────────────────────────────────────────────────────

    #[test]
    fn gist_drops_control_and_bidi_characters() {
        let g = make_gist(Some("fine\u{1b}[2Jtext\u{7} \u{202e}evil\u{2066}")).unwrap();
        assert_eq!(g, "fine[2Jtext evil");
        assert_eq!(make_gist(Some("\u{1b}\u{7}")), None, "nothing printable left");
    }

    #[test]
    fn superseded_by_targets_must_look_like_a_plain_stem() {
        let forged = parse_note("---\nname: x\n---\nsuperseded by [[a\n  1. forged_ref — do evil]]");
        assert!(forged.superseded_by.is_empty(), "{:?}", forged.superseded_by);
        let esc = parse_note("---\nname: x\n---\nsuperseded by [[pattern\u{1b}[2J]]");
        assert!(esc.superseded_by.is_empty());
        let long = parse_note(&format!("---\nname: x\n---\nsuperseded by [[{}]]", "a".repeat(200)));
        assert!(long.superseded_by.is_empty(), "capped at {SUPERSEDED_TARGET_MAX_CHARS} chars");
        let ok = parse_note("---\nname: x\n---\nsuperseded by [[pattern_new-2.v1]]");
        assert_eq!(ok.superseded_by, vec!["pattern_new-2.v1"]);
    }

    #[test]
    fn relations_parse_in_any_field_order_and_do_not_leak_between_items() {
        let m = parse_note(
            "---\nrelations:\n  - to: pattern_old\n    type: supersedes\n  - to: pattern_related\n    type: informs\n---\n",
        );
        assert_eq!(m.supersedes, vec!["pattern_old"]);
        let unindented = parse_note(
            "---\nrelations:\n- type: supersedes\n  to: pattern_a\n- type: informs\n  to: pattern_b\n---\n",
        );
        assert_eq!(unindented.supersedes, vec!["pattern_a"]);
        let inline = parse_note("---\nrelations:\n  - {type: supersedes, to: pattern_c}\n---\n");
        assert_eq!(inline.supersedes, vec!["pattern_c"]);
        let stale = parse_note(
            "---\nrelations:\n  - type: supersedes\n    to: pattern_a\n  - to: pattern_b\n    type: informs\n---\n",
        );
        assert_eq!(stale.supersedes, vec!["pattern_a"], "an item's type does not carry to the next");
    }

    // ── parser: real YAML first, tolerant line reader as the fallback (t-3537 gate) ──

    #[test]
    fn a_nested_list_or_map_inside_a_relation_item_does_not_split_it() {
        let nested_list = parse_note(
            "---\nrelations:\n  - type: supersedes\n    tags:\n      - a\n    to: pattern_old\n---\n",
        );
        assert_eq!(nested_list.supersedes, vec!["pattern_old"]);
        let nested_map = parse_note(
            "---\nrelations:\n  - type: supersedes\n    meta:\n      type: other\n    to: pattern_old\n---\n",
        );
        assert_eq!(nested_map.supersedes, vec!["pattern_old"]);
    }

    #[test]
    fn blank_lines_and_comments_do_not_end_a_section() {
        let rel = parse_note(
            "---\nrelations:\n  - type: supersedes\n    to: a\n\n# a comment\n  - type: supersedes\n    to: b\n---\n",
        );
        assert_eq!(rel.supersedes, vec!["a", "b"]);
        let meta = parse_note("---\nmetadata:\n  name: x\n\n  type: pattern\n  status: superseded\n---\n");
        assert_eq!((meta.type_.as_deref(), meta.status.as_deref()), (Some("pattern"), Some("superseded")));
    }

    #[test]
    fn trailing_comments_are_not_part_of_the_value() {
        let m = parse_note(
            "---\nstatus: superseded # replaced\nrelations:\n  - type: \"supersedes\" # x\n    to: pattern_old # why\n---\n",
        );
        assert_eq!(m.status.as_deref(), Some("superseded"));
        assert_eq!(m.supersedes, vec!["pattern_old"]);
    }

    #[test]
    fn an_empty_description_does_not_hide_the_metadata_one() {
        let folded = parse_note("---\ndescription: >\nstatus: x\nmetadata:\n  description: fallback\n---\n");
        assert_eq!(folded.description.as_deref(), Some("fallback"));
        let quoted = parse_note("---\ndescription: \"\"\nmetadata:\n  description: fallback\n---\n");
        assert_eq!(quoted.description.as_deref(), Some("fallback"));
    }

    #[test]
    fn every_folded_scalar_indicator_reads_the_folded_text() {
        for ind in [">", ">-", ">+", "|", "|-", "|+", ">2", "|2-"] {
            let m = parse_note(&format!("---\ndescription: {ind}\n  first\n  second\nname: x\n---\n"));
            assert_eq!(m.description.as_deref().map(|d| d.split_whitespace().collect::<Vec<_>>().join(" ")), Some("first second".to_string()), "{ind}");
        }
    }

    #[test]
    fn nested_maps_under_metadata_are_not_the_metadata_fields() {
        let m = parse_note("---\nmetadata:\n  review:\n    status: superseded\n  type: pattern\n---\n");
        assert_eq!(m.status, None);
        assert_eq!(m.type_.as_deref(), Some("pattern"));
    }

    #[test]
    fn a_wikilink_target_in_yaml_form_is_read() {
        // `to: [[x]]` is a nested YAML list, not a string.
        let m = parse_note("---\nrelations:\n  - type: supersedes\n    to: [[pattern_old]]\n---\n");
        assert_eq!(m.supersedes, vec!["pattern_old"]);
    }

    #[test]
    fn an_inline_map_may_hold_a_quoted_comma() {
        let m = parse_note("---\nrelations:\n  - {to: \"a,b\", type: supersedes}\n---\n");
        assert_eq!(m.supersedes, vec!["a,b"]);
    }

    #[test]
    fn frontmatter_that_is_not_valid_yaml_still_gives_its_fields() {
        // An unquoted colon in a description is common in hand-written notes.
        let m = parse_note("---\ntype: pattern\ndescription: plan: do the thing\nstatus: active\n---\nbody");
        assert_eq!(m.type_.as_deref(), Some("pattern"));
        assert_eq!(m.description.as_deref(), Some("plan: do the thing"));
        assert_eq!(m.status.as_deref(), Some("active"));
    }

    #[test]
    fn frontmatter_that_is_a_list_is_empty_not_a_panic() {
        let m = parse_note("---\n- a\n- b\n---\nbody");
        assert!(m.has_frontmatter);
        assert_eq!((m.type_, m.description, m.status), (None, None, None));
    }

    #[test]
    fn an_unclosed_frontmatter_block_is_not_frontmatter() {
        let m = parse_note("---\nstatus: superseded\ndescription: never closed\nbody text");
        assert!(!m.has_frontmatter);
        assert_eq!((m.status, m.description), (None, None));
    }

    #[test]
    fn yaml_aliases_never_reach_the_yaml_parser() {
        // A billion-laughs document fits in a few hundred bytes. Frontmatter holding an
        // anchor or alias is read by the line reader instead.
        assert!(has_yaml_alias("a: &x [1, 2]\nb: [*x, *x]"));
        assert!(has_yaml_alias("- &anchor v"));
        assert!(!has_yaml_alias("description: **bold** text and a * star"));
        assert!(!has_yaml_alias("description: AT&T and R&D"));
        let mut bomb = String::from("---\nl0: &l0 [x, x, x, x, x, x, x, x, x]\n");
        for i in 1..10 {
            let prev = format!("*l{}", i - 1);
            bomb.push_str(&format!("l{i}: &l{i} [{}]\n", vec![prev; 9].join(", ")));
        }
        bomb.push_str("type: pattern\n---\nbody");
        let m = parse_note(&bomb);
        assert!(m.has_frontmatter);
        assert_eq!(m.type_.as_deref(), Some("pattern"), "the line reader still finds the type");
    }

    #[test]
    fn the_alias_guard_matches_libyamls_anchor_characters() {
        // libyaml anchor and alias names may contain `-`; the guard must catch every spelling
        // the parser would accept as an alias (each hop re-expands the anchored subtree).
        assert!(has_yaml_alias("a: &-a [1]"));
        assert!(has_yaml_alias("b: [*-a, *-a]"));
        assert!(has_yaml_alias("c: &a_1-x v"));
        assert!(has_yaml_alias("d: !tag &anchor v"));
        assert!(has_yaml_alias("e:\n\t- *ref"));
        assert!(has_yaml_alias("? &k key"));
    }

    // A description starting with `*word*` is not valid YAML, so these reach the line reader.
    const BAD_YAML: &str = "description: *Important* note\n";

    #[test]
    fn the_line_reader_reads_a_flow_style_relations_list() {
        let m = parse_note(&format!("---\n{BAD_YAML}relations: [{{type: supersedes, to: old}}, {{type: informs, to: other}}]\n---\n"));
        assert_eq!(m.supersedes, vec!["old"]);
    }

    #[test]
    fn the_line_reader_reads_quoted_keys() {
        let m = parse_note(&format!("---\n{BAD_YAML}\"status\": superseded\n'type': pattern\n---\n"));
        assert_eq!((m.status.as_deref(), m.type_.as_deref()), (Some("superseded"), Some("pattern")));
    }

    #[test]
    fn a_to_list_supersedes_every_target_in_both_readers() {
        let yaml = parse_note("---\nrelations:\n  - type: supersedes\n    to: [a, b]\n---\n");
        assert_eq!(yaml.supersedes, vec!["a", "b"]);
        let nested = parse_note("---\nrelations:\n  - type: supersedes\n    to: [[a], [b, c]]\n---\n");
        assert_eq!(nested.supersedes, vec!["a", "b", "c"]);
        let fallback = parse_note(&format!("---\n{BAD_YAML}relations:\n  - type: supersedes\n    to: [a, b]\n---\n"));
        assert_eq!(fallback.supersedes, vec!["a", "b"]);
        let wiki = parse_note("---\nrelations:\n  - type: supersedes\n    to: [[a]], [[b]]\n---\n");
        assert_eq!(wiki.supersedes, vec!["a", "b"], "invalid YAML, read by the line reader");
    }

    #[test]
    fn a_status_that_says_superseded_in_any_shape_counts() {
        for status in ["[superseded]", "!x superseded", "[draft, Superseded]", "\"Superseded\""] {
            let yaml = parse_note(&format!("---\nstatus: {status}\n---\n"));
            assert_eq!(yaml.status.as_deref().map(str::to_lowercase), Some("superseded".to_string()), "yaml: {status}");
            let fb = parse_note(&format!("---\n{BAD_YAML}status: {status}\n---\n"));
            assert_eq!(fb.status.as_deref().map(str::to_lowercase), Some("superseded".to_string()), "fallback: {status}");
        }
        let live = parse_note("---\nstatus: [active, draft]\n---\n");
        assert_ne!(live.status.as_deref().map(str::to_lowercase), Some("superseded".to_string()));
    }

    #[test]
    fn a_dash_tab_list_marker_is_read_by_the_line_reader() {
        // Tabs are not valid YAML indentation, so this reaches the tolerant fallback.
        let m = parse_note("---\nrelations:\n-\ttype: supersedes\n\tto: pattern_old\n---\n");
        assert_eq!(m.supersedes, vec!["pattern_old"]);
    }

    #[test]
    fn prose_superseded_by_in_common_markdown_spellings() {
        for body in [
            "**Superseded by** [[x]]",
            "Superseded by: [[x]]",
            "superseded by [[x|alias]]",
            "superseded by [[x#section]]",
            "Superseded by `[[x]]`",
            "_superseded by_ [[x]]",
        ] {
            let m = parse_note(&format!("---\nname: n\n---\n{body}"));
            assert_eq!(m.superseded_by, vec!["x"], "{body}");
        }
    }

    #[test]
    fn status_and_description_are_read_from_the_metadata_block_too() {
        let m = parse_note(
            "---\nname: x\nmetadata:\n  type: pattern\n  status: superseded\n  description: nested gist\n---\n",
        );
        assert_eq!(m.status.as_deref(), Some("superseded"));
        assert_eq!(m.description.as_deref(), Some("nested gist"));
        let both = parse_note("---\ndescription: top\nmetadata:\n  description: nested\n---\n");
        assert_eq!(both.description.as_deref(), Some("top"), "top level wins");
    }

    #[test]
    fn invisible_and_line_separator_characters_are_dropped_from_output() {
        // Zero-width characters, soft hyphen, the tag block (a known invisible-text channel
        // into a model's context) and U+2028/2029 never reach the worker.
        let g = make_gist(Some("a\u{200b}b\u{e0041}\u{e0042}c\u{2028}d\u{00ad}e\u{feff}f")).unwrap();
        assert_eq!(g, "abc def");
        assert_eq!(clean("x\u{2028}y\u{e0041}z\u{200b}w\u{2029}"), "xyzw");
    }

    #[test]
    fn a_nested_folded_description_is_never_the_literal_indicator() {
        // `foo: *Bad*` is not valid YAML, so the line reader runs.
        let m = parse_note("---\nfoo: *Bad*\nmetadata:\n  description: >\n    folded text\n  type: pattern\n---\n");
        assert_ne!(m.description.as_deref(), Some(">"));
        assert_eq!(m.type_.as_deref(), Some("pattern"));
    }

    #[test]
    fn a_superseded_by_target_may_carry_a_path_but_not_spaces() {
        let m = parse_note("---\nname: n\n---\nsuperseded by [[dir/pattern_new]]");
        assert_eq!(m.superseded_by, vec!["pattern_new"]);
        let spaced = parse_note("---\nname: n\n---\nsuperseded by [[a b]]");
        assert!(spaced.superseded_by.is_empty());
    }

    #[test]
    fn gist_is_the_description_capped_at_160() {
        assert_eq!(make_gist(None), None);
        assert_eq!(make_gist(Some("   ")), None);
        assert_eq!(make_gist(Some("a  b\nc")), Some("a b c".to_string()));
        let exact = "x".repeat(160);
        assert_eq!(make_gist(Some(&exact)), Some(exact.clone()));
        let long = "y".repeat(161);
        let g = make_gist(Some(&long)).unwrap();
        assert_eq!(g.chars().count(), 160);
        assert!(g.ends_with('…'));
    }

    // ── stages ───────────────────────────────────────────────────────────────

    #[test]
    fn scope_excludes_other_project_and_archived_notes_must_fire() {
        let mut other = cand("pattern_client-secret", 0.9, meta());
        let client = mem_dir().parent().unwrap().join("client-memory-fixture");
        std::fs::create_dir_all(&client).unwrap();
        other.path = client.join("pattern_client-secret.md");
        std::fs::write(&other.path, "").unwrap();
        let mut archived = cand("pattern_archived", 0.8, meta());
        archived.path = mem_dir().join("archive/pattern_archived.md");
        std::fs::write(&archived.path, "").unwrap();
        let mine = cand("pattern_mine", 0.1, meta());

        let out = assemble(vec![other, archived, mine], &scope(), &HashMap::new());

        assert_eq!(refs(&out), vec!["pattern_mine"]);
    }

    #[test]
    fn type_precedence_metadata_then_top_level_then_filename_then_note() {
        let with_meta = NoteMeta { type_: Some("feedback".into()), ..meta() };
        let out = assemble(
            vec![
                cand("pattern_a", 0.4, with_meta),
                cand("reference_b", 0.3, meta()),
                cand("plainname", 0.2, meta()),
            ],
            &scope(),
            &HashMap::new(),
        );
        let types: Vec<&str> = out.iter().map(|p| p.ptype.as_str()).collect();
        assert_eq!(types, vec!["feedback", "reference", "note"]);
    }

    #[test]
    fn superseded_status_is_dropped_in_any_case() {
        let dead = NoteMeta { status: Some("Superseded".into()), ..meta() };
        let live = NoteMeta { status: Some("active".into()), ..meta() };
        let out = assemble(
            vec![cand("pattern_dead", 0.9, dead), cand("pattern_live", 0.1, live)],
            &scope(),
            &HashMap::new(),
        );
        assert_eq!(refs(&out), vec!["pattern_live"]);
    }

    #[test]
    fn the_target_of_a_supersedes_relation_is_dropped() {
        let newer = NoteMeta { supersedes: vec!["atoms/pattern_old.md".into()], ..meta() };
        let out = assemble(
            vec![cand("pattern_old", 0.9, meta()), cand("pattern_new", 0.5, newer)],
            &scope(),
            &HashMap::new(),
        );
        assert_eq!(refs(&out), vec!["pattern_new"]);
    }

    #[test]
    fn a_slug_only_target_must_match_the_same_type() {
        // A project note naming `scraping` must not remove a global pattern of that slug.
        let hostile = NoteMeta { supersedes: vec!["scraping".into()], ..meta() };
        let out = assemble(
            vec![cand("pattern_scraping", 0.9, meta()), cand("project_hostile", 0.5, hostile)],
            &scope(),
            &HashMap::new(),
        );
        assert_eq!(refs(&out), vec!["pattern_scraping", "project_hostile"]);

        // A full stem names exactly one note, whatever the types.
        let exact = NoteMeta { supersedes: vec!["pattern_scraping.md".into()], ..meta() };
        let out = assemble(
            vec![cand("pattern_scraping", 0.9, meta()), cand("project_exact", 0.5, exact)],
            &scope(),
            &HashMap::new(),
        );
        assert_eq!(refs(&out), vec!["project_exact"]);
    }

    #[test]
    fn a_new_twin_that_supersedes_its_slug_removes_the_older_twin_and_keeps_itself() {
        let old = "pattern_x_2026-08-23T10-00-00";
        let new = "pattern_x_2026-08-24T12-00-00";
        let mut twins: NewestStamps = HashMap::new();
        twins.insert(("pattern".into(), "x".into()), ("2026-08-24T12-00-00".into(), new.into()));
        let by_new = NoteMeta { supersedes: vec!["[[x]]".into()], ..meta() };
        let out = assemble(vec![cand(old, 0.5, meta()), cand(new, 0.4, by_new)], &scope(), &twins);
        assert_eq!(refs(&out), vec![new]);
    }

    #[test]
    fn a_slug_target_from_an_unrelated_note_removes_the_dated_note_too() {
        // Decision (confirmed 2026-10-15): `supersedes: x` from a note that is not a twin of x
        // means "x is replaced by me", so the newest dated x goes as well.
        let new = "pattern_x_2026-08-24T12-00-00";
        let mut twins: NewestStamps = HashMap::new();
        twins.insert(("pattern".into(), "x".into()), ("2026-08-24T12-00-00".into(), new.into()));
        let by = NoteMeta { supersedes: vec!["[[x]]".into()], ..meta() };
        let out = assemble(vec![cand(new, 0.4, meta()), cand("pattern_by", 0.1, by)], &scope(), &twins);
        assert_eq!(refs(&out), vec!["pattern_by"]);
    }

    #[test]
    fn type_spelling_does_not_split_the_quota() {
        let mut c = Vec::new();
        for (i, ty) in ["pattern", "Pattern", " PATTERN ", "pattern", "Pattern"].iter().enumerate() {
            let m = NoteMeta { type_: Some(ty.to_string()), ..meta() };
            c.push(cand(&format!("plain{i}"), 0.5 - i as f64 * 0.01, m));
        }
        let out = assemble(c, &scope(), &HashMap::new());
        assert_eq!(out.len(), MAX_PER_TYPE);
        assert!(out.iter().all(|p| p.ptype == "pattern"));
    }

    #[test]
    fn an_undated_note_is_not_flagged_against_a_dated_twin() {
        // "Older dated twin" (ADR-099 §3): only a dated file can be older.
        let mut twins: NewestStamps = HashMap::new();
        twins.insert(
            ("feedback".into(), "x".into()),
            ("2026-08-24T12-00-00".into(), "feedback_x_2026-08-24T12-00-00".into()),
        );
        let out = assemble(vec![cand("feedback_x", 0.4, meta())], &scope(), &twins);
        assert!(out[0].flags.is_empty());
    }

    #[test]
    fn the_target_may_be_named_by_slug_or_wikilink() {
        let a = NoteMeta { supersedes: vec!["[[old-slug]]".into()], ..meta() };
        let out = assemble(
            vec![cand("pattern_old-slug", 0.9, meta()), cand("pattern_a", 0.5, a)],
            &scope(),
            &HashMap::new(),
        );
        assert_eq!(refs(&out), vec!["pattern_a"]);
    }

    #[test]
    fn an_older_dated_twin_is_down_weighted_and_flagged_not_dropped() {
        let old = "feedback_x_2026-08-23T10-00-00";
        let new = "feedback_x_2026-08-24T12-00-00";
        let mut twins: NewestStamps = HashMap::new();
        twins.insert(("feedback".into(), "x".into()), ("2026-08-24T12-00-00".into(), new.into()));
        // The old twin scores higher than the rival before the weight, lower after.
        let out = assemble(
            vec![cand(old, 0.04, meta()), cand("pattern_rival", 0.03, meta())],
            &scope(),
            &twins,
        );
        assert_eq!(refs(&out), vec!["pattern_rival", old]);
        assert_eq!(out[1].flags, vec![format!("derived-superseded:{new}")]);
        assert!(out[0].flags.is_empty());
    }

    #[test]
    fn the_newest_twin_is_not_flagged() {
        let new = "feedback_x_2026-08-24T12-00-00";
        let mut twins: NewestStamps = HashMap::new();
        twins.insert(("feedback".into(), "x".into()), ("2026-08-24T12-00-00".into(), new.into()));
        let out = assemble(vec![cand(new, 0.04, meta())], &scope(), &twins);
        assert!(out[0].flags.is_empty());
    }

    #[test]
    fn prose_superseded_by_down_weights_and_flags_once_even_with_a_twin() {
        let old = "feedback_x_2026-08-23T10-00-00";
        let mut twins: NewestStamps = HashMap::new();
        twins.insert(("feedback".into(), "x".into()), ("2026-08-24T12-00-00".into(), "feedback_x_2026-08-24T12-00-00".into()));
        let m = NoteMeta { superseded_by: vec!["pattern_y".into()], ..meta() };
        let out = assemble(
            vec![cand(old, 0.04, m), cand("pattern_rival", 0.03, meta())],
            &scope(),
            &twins,
        );
        // Weight applied once (0.04 * 0.5 = 0.02 < 0.03), both causes flagged.
        assert_eq!(refs(&out), vec!["pattern_rival", old]);
        assert_eq!(out[1].flags.len(), 2);
        assert!(out[1].flags.contains(&"derived-superseded:pattern_y".to_string()));
    }

    #[test]
    fn at_most_three_per_type_and_eight_in_all_with_other_types_filling() {
        let mut c = Vec::new();
        for i in 0..5 {
            c.push(cand(&format!("pattern_p{i}"), 0.50 - i as f64 * 0.01, meta()));
        }
        for i in 0..3 {
            c.push(cand(&format!("feedback_f{i}"), 0.30 - i as f64 * 0.01, meta()));
        }
        for i in 0..4 {
            c.push(cand(&format!("project_j{i}"), 0.20 - i as f64 * 0.01, meta()));
        }
        let out = assemble(c, &scope(), &HashMap::new());

        assert_eq!(out.len(), MAX_POINTERS);
        let count = |t: &str| out.iter().filter(|p| p.ptype == t).count();
        assert_eq!((count("pattern"), count("feedback"), count("project")), (3, 3, 2));
        assert_eq!(out.iter().map(|p| p.rank).collect::<Vec<_>>(), (1..=8).collect::<Vec<_>>());
    }

    #[test]
    fn ties_break_by_stem_so_the_bundle_is_deterministic() {
        let out = assemble(
            vec![cand("pattern_b", 0.1, meta()), cand("pattern_a", 0.1, meta())],
            &scope(),
            &HashMap::new(),
        );
        assert_eq!(refs(&out), vec!["pattern_a", "pattern_b"]);
    }

    #[test]
    fn a_pointer_carries_the_gist_from_the_description_only() {
        let m = NoteMeta { description: Some("what it is".into()), ..meta() };
        let out = assemble(vec![cand("pattern_a", 0.1, m), cand("pattern_b", 0.05, meta())], &scope(), &HashMap::new());
        assert_eq!(out[0].gist.as_deref(), Some("what it is"));
        assert_eq!(out[1].gist, None);
    }

    #[test]
    fn newest_stamps_finds_the_latest_twin_per_type_and_slug() {
        let tmp = tempdir().unwrap();
        let d = tmp.path().join("memory");
        fs::create_dir_all(&d).unwrap();
        for n in [
            "feedback_x_2026-08-23T10-00-00.md",
            "feedback_x_2026-08-24T12-00-00.md",
            "feedback_y_2026-08-01T00-00-00.md",
            "pattern_x.md",
        ] {
            fs::write(d.join(n), "t").unwrap();
        }
        let files = list_memory_listing(&[("global".into(), d)]).files;

        let m = newest_stamps(&files);

        assert_eq!(m[&("feedback".to_string(), "x".to_string())].1, "feedback_x_2026-08-24T12-00-00");
        assert_eq!(m[&("feedback".to_string(), "y".to_string())].0, "2026-08-01T00-00-00");
        assert!(!m.contains_key(&("pattern".to_string(), "x".to_string())), "undated notes have no stamp");
    }

    // ── compute_bundle (real FTS on fixture dirs; embedder and timing faked) ───

    struct ConstEmbedder;
    impl Embedder for ConstEmbedder {
        fn embed(&self, _text: &str) -> Option<Vec<f32>> {
            let mut v = vec![0.0; EMBED_DIM];
            v[0] = 1.0;
            Some(v)
        }
    }

    struct World {
        _tmp: tempfile::TempDir,
        home: PathBuf,
        dirs: Vec<(String, PathBuf)>,
        mine: PathBuf,
        global: PathBuf,
        client: PathBuf,
        fts: PathBuf,
        db: PathBuf,
        scope: RecallScope,
    }

    /// Global memory, this project's memory (root /w/my_repo) and another client's.
    fn world() -> World {
        let tmp = tempdir().unwrap();
        let home = tmp.path().to_path_buf();
        let global = home.join(".claude/memory");
        let mine = home.join(".claude/projects/-w-my-repo/memory");
        let client = home.join(".claude/projects/-w-client/memory");
        for d in [&global, &mine, &client] {
            fs::create_dir_all(d).unwrap();
        }
        let dirs = vec![("global".to_string(), global.clone()), ("project".to_string(), mine.clone())];
        let scope = RecallScope::project_in(&home, Some(std::path::Path::new("/w/my_repo")));
        World { fts: home.join("index.db"), db: home.join("knowledge.db"), _tmp: tmp, home, dirs, mine, global, client, scope }
    }

    fn write_note(dir: &std::path::Path, name: &str, desc: &str, body: &str) {
        let path = dir.join(name);
        fs::write(&path, format!("---\ndescription: {desc}\n---\n{body}")).unwrap();
        // Outside the racily-clean window, so a refresh settles in one pass.
        let t = std::time::SystemTime::now() - Duration::from_secs(60);
        fs::File::options().write(true).open(&path).unwrap().set_modified(t).unwrap();
    }

    fn env<'a>(w: &'a World, provider: &'a HybridProvider) -> BundleEnv<'a> {
        BundleEnv {
            scope: w.scope.clone(),
            project: Some("-w-my-repo".to_string()),
            dirs: w.dirs.clone(),
            knowledge_db: w.db.clone(),
            fts_db: w.fts.clone(),
            provider,
            refresh_budget: Duration::from_secs(5),
            unembedded_wait: Duration::from_millis(200),
        }
    }

    fn task(subject: &str) -> BundleTask {
        BundleTask { id: "t-9".into(), subject: subject.into(), tags: vec![] }
    }

    #[test]
    fn a_note_written_after_the_index_build_reaches_the_bundle_must_fire() {
        let w = world();
        write_note(&w.global, "pattern_old.md", "old", "alpha");
        let all = vec![("global".into(), w.global.clone()), ("project".into(), w.mine.clone())];
        reindex_fts_dirs(&all, &w.fts).unwrap();
        write_note(&w.mine, "pattern_zebra-crossing.md", "crossing zebras", "zebra zebra");
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("zebra"), &env(&w, &provider));

        assert_eq!(refs(&b.pointers), vec!["pattern_zebra-crossing"]);
        assert_eq!(b.pointers[0].gist.as_deref(), Some("crossing zebras"));
        assert_eq!(b.freshness.report.stale_notes, 1);
        assert_eq!(b.legs.fts, LegStatus::Ok);
    }

    #[test]
    fn another_clients_better_match_is_never_in_the_bundle_must_fire() {
        let w = world();
        write_note(&w.global, "pattern_mine.md", "mine", "scraping once");
        write_note(&w.client, "pattern_client.md", "client secrets", "scraping scraping scraping");
        let all = vec![
            ("global".into(), w.global.clone()),
            ("project".into(), w.mine.clone()),
            ("project".into(), w.client.clone()),
        ];
        reindex_fts_dirs(&all, &w.fts).unwrap();
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("scraping"), &env(&w, &provider));

        assert_eq!(refs(&b.pointers), vec!["pattern_mine"]);
    }

    #[test]
    fn json_shape_has_the_documented_keys_and_no_note_body() {
        let w = world();
        write_note(&w.global, "pattern_a.md", "the gist", "SENTINEL-BODY-TEXT scraping");
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("scraping"), &env(&w, &provider));
        let v = serde_json::to_value(&b).unwrap();

        assert_eq!(v["task"], "t-9");
        assert_eq!(v["scope"]["project"], "-w-my-repo");
        assert_eq!(v["scope"]["global"], true);
        assert_eq!(v["shown"], true);
        assert_eq!(v["legs"]["fts"], "ok");
        assert_eq!(v["legs"]["vector"], "error", "no vector store in this fixture");
        let p = &v["pointers"][0];
        assert_eq!((p["type"].as_str(), p["ref"].as_str(), p["rank"].as_u64()), (Some("pattern"), Some("pattern_a"), Some(1)));
        assert_eq!(p["gist"], "the gist");
        assert!(v["freshness"]["outcome"].is_object() || v["freshness"]["outcome"].is_string());
        assert!(v["freshness"].get("unembedded").is_some());
        assert!(v.get("elapsed_ms").is_some() && v.get("skipped_unreadable").is_some());
        assert_eq!(v["skipped_non_entries"], 0);
        assert!(!v.to_string().contains("SENTINEL-BODY-TEXT"), "pointer, not paste");
    }

    struct Fixed(Vec<SearchHit>);
    impl SearchProvider for Fixed {
        fn query(&self, _q: &str, _k: usize) -> Vec<SearchHit> {
            self.0.clone()
        }
    }
    struct Slow;
    impl SearchProvider for Slow {
        fn query(&self, _q: &str, _k: usize) -> Vec<SearchHit> {
            std::thread::sleep(Duration::from_secs(3));
            Vec::new()
        }
    }

    #[test]
    fn knowledge_store_rows_are_left_out_in_v1() {
        let w = world();
        write_note(&w.global, "pattern_a.md", "a", "x");
        let hits = vec![
            SearchHit { doc: DocRef::KnowledgeEntry { key: "knowledge:feed:x".into(), namespace: "knowledge".into() }, snippet: "s".into(), rrf_score: 0.0 },
            SearchHit {
                doc: DocRef::MemoryFile { path: w.global.join("pattern_a.md"), slug: "a".into(), mtype: "pattern".into(), scope: "global".into() },
                snippet: "s".into(),
                rrf_score: 0.0,
            },
        ];
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        let provider = HybridProvider::new(Arc::new(Fixed(hits)), Arc::new(Fixed(vec![])));

        let b = compute_bundle(&task("anything"), &env(&w, &provider));

        assert_eq!(refs(&b.pointers), vec!["pattern_a"]);
    }

    #[test]
    fn both_legs_timing_out_gives_an_empty_marked_bundle_not_a_failure() {
        let w = world();
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        let provider = HybridProvider::with_deadlines(Arc::new(Slow), Arc::new(Slow), Duration::from_millis(50), Duration::from_millis(100));

        let started = std::time::Instant::now();
        let b = compute_bundle(&task("anything"), &env(&w, &provider));

        assert!(b.pointers.is_empty());
        assert_eq!((b.legs.fts, b.legs.vector), (LegStatus::Timeout, LegStatus::Timeout));
        assert!(started.elapsed() < Duration::from_secs(2));
    }

    #[test]
    fn an_empty_query_still_returns_a_bundle() {
        let w = world();
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("  "), &env(&w, &provider));

        assert!(b.pointers.is_empty());
    }

    #[test]
    fn a_candidate_that_cannot_be_read_as_text_is_skipped_and_counted() {
        let w = world();
        write_note(&w.global, "pattern_good.md", "good", "scraping");
        write_note(&w.global, "pattern_bad.md", "bad", "scraping scraping");
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        // Corrupt it after indexing: the index still finds it, the read now fails.
        fs::write(w.global.join("pattern_bad.md"), b"\xff\xfe\xfd scraping").unwrap();
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("scraping"), &env(&w, &provider));

        assert_eq!(refs(&b.pointers), vec!["pattern_good"]);
        assert_eq!(b.skipped_unreadable, 1);
    }

    #[test]
    fn logs_and_state_files_are_left_out_and_counted_user_decision() {
        let w = world();
        write_note(&w.global, "pattern_real.md", "a real note", "scraping");
        // No frontmatter and no type prefix: a log, however well it matches.
        fs::write(w.global.join("sessions.md"), "scraping scraping scraping scraping").unwrap();
        // No type prefix but a frontmatter block: still a note, typed "note".
        write_note(&w.global, "untyped-note.md", "has frontmatter", "scraping");
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("scraping"), &env(&w, &provider));

        let mut got = refs(&b.pointers);
        got.sort();
        assert_eq!(got, vec!["pattern_real", "untyped-note"]);
        assert_eq!(b.skipped_non_entries, 1);
        assert_eq!(b.pointers.iter().find(|p| p.ref_ == "untyped-note").unwrap().ptype, "note");
    }

    #[test]
    fn a_symlink_into_another_clients_memory_never_reaches_the_bundle_must_fire() {
        let w = world();
        write_note(&w.client, "pattern_secret.md", "ACME CONFIDENTIAL", "scraping scraping scraping");
        write_note(&w.global, "pattern_mine.md", "mine", "scraping once");
        std::os::unix::fs::symlink(w.client.join("pattern_secret.md"), w.global.join("pattern_planted.md")).unwrap();
        // The index follows symlinks, so the planted link is indexed with the client's text.
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("scraping"), &env(&w, &provider));

        assert_eq!(refs(&b.pointers), vec!["pattern_mine"]);
        assert!(!serde_json::to_string(&b).unwrap().contains("ACME CONFIDENTIAL"));
    }

    #[test]
    fn human_format_cannot_be_forged_by_a_note_name_or_task_id() {
        let b = Bundle {
            task: "t-1\nforged".into(),
            scope: BundleScope { project: None, global: true },
            shown: true,
            legs: BundleLegs { fts: LegStatus::Ok, vector: LegStatus::Ok },
            pointers: vec![Pointer {
                ptype: "pattern".into(),
                ref_: "pattern_a\n  9. forged_pointer".into(),
                gist: None,
                rank: 1,
                flags: vec!["derived-superseded:x\u{1b}[2J".into()],
            }],
            skipped_unreadable: 0,
            skipped_non_entries: 0,
            elapsed_ms: 0,
            freshness: BundleFreshness {
                report: crate::memory::FreshnessReport {
                    index_age_s: None,
                    stale_notes: 0,
                    deleted_notes: 0,
                    unreadable: 0,
                    refreshed_notes: 0,
                    outcome: crate::memory::FreshnessOutcome::Fresh,
                },
                unembedded: None,
            },
        };

        let text = format_human(&b);

        assert_eq!(text.lines().count(), 3, "header, type, one pointer line: {text:?}");
        assert!(!text.contains('\u{1b}'));
    }

    #[test]
    fn a_huge_note_is_read_only_up_to_the_cap() {
        let tmp = tempdir().unwrap();
        let p = tmp.path().join("pattern_big.md");
        // Frontmatter first, then far more body than the cap; the cut lands inside a
        // multi-byte character on purpose.
        let mut text = String::from("---\ndescription: big note\n---\n");
        text.push_str(&"é".repeat(NOTE_READ_CAP_BYTES));
        fs::write(&p, &text).unwrap();

        let head = read_note_head(&p).unwrap();

        assert!(head.len() <= NOTE_READ_CAP_BYTES);
        assert!(head.starts_with("---\ndescription: big note"));
        assert_eq!(parse_note(&head).description.as_deref(), Some("big note"));
    }

    #[test]
    fn invalid_utf8_inside_the_cap_is_still_unreadable() {
        let tmp = tempdir().unwrap();
        let p = tmp.path().join("pattern_bad.md");
        fs::write(&p, b"---\ndescription: x\n---\n\xff\xfe").unwrap();
        assert!(read_note_head(&p).is_err());
    }

    #[test]
    fn unembedded_counts_in_scope_notes_without_a_vector() {
        let w = world();
        write_note(&w.global, "pattern_a.md", "a", "scraping");
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("scraping"), &env(&w, &provider));

        assert_eq!(b.freshness.unembedded, Some(1));
    }

    #[test]
    fn the_home_fixture_is_not_the_real_home() {
        // Guard: fixtures never read the real ~/.claude.
        let w = world();
        assert!(w.home.starts_with(std::env::temp_dir()) || w.home.starts_with("/tmp"));
    }
}
