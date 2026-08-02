//! Build receipts — `brana.build-receipt/v1` (t-2593, ADR-076).
//!
//! Pure logic only: schema, digests, structural validation, and the gate comparison.
//! **Every function here is zero-I/O.** All re-derivation from git lives in the caller
//! (`brana-cli`), by design — the comparison function takes no repo handle so it cannot be
//! tested against a repo it also mutates.
//!
//! Spec: `docs/architecture/features/build-receipts.md`.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub const SCHEMA: &str = "brana.build-receipt/v1";

const DOMAIN_PATHS: &str = "brana.build-receipt/v1:paths";
const DOMAIN_AC: &str = "brana.build-receipt/v1:ac";

/// `passed` iff the executed command exited 0. There is deliberately **no** constructor
/// taking a caller-supplied verdict — see [`Outcome::from_exit_code`].
#[derive(Serialize, Deserialize, PartialEq, Eq, Debug, Clone, Copy)]
#[serde(rename_all = "lowercase")]
pub enum Outcome {
    Passed,
    Failed,
}

impl Outcome {
    /// The only way to produce an `Outcome`. `mint` derives it from the exit code of the
    /// subprocess it ran itself; no CLI flag, env var, or config key reaches this.
    pub fn from_exit_code(code: i32) -> Outcome {
        if code == 0 {
            Outcome::Passed
        } else {
            Outcome::Failed
        }
    }
}

#[derive(Serialize, Deserialize, PartialEq, Eq, Debug, Clone)]
#[serde(deny_unknown_fields)]
pub struct RepoBinding {
    pub base_commit: String,
    pub base_tree: String,
    pub candidate_commit: String,
    pub candidate_tree: String,
    pub paths_digest: String,
}

#[derive(Serialize, Deserialize, PartialEq, Eq, Debug, Clone)]
#[serde(deny_unknown_fields)]
pub struct Execution {
    pub argv: Vec<String>,
    pub cwd_rel: String,
    pub duration_ms: u64,
    pub exit_code: i32,
    pub output_bytes: u64,
    pub stderr_sha256: String,
    pub stdout_sha256: String,
}

/// Fields are declared in alphabetical order so canonical JSON has sorted keys.
#[derive(Serialize, Deserialize, PartialEq, Eq, Debug, Clone)]
#[serde(deny_unknown_fields)]
pub struct Receipt {
    pub ac_digest: String,
    pub execution: Execution,
    pub minted_at: String,
    pub outcome: Outcome,
    pub repo: RepoBinding,
    pub schema: String,
    pub task_id: String,
}

#[derive(Debug, PartialEq, Eq)]
pub enum StructureError {
    BadSchema(String),
    BadHex { field: &'static str, value: String },
    EmptyArgv,
    EmptyTaskId,
    /// `outcome` disagrees with `execution.exit_code`. This is the structural expression of
    /// ADR-076 D1: a receipt claiming `passed` over a non-zero exit is incoherent, whoever
    /// wrote it.
    OutcomeIncoherent { outcome: Outcome, exit_code: i32 },
}

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum GateResult {
    Allow,
    ScopeChanged,
    Invalidated,
}

/// Facts the caller re-derived from the repository. Passing these in rather than reading
/// them here is what keeps [`compare`] pure.
#[derive(Debug, Clone)]
pub struct DerivedFacts {
    /// Is `repo.candidate_commit` reachable from the ref being gated?
    pub candidate_reachable: bool,
    /// `paths_digest` recomputed from `base_commit..<gated ref>` for this task now.
    pub paths_digest: String,
    /// `ac_digest` recomputed from the task's current `AC:` lines.
    pub ac_digest: String,
    /// Digests recomputed by re-hashing the stored output blobs. `None` when the blobs are
    /// absent, which is itself a failure — an unverifiable hash is a claim, not evidence.
    pub stdout_sha256: Option<String>,
    pub stderr_sha256: Option<String>,
}

/// Domain-separated, length-prefixed digest over an ordered item list.
fn domain_digest(domain: &str, items: &[String]) -> String {
    let mut buf: Vec<u8> = Vec::new();
    buf.extend_from_slice(domain.as_bytes());
    buf.push(0);
    for item in items {
        push_varint(&mut buf, item.len() as u64);
        buf.extend_from_slice(item.as_bytes());
    }
    sha256_hex(&buf)
}

/// LEB128. Length-prefixing is what stops `["ab","c"]` and `["a","bc"]` from colliding.
fn push_varint(out: &mut Vec<u8>, mut v: u64) {
    loop {
        let byte = (v & 0x7f) as u8;
        v >>= 7;
        if v == 0 {
            out.push(byte);
            return;
        }
        out.push(byte | 0x80);
    }
}

fn is_hex(s: &str, len: usize) -> bool {
    s.len() == len && s.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// Digest over the changed-path set. Sorts internally — callers need not.
pub fn paths_digest(paths: &[String]) -> String {
    let mut sorted = paths.to_vec();
    sorted.sort();
    domain_digest(DOMAIN_PATHS, &sorted)
}

/// Digest over the task's `AC:` lines, verbatim, in file order (NOT sorted — order is
/// part of what is being attested).
pub fn ac_digest(lines: &[String]) -> String {
    domain_digest(DOMAIN_AC, lines)
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(bytes);
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

/// Strict parse: unknown fields rejected, trailing values after the top-level object
/// rejected.
pub fn parse_receipt(s: &str) -> Result<Receipt, String> {
    // `from_str` runs `Deserializer::end()`, which rejects trailing values; the
    // `deny_unknown_fields` attributes reject unknown keys at every level.
    serde_json::from_str(s).map_err(|e| e.to_string())
}

/// Canonical JSON — sorted keys (field declaration order is alphabetical), no
/// insignificant whitespace. Round-trips byte-stable.
pub fn to_canonical_json(r: &Receipt) -> String {
    // Struct fields are declared alphabetically, so serde emits sorted keys with no
    // insignificant whitespace.
    serde_json::to_string(r).expect("receipt is always serialisable")
}

/// Pure shape validation. No repo handle, no I/O.
pub fn validate_structure(r: &Receipt) -> Result<(), StructureError> {
    if r.schema != SCHEMA {
        return Err(StructureError::BadSchema(r.schema.clone()));
    }
    if r.task_id.is_empty() {
        return Err(StructureError::EmptyTaskId);
    }
    if r.execution.argv.is_empty() {
        return Err(StructureError::EmptyArgv);
    }

    let hex64 = [
        ("ac_digest", &r.ac_digest),
        ("repo.paths_digest", &r.repo.paths_digest),
        ("execution.stdout_sha256", &r.execution.stdout_sha256),
        ("execution.stderr_sha256", &r.execution.stderr_sha256),
    ];
    for (field, value) in hex64 {
        if !is_hex(value, 64) {
            return Err(StructureError::BadHex { field, value: value.clone() });
        }
    }

    let hex40 = [
        ("repo.base_commit", &r.repo.base_commit),
        ("repo.base_tree", &r.repo.base_tree),
        ("repo.candidate_commit", &r.repo.candidate_commit),
        ("repo.candidate_tree", &r.repo.candidate_tree),
    ];
    for (field, value) in hex40 {
        if !is_hex(value, 40) {
            return Err(StructureError::BadHex { field, value: value.clone() });
        }
    }

    // ADR-076 D1, structurally: the verdict must follow the exit code it claims to
    // summarise. A forged `passed` over a non-zero exit dies here regardless of who
    // wrote the file.
    let derived = Outcome::from_exit_code(r.execution.exit_code);
    if r.outcome != derived {
        return Err(StructureError::OutcomeIncoherent {
            outcome: r.outcome,
            exit_code: r.execution.exit_code,
        });
    }
    Ok(())
}

/// Pure comparison. No repo handle, no I/O.
pub fn compare(r: &Receipt, d: &DerivedFacts) -> GateResult {
    // `invalidated` outranks `scope-changed`: a void approval is not recoverable by
    // re-scoping.
    if !d.candidate_reachable {
        return GateResult::Invalidated;
    }
    if r.outcome != Outcome::Passed {
        return GateResult::Invalidated;
    }
    if d.ac_digest != r.ac_digest {
        return GateResult::Invalidated;
    }
    // An unverifiable hash is a claim, not evidence — a missing blob fails closed.
    match (&d.stdout_sha256, &d.stderr_sha256) {
        (Some(out), Some(err))
            if *out == r.execution.stdout_sha256 && *err == r.execution.stderr_sha256 => {}
        _ => return GateResult::Invalidated,
    }
    if d.paths_digest != r.repo.paths_digest {
        return GateResult::ScopeChanged;
    }
    GateResult::Allow
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(v: &str) -> String {
        v.to_string()
    }

    fn hex64(seed: u8) -> String {
        std::iter::repeat(format!("{seed:02x}")).take(32).collect()
    }

    fn hex40(seed: u8) -> String {
        std::iter::repeat(format!("{seed:02x}")).take(20).collect()
    }

    fn receipt() -> Receipt {
        Receipt {
            ac_digest: hex64(0xaa),
            execution: Execution {
                argv: vec![s("./validate.sh")],
                cwd_rel: s("."),
                duration_ms: 1000,
                exit_code: 0,
                output_bytes: 12,
                stderr_sha256: hex64(0xbb),
                stdout_sha256: hex64(0xcc),
            },
            minted_at: s("2026-08-02T14:03:11Z"),
            outcome: Outcome::Passed,
            repo: RepoBinding {
                base_commit: hex40(0x01),
                base_tree: hex40(0x02),
                candidate_commit: hex40(0x03),
                candidate_tree: hex40(0x04),
                paths_digest: hex64(0xdd),
            },
            schema: s(SCHEMA),
            task_id: s("t-2593"),
        }
    }

    fn facts(r: &Receipt) -> DerivedFacts {
        DerivedFacts {
            candidate_reachable: true,
            paths_digest: r.repo.paths_digest.clone(),
            ac_digest: r.ac_digest.clone(),
            stdout_sha256: Some(r.execution.stdout_sha256.clone()),
            stderr_sha256: Some(r.execution.stderr_sha256.clone()),
        }
    }

    // ---- T2: no input reaches `outcome` -------------------------------------------

    #[test]
    fn t2_outcome_is_derived_from_exit_code_only() {
        assert_eq!(Outcome::from_exit_code(0), Outcome::Passed);
        for code in [1, 2, 127, -1, 130] {
            assert_eq!(Outcome::from_exit_code(code), Outcome::Failed, "code {code}");
        }
    }

    #[test]
    fn t2_receipt_claiming_passed_over_nonzero_exit_is_rejected() {
        let mut r = receipt();
        r.execution.exit_code = 1;
        // outcome still `passed` — the forged-verdict case
        assert_eq!(
            validate_structure(&r),
            Err(StructureError::OutcomeIncoherent {
                outcome: Outcome::Passed,
                exit_code: 1
            })
        );
    }

    #[test]
    fn t2_receipt_claiming_failed_over_zero_exit_is_rejected() {
        let mut r = receipt();
        r.outcome = Outcome::Failed;
        assert!(matches!(
            validate_structure(&r),
            Err(StructureError::OutcomeIncoherent { .. })
        ));
    }

    // ---- T10/T11: strict parsing -------------------------------------------------

    #[test]
    fn t10_unknown_field_rejected() {
        let mut v: serde_json::Value =
            serde_json::from_str(&to_canonical_json(&receipt())).unwrap();
        v.as_object_mut()
            .unwrap()
            .insert(s("extra"), serde_json::json!(1));
        assert!(parse_receipt(&v.to_string()).is_err());
    }

    #[test]
    fn t10_unknown_nested_field_rejected() {
        let mut v: serde_json::Value =
            serde_json::from_str(&to_canonical_json(&receipt())).unwrap();
        v["execution"]
            .as_object_mut()
            .unwrap()
            .insert(s("sneaky"), serde_json::json!(true));
        assert!(parse_receipt(&v.to_string()).is_err());
    }

    #[test]
    fn t11_trailing_value_rejected() {
        let doc = format!("{}{{}}", to_canonical_json(&receipt()));
        assert!(parse_receipt(&doc).is_err());
    }

    #[test]
    fn roundtrip_is_byte_stable_and_key_sorted() {
        let a = to_canonical_json(&receipt());
        let b = to_canonical_json(&parse_receipt(&a).unwrap());
        assert_eq!(a, b);

        // Assert on the RAW STRING. Round-tripping through serde_json::Map would sort
        // the keys itself (it is a BTreeMap by default) and prove nothing.
        let order = ["ac_digest", "execution", "minted_at", "outcome", "repo", "schema", "task_id"];
        let mut last = 0usize;
        for key in order {
            let at = a
                .find(&format!("\"{key}\":"))
                .unwrap_or_else(|| panic!("{key} missing from canonical JSON"));
            assert!(at > last, "canonical JSON keys out of order at {key}");
            last = at;
        }
    }

    // ---- T12: length-prefixing --------------------------------------------------

    #[test]
    fn t12_ambiguous_path_sets_produce_distinct_digests() {
        assert_ne!(
            paths_digest(&[s("ab"), s("c")]),
            paths_digest(&[s("a"), s("bc")])
        );
    }

    #[test]
    fn t12_ac_lines_are_length_prefixed_too() {
        assert_ne!(ac_digest(&[s("ab"), s("c")]), ac_digest(&[s("a"), s("bc")]));
    }

    #[test]
    fn paths_digest_is_order_independent_ac_digest_is_not() {
        assert_eq!(
            paths_digest(&[s("b.rs"), s("a.rs")]),
            paths_digest(&[s("a.rs"), s("b.rs")])
        );
        assert_ne!(
            ac_digest(&[s("second"), s("first")]),
            ac_digest(&[s("first"), s("second")])
        );
    }

    #[test]
    fn domains_are_separated() {
        // Same item list, different domain -> different digest.
        assert_ne!(paths_digest(&[s("x")]), ac_digest(&[s("x")]));
    }

    // ---- structural validation ---------------------------------------------------

    #[test]
    fn valid_receipt_passes() {
        assert_eq!(validate_structure(&receipt()), Ok(()));
    }

    #[test]
    fn wrong_schema_rejected() {
        let mut r = receipt();
        r.schema = s("gentle.receipt/v1");
        assert!(matches!(
            validate_structure(&r),
            Err(StructureError::BadSchema(_))
        ));
    }

    #[test]
    fn malformed_digest_rejected() {
        for bad in ["", "xyz", "AABB", &"ab".repeat(31)] {
            let mut r = receipt();
            r.ac_digest = s(bad);
            assert!(
                matches!(validate_structure(&r), Err(StructureError::BadHex { .. })),
                "should reject ac_digest {bad:?}"
            );
        }
    }

    #[test]
    fn uppercase_hex_rejected() {
        let mut r = receipt();
        // Seed must contain a-f: `hex40(0x01)` is all digits, so `to_uppercase()` would
        // be a no-op and the test would pass without exercising anything.
        r.repo.base_commit = hex40(0xab).to_uppercase();
        assert!(r.repo.base_commit.contains('A'), "fixture must actually be uppercase");
        assert!(matches!(
            validate_structure(&r),
            Err(StructureError::BadHex { .. })
        ));
    }

    #[test]
    fn empty_argv_rejected() {
        let mut r = receipt();
        r.execution.argv = vec![];
        assert_eq!(validate_structure(&r), Err(StructureError::EmptyArgv));
    }

    // ---- T6/T7/T8/T9: the gate ---------------------------------------------------

    #[test]
    fn allow_when_everything_matches() {
        let r = receipt();
        assert_eq!(compare(&r, &facts(&r)), GateResult::Allow);
    }

    #[test]
    fn t6_paths_moved_is_scope_changed_not_invalidated() {
        let r = receipt();
        let mut d = facts(&r);
        d.paths_digest = hex64(0xee);
        assert_eq!(compare(&r, &d), GateResult::ScopeChanged);
    }

    #[test]
    fn t7_edited_ac_is_invalidated() {
        let r = receipt();
        let mut d = facts(&r);
        d.ac_digest = hex64(0xee);
        assert_eq!(compare(&r, &d), GateResult::Invalidated);
    }

    #[test]
    fn t8_unreachable_candidate_is_invalidated() {
        let r = receipt();
        let mut d = facts(&r);
        d.candidate_reachable = false;
        assert_eq!(compare(&r, &d), GateResult::Invalidated);
    }

    #[test]
    fn failed_outcome_never_allows() {
        let mut r = receipt();
        r.execution.exit_code = 1;
        r.outcome = Outcome::Failed;
        assert_eq!(compare(&r, &facts(&r)), GateResult::Invalidated);
    }

    #[test]
    fn t9_tampered_stdout_hash_is_invalidated() {
        let r = receipt();
        let mut d = facts(&r);
        d.stdout_sha256 = Some(hex64(0xee)); // re-hashed blob disagrees with the receipt
        assert_eq!(compare(&r, &d), GateResult::Invalidated);
    }

    #[test]
    fn t9_missing_output_blob_is_invalidated() {
        let r = receipt();
        let mut d = facts(&r);
        d.stdout_sha256 = None; // an unverifiable hash is a claim, not evidence
        assert_eq!(compare(&r, &d), GateResult::Invalidated);
    }

    #[test]
    fn invalidated_beats_scope_changed_when_both_apply() {
        let r = receipt();
        let mut d = facts(&r);
        d.paths_digest = hex64(0xee);
        d.ac_digest = hex64(0xef);
        assert_eq!(compare(&r, &d), GateResult::Invalidated);
    }

    // ---- T15: purity -------------------------------------------------------------

    #[test]
    fn t15_compare_works_with_no_repo_present() {
        // Running from a directory that is not a git repo at all. If `compare` did any
        // I/O this would change behaviour; it must not.
        let prev = std::env::current_dir().unwrap();
        std::env::set_current_dir("/").unwrap();
        let r = receipt();
        let got = compare(&r, &facts(&r));
        std::env::set_current_dir(prev).unwrap();
        assert_eq!(got, GateResult::Allow);
    }
}
