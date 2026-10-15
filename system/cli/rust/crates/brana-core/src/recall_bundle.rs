//! The recall bundle (t-3537, ADR-099): at most 8 typed pointers for one task.
//! Design: docs/architecture/features/recall-bundle.md §"Bundle assembly".

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

    fn cand(stem: &str, rrf: f64, m: NoteMeta) -> Candidate {
        let (file_type, slug) = crate::memory::memory_file_identity(stem);
        Candidate {
            path: PathBuf::from(format!("/h/.claude/memory/{stem}.md")),
            stem: stem.to_string(),
            slug,
            file_type,
            rrf,
            meta: m,
        }
    }

    fn scope() -> RecallScope {
        RecallScope::Dirs(vec![PathBuf::from("/h/.claude/memory")])
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

    // ── gist ─────────────────────────────────────────────────────────────────

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
        other.path = PathBuf::from("/h/.claude/projects/-w-client/memory/pattern_client-secret.md");
        let mut archived = cand("pattern_archived", 0.8, meta());
        archived.path = PathBuf::from("/h/.claude/memory/archive/pattern_archived.md");
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
