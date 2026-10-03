//! Regression test for t-3462: a client that writes its requests and then
//! closes stdin (a one-shot `echo ... | brana-mcp`, the CI stdio-isolation
//! test, any client shutting down with a call in flight) must still get every
//! response. pmcp 2.22's transport actor stops on the first receive error, and
//! end-of-input is one, so a request already queued to the worker was answered
//! by nobody: the actor — the only task that writes — was gone. The server
//! must drain in-flight requests at EOF, then exit on its own.

use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const INITIALIZE: &str = r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t-3462","version":"0"}}}"#;
const INITIALIZED: &str = r#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#;
const TOOLS_LIST: &str = r#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#;
const PING: &str = r#"{"jsonrpc":"2.0","id":3,"method":"ping"}"#;

/// Write the burst, close stdin, collect every stdout line until the process
/// exits. Returns the ids answered and whether it exited within `limit`.
fn one_shot(burst: &[&str], limit: Duration) -> (Vec<u64>, bool) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_brana-mcp"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn brana-mcp");
    {
        let mut stdin = child.stdin.take().expect("stdin");
        writeln!(stdin, "{}", burst.join("\n")).expect("write");
        stdin.flush().expect("flush");
    } // stdin dropped here: EOF
    let stdout = child.stdout.take().expect("stdout");
    let reader = std::thread::spawn(move || {
        BufReader::new(stdout)
            .lines()
            .map_while(Result::ok)
            .map(|l| {
                let v: serde_json::Value = serde_json::from_str(&l)
                    .unwrap_or_else(|e| panic!("stdout line is not one JSON frame ({e}): {l}"));
                v.get("id").and_then(|i| i.as_u64()).unwrap_or(u64::MAX)
            })
            .collect::<Vec<u64>>()
    });
    let start = Instant::now();
    let exited = loop {
        match child.try_wait().expect("try_wait") {
            Some(_) => break true,
            None if start.elapsed() > limit => {
                let _ = child.kill();
                let _ = child.wait();
                break false;
            },
            None => std::thread::sleep(Duration::from_millis(20)),
        }
    };
    let ids = reader.join().expect("reader thread");
    (ids, exited)
}

#[test]
fn requests_written_before_eof_are_all_answered() {
    // Repeat: the race (EOF read before the worker answers) is timing-dependent.
    for round in 0..20 {
        let (ids, _) = one_shot(&[INITIALIZE, INITIALIZED, TOOLS_LIST, PING], Duration::from_secs(10));
        for want in [1, 2, 3] {
            assert!(ids.contains(&want), "round {round}: no response for id {want}; got {ids:?}");
        }
    }
}

#[test]
fn server_exits_on_its_own_after_draining() {
    let (ids, exited) = one_shot(&[INITIALIZE, INITIALIZED, PING], Duration::from_secs(10));
    assert!(ids.contains(&3), "ping answered: {ids:?}");
    assert!(exited, "brana-mcp must exit after EOF once in-flight requests are answered, not hang");
}
