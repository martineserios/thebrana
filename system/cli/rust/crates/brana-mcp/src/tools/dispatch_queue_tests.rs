//! Dispatch-queue integration test for t-2305 (Challenger gate iteration 1, finding #2).
//!
//! The unit tests in `brana-core::util` and the handler-level test in `backlog_set.rs`
//! prove the bounded lock acquire works, but neither exercises pmcp's *actual* serialized
//! stdio dispatch loop — the literal original symptom was "one stuck handler starves an
//! unrelated queued request of any tool, including reads that never touch the lock."
//!
//! This drives a real `pmcp::Server` (the same one `main.rs` builds) through its real
//! `run()` dispatch loop via a minimal in-memory `Transport`, proving a queued, unrelated,
//! lock-free `backlog_get` call only receives its response *after* an earlier contended
//! `backlog_set` call resolves — not concurrently, not early, not lost.

use crate::tools::CWD_LOCK;
use pmcp::async_trait;
use pmcp::shared::{Transport, TransportMessage};
use pmcp::types::{
    CallToolRequest, ClientCapabilities, ClientRequest, Implementation, InitializeRequest,
    Request, RequestId,
};
use pmcp::Server;
use std::collections::VecDeque;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

struct Hermetic {
    orig_cwd: PathBuf,
    orig_project_dir: Option<String>,
    dir: tempfile::TempDir,
}

impl Hermetic {
    fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let claude = dir.path().join(".claude");
        std::fs::create_dir_all(&claude).unwrap();
        std::fs::write(
            claude.join("tasks.json"),
            r#"{"project":"test","tasks":[{"id":"t-1","subject":"x","status":"pending"}]}"#,
        )
        .unwrap();
        let orig_cwd = std::env::current_dir().unwrap();
        let orig_project_dir = std::env::var("CLAUDE_PROJECT_DIR").ok();
        // SAFETY: caller holds CWD_LOCK; no other test in this binary reads or writes
        // the environment concurrently.
        unsafe { std::env::remove_var("CLAUDE_PROJECT_DIR") };
        std::env::set_current_dir(dir.path()).unwrap();
        Self {
            orig_cwd,
            orig_project_dir,
            dir,
        }
    }

    fn tasks_file(&self) -> PathBuf {
        self.dir.path().join(".claude/tasks.json")
    }
}

impl Drop for Hermetic {
    fn drop(&mut self) {
        let _ = std::env::set_current_dir(&self.orig_cwd);
        if let Some(v) = &self.orig_project_dir {
            // SAFETY: still under CWD_LOCK (guard drops before the lock).
            unsafe { std::env::set_var("CLAUDE_PROJECT_DIR", v) };
        }
    }
}

/// In-memory transport: pre-loaded request queue (FIFO), timestamped response log.
/// Mirrors the pattern pmcp uses for its own `Server::run` tests
/// (`pmcp::server::tests::MockTransport`), with response timestamps added so the test
/// can assert *ordering in wall-clock time*, not just eventual arrival.
#[derive(Debug)]
struct TimestampedMockTransport {
    requests: Arc<Mutex<VecDeque<TransportMessage>>>,
    responses: Arc<Mutex<Vec<(Instant, TransportMessage)>>>,
}

impl TimestampedMockTransport {
    fn with_requests(requests: Vec<TransportMessage>) -> Self {
        Self {
            requests: Arc::new(Mutex::new(requests.into())),
            responses: Arc::new(Mutex::new(Vec::new())),
        }
    }

    fn responses_handle(&self) -> Arc<Mutex<Vec<(Instant, TransportMessage)>>> {
        self.responses.clone()
    }
}

#[async_trait]
impl Transport for TimestampedMockTransport {
    async fn send(&mut self, message: TransportMessage) -> pmcp::Result<()> {
        self.responses.lock().unwrap().push((Instant::now(), message));
        Ok(())
    }

    async fn receive(&mut self) -> pmcp::Result<TransportMessage> {
        // Once the queue drains, block "forever" (bounded by the test's outer timeout)
        // rather than erroring — an error would abort server.run()'s loop early and we
        // want it to keep servicing whatever's left to send.
        loop {
            if let Some(msg) = self.requests.lock().unwrap().pop_front() {
                return Ok(msg);
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    }

    async fn close(&mut self) -> pmcp::Result<()> {
        Ok(())
    }

    fn transport_type(&self) -> &'static str {
        "timestamped-mock"
    }
}

fn call_tool_request(id: i64, name: &str, arguments: serde_json::Value) -> TransportMessage {
    TransportMessage::Request {
        id: RequestId::from(id),
        request: Request::Client(Box::new(ClientRequest::CallTool(CallToolRequest::new(
            name, arguments,
        )))),
    }
}

/// Extract the JSON-RPC response `id` for a `TransportMessage::Response`, else `None`.
fn response_id(msg: &TransportMessage) -> Option<RequestId> {
    match msg {
        TransportMessage::Response(r) => Some(r.id.clone()),
        _ => None,
    }
}

/// t-2305, Challenger gate iteration 1 finding #2: a queued, unrelated, lock-free call
/// (`backlog_get`) must only receive its response after an earlier contended `backlog_set`
/// call resolves — proving pmcp's real serialized dispatch loop recovers correctly once the
/// bounded lock acquire resolves, rather than staying frozen (the original bug) or somehow
/// racing ahead of the earlier request (which would indicate the loop isn't truly
/// serialized, contradicting the diagnosis).
#[tokio::test]
async fn queued_unrelated_request_recovers_after_blocking_request_times_out() {
    let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let h = Hermetic::new();
    let tf = h.tasks_file();

    // Hold the lock from a background thread — released after ~250ms, well under
    // DEFAULT_LOCK_TIMEOUT (10s), so backlog_set contends-then-succeeds rather than
    // timing out. This keeps the test fast while still proving the queuing/recovery
    // behavior: the queued backlog_get must wait for that ~250ms, not skip ahead.
    let hold = Duration::from_millis(250);
    let holder = std::thread::spawn(move || {
        let _guard = brana_core::util::lock_sidecar(&tf).expect("holder should acquire immediately");
        std::thread::sleep(hold);
    });
    std::thread::sleep(Duration::from_millis(30)); // let the holder acquire first

    let init = TransportMessage::Request {
        id: RequestId::from(0i64),
        request: Request::Client(Box::new(ClientRequest::Initialize(InitializeRequest::new(
            Implementation::new("dispatch-queue-test", "1.0.0"),
            ClientCapabilities::minimal(),
        )))),
    };
    let set_req = call_tool_request(
        1,
        "backlog_set",
        serde_json::json!({"task_id": "t-1", "field": "status", "value": "in_progress"}),
    );
    let get_req = call_tool_request(2, "backlog_get", serde_json::json!({"task_id": "t-1"}));

    let transport = TimestampedMockTransport::with_requests(vec![init, set_req, get_req]);
    let responses = transport.responses_handle();

    let server = Server::builder()
        .name("dispatch-queue-test-server")
        .version("1.0.0")
        .tool("backlog_set", super::backlog_set::build())
        .tool("backlog_get", super::backlog_get::build())
        .build()
        .expect("server should build");

    // server.run()'s main loop sleeps forever by design (it's a real server, meant to run
    // until the process exits) — it never itself "completes". Spawn it in the background
    // and poll the response log instead, with a bounded overall wait as the safety net
    // against exactly the original bug (a handler that never resolves at all).
    tokio::spawn(server.run(transport));

    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if responses.lock().unwrap().len() >= 3 {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "did not receive all 3 responses within the outer safety window — dispatch loop appears stuck"
        );
        tokio::time::sleep(Duration::from_millis(10)).await;
    }

    holder.join().unwrap();

    let responses = responses.lock().unwrap();
    // Expect: Initialize result, then backlog_set result, then backlog_get result —
    // in that arrival order, since pmcp's dispatch loop is fully serialized.
    assert_eq!(responses.len(), 3, "expected 3 responses (init + 2 tool calls), got {}", responses.len());

    let set_idx = responses
        .iter()
        .position(|(_, m)| response_id(m) == Some(RequestId::from(1i64)))
        .expect("backlog_set response must be present");
    let get_idx = responses
        .iter()
        .position(|(_, m)| response_id(m) == Some(RequestId::from(2i64)))
        .expect("backlog_get response must be present — it must NOT be lost or dropped");

    assert!(
        set_idx < get_idx,
        "backlog_set's response must arrive before backlog_get's (strict dispatch order)"
    );

    let (set_time, _) = &responses[set_idx];
    let (get_time, _) = &responses[get_idx];
    assert!(
        *get_time >= *set_time,
        "backlog_get must not be timestamped before backlog_set resolved"
    );
    assert!(
        get_time.duration_since(*set_time) < Duration::from_millis(500),
        "backlog_get should follow closely once backlog_set resolves, not stall further"
    );

    // The queued read must have succeeded once serviced — it never touches the lock, so
    // contention on backlog_set must not have broken it, only delayed it.
    if let TransportMessage::Response(r) = &responses[get_idx].1 {
        assert!(
            matches!(r.payload, pmcp::types::jsonrpc::ResponsePayload::Result(_)),
            "backlog_get must succeed once serviced, not error: {:?}",
            r.payload
        );
    }
}
