//! Regression test for t-3414: Claude Code ≥ 2.1.285 opens every stdio MCP
//! server with a version-negotiation probe (`server/discover`) *before*
//! `initialize`. pmcp 2.1.0 could not parse the unknown method, its stdio loop
//! broke, and the process stayed alive without ever answering — Claude Code
//! then reported CONNECT_TIMEOUT after 30s. The server must keep serving after
//! an unknown method, both before and after `initialize`.

use std::io::{BufRead, BufReader, Write};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

const INITIALIZE: &str = r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t-3414","version":"0"}}}"#;
const INITIALIZED: &str = r#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#;
const DISCOVER: &str = r#"{"jsonrpc":"2.0","id":0,"method":"server/discover","params":{}}"#;
const UNKNOWN: &str = r#"{"jsonrpc":"2.0","id":5,"method":"foo/bar","params":{}}"#;
const TOOLS_LIST: &str = r#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#;

struct Server {
    child: Child,
    lines: mpsc::Receiver<String>,
    /// Frames already read whose id nobody asked for yet. Replies may arrive
    /// in any order (an error reply is written from its own task).
    pending: std::cell::RefCell<Vec<serde_json::Value>>,
}

impl Server {
    fn spawn() -> Self {
        let mut child = Command::new(env!("CARGO_BIN_EXE_brana-mcp"))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .expect("spawn brana-mcp");
        let stdout = child.stdout.take().expect("stdout");
        let (tx, rx) = mpsc::channel();
        thread::spawn(move || {
            for line in BufReader::new(stdout).lines().map_while(Result::ok) {
                if tx.send(line).is_err() {
                    break;
                }
            }
        });
        Self {
            child,
            lines: rx,
            pending: std::cell::RefCell::new(Vec::new()),
        }
    }

    fn send(&mut self, msg: &str) {
        let stdin = self.child.stdin.as_mut().expect("stdin");
        writeln!(stdin, "{msg}").expect("write");
        stdin.flush().expect("flush");
    }

    /// Next stdout line that carries the given JSON-RPC id, or None after 5s.
    fn response_for(&self, id: u64) -> Option<serde_json::Value> {
        let has_id = |v: &serde_json::Value| v.get("id").and_then(|i| i.as_u64()) == Some(id);
        let already = self.pending.borrow().iter().position(has_id);
        if let Some(pos) = already {
            return Some(self.pending.borrow_mut().remove(pos));
        }
        let deadline = std::time::Instant::now() + Duration::from_secs(5);
        while let Ok(line) = self.lines.recv_timeout(
            deadline.saturating_duration_since(std::time::Instant::now()),
        ) {
            // Every stdout line must be exactly one JSON-RPC frame. A line that
            // does not parse on its own (e.g. two frames glued together) is a
            // framing bug, never something to skip.
            let v: serde_json::Value = serde_json::from_str(&line)
                .unwrap_or_else(|e| panic!("stdout line is not one JSON frame ({e}): {line}"));
            if has_id(&v) {
                return Some(v);
            }
            self.pending.borrow_mut().push(v);
        }
        None
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn assert_tools_listed(server: &Server) {
    let tools = server
        .response_for(2)
        .expect("tools/list must be answered");
    let names: Vec<&str> = tools["result"]["tools"]
        .as_array()
        .expect("tools array")
        .iter()
        .filter_map(|t| t["name"].as_str())
        .collect();
    assert!(names.contains(&"backlog_query"), "tools: {names:?}");
}

#[test]
fn unknown_method_before_initialize_does_not_wedge_the_server() {
    let mut server = Server::spawn();
    server.send(DISCOVER);
    server.send(INITIALIZE);
    server.send(INITIALIZED);
    server.send(TOOLS_LIST);

    let init = server
        .response_for(1)
        .expect("initialize must be answered after a pre-init server/discover");
    assert_eq!(init["result"]["serverInfo"]["name"], "brana-mcp");
    assert_tools_listed(&server);
}

#[test]
fn unknown_method_after_initialize_gets_method_not_found() {
    let mut server = Server::spawn();
    server.send(INITIALIZE);
    server.send(INITIALIZED);
    server.response_for(1).expect("initialize answered");

    server.send(UNKNOWN);
    server.send(TOOLS_LIST);

    let err = server
        .response_for(5)
        .expect("unknown method must get a JSON-RPC error, not silence");
    assert_eq!(err["error"]["code"], -32601, "{err}");
    assert_tools_listed(&server);
}

/// Claude Code writes its probe and handshake back-to-back. pmcp's transport
/// actor cancels a pending `receive()` whenever it has a frame to send, so an
/// error reply written from inside `receive()` could be cut mid-frame and
/// glued to the next response. Repeat a burst a few times to make the race
/// likely.
#[test]
fn burst_of_frames_never_glues_stdout() {
    const PING: &str = r#"{"jsonrpc":"2.0","id":6,"method":"ping"}"#;
    for _ in 0..20 {
        let mut server = Server::spawn();
        let burst = [DISCOVER, INITIALIZE, INITIALIZED, TOOLS_LIST, UNKNOWN, PING].join("\n");
        server.send(&burst);
        for id in [0, 1, 2, 5, 6] {
            server
                .response_for(id)
                .unwrap_or_else(|| panic!("no response for id {id}"));
        }
    }
}
