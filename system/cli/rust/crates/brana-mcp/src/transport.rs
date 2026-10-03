//! Lenient stdio transport (t-3414).
//!
//! pmcp's `StdioTransport` turns any request whose method it does not know
//! into a transport *receive error*, and the server loop breaks on receive
//! errors. Claude Code ≥ 2.1.285 opens every stdio server with a
//! version-negotiation probe (`server/discover`) before `initialize`, so with
//! the stock transport the server went silent on the very first line and
//! Claude Code reported CONNECT_TIMEOUT after 30s.
//!
//! This transport reads stdin itself. Lines pmcp can parse are handed over
//! untouched; a request with an unknown method is answered with the JSON-RPC
//! `-32601 Method not found` error (as the spec requires) and reading
//! continues; an unknown notification or an unparseable line is skipped.
//!
//! Writing is delegated to the stock `StdioTransport`, so the wire format of
//! everything the server sends is unchanged. The writer is shared behind a
//! mutex and the error replies are written from their own task: pmcp's
//! transport actor drops a pending `receive()` whenever it has a frame to
//! send, and a write started inside `receive()` would be cut mid-frame.
//!
//! **Draining at end of input (t-3462).** pmcp 2.22's transport actor stops on
//! the first receive error, and end-of-input is one: a request it had already
//! queued to the worker was then answered by nobody, because the actor is the
//! only task that writes. So `receive()` counts the requests it hands over and
//! `send()` counts the responses written; at EOF, `receive()` stays pending
//! until every handed-over request has its response (or `DRAIN_TIMEOUT`
//! passes), and only then reports the connection closed. While it waits, the
//! actor keeps selecting on its outbound queue, so the responses still go out.
//! The `-32601` replies this transport writes itself count too, and a read
//! error other than EOF drains the same way.
//!
//! SUNSET: workaround for pmcp 2.22.5's `run_transport_actor`, which `break`s
//! on any receive error without flushing queued responses. Remove the drain
//! when pmcp drains in-flight requests on transport close — re-check on every
//! pmcp bump; `tests/stdio_eof_drain.rs` is the tripwire (it must stay green
//! with the drain removed before the drain can go).

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use pmcp::async_trait;
use pmcp::error::TransportError;
use pmcp::shared::{StdioTransport, Transport, TransportMessage};
use pmcp::types::jsonrpc::{JSONRPCError, JSONRPCResponse, RequestId};
use pmcp::Result;
use tokio::io::{AsyncBufReadExt, BufReader, Lines, Stdin};
use tokio::sync::Mutex;
use tokio::time::Instant;

const METHOD_NOT_FOUND: i32 = -32601;

/// How long a closed input may wait for in-flight requests. Requests are
/// handled by ONE sequential worker, so this bounds all queued calls together;
/// bounded so a handler that never answers cannot keep the process alive
/// forever. `BRANA_MCP_DRAIN_TIMEOUT_MS` overrides it (tests; a slow host).
const DRAIN_TIMEOUT: Duration = Duration::from_secs(30);

fn drain_timeout() -> Duration {
    std::env::var("BRANA_MCP_DRAIN_TIMEOUT_MS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .map(Duration::from_millis)
        .unwrap_or(DRAIN_TIMEOUT)
}
const DRAIN_POLL: Duration = Duration::from_millis(10);

#[derive(Debug)]
pub struct LenientStdio {
    lines: Lines<BufReader<Stdin>>,
    writer: Arc<Mutex<StdioTransport>>,
    /// Requests handed to pmcp whose response has not been written yet.
    in_flight: Arc<AtomicUsize>,
    /// When end of input was first seen; kept across `receive()` calls because
    /// the actor drops and re-creates the future each time it sends a frame.
    eof_at: Option<Instant>,
}

impl LenientStdio {
    pub fn new() -> Self {
        Self {
            lines: BufReader::new(tokio::io::stdin()).lines(),
            writer: Arc::new(Mutex::new(StdioTransport::new())),
            in_flight: Arc::new(AtomicUsize::new(0)),
            eof_at: None,
        }
    }

    /// At end of input: wait until every handed-over request is answered or
    /// the drain deadline passes. Cancellation safe — all state lives in
    /// `self`, so a dropped future just resumes the wait on the next call.
    async fn drain_then_close(&mut self) -> Result<TransportMessage> {
        let since = *self.eof_at.get_or_insert_with(Instant::now);
        let limit = drain_timeout();
        while self.in_flight.load(Ordering::SeqCst) > 0 {
            if since.elapsed() >= limit {
                eprintln!(
                    "brana-mcp: input closed; {} request(s) still unanswered after {:?}, exiting",
                    self.in_flight.load(Ordering::SeqCst),
                    limit
                );
                break;
            }
            tokio::time::sleep(DRAIN_POLL).await;
        }
        Err(TransportError::ConnectionClosed.into())
    }

    /// What to do with a line pmcp refused to parse.
    fn classify(line: &str) -> Unparseable {
        let Ok(value) = serde_json::from_str::<serde_json::Value>(line) else {
            return Unparseable::Garbage;
        };
        let method = value
            .get("method")
            .and_then(|m| m.as_str())
            .map(str::to_owned);
        let id = value
            .get("id")
            .filter(|id| !id.is_null())
            .and_then(|id| serde_json::from_value::<RequestId>(id.clone()).ok());
        match (id, method) {
            (Some(id), Some(method)) => Unparseable::UnknownRequest { id, method },
            (None, Some(_)) => Unparseable::UnknownNotification,
            _ => Unparseable::Garbage,
        }
    }

    fn method_not_found(id: RequestId, method: &str) -> TransportMessage {
        TransportMessage::Response(JSONRPCResponse::error(
            id,
            JSONRPCError {
                code: METHOD_NOT_FOUND,
                message: format!("Method not found: {method}"),
                data: None,
            },
        ))
    }

    /// Write a frame from a task of its own, so a cancelled `receive()` can
    /// never leave half a frame on stdout.
    /// Counted in `in_flight` like any response, so EOF right after an
    /// unknown method still waits for its reply.
    fn reply_detached(&self, message: TransportMessage) {
        let writer = Arc::clone(&self.writer);
        let in_flight = Arc::clone(&self.in_flight);
        in_flight.fetch_add(1, Ordering::SeqCst);
        tokio::spawn(async move {
            if let Err(e) = writer.lock().await.send(message).await {
                eprintln!("brana-mcp: failed to write error reply: {e}");
            }
            let _ = in_flight.fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_sub(1));
        });
    }
}

impl Default for LenientStdio {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, PartialEq)]
enum Unparseable {
    UnknownRequest { id: RequestId, method: String },
    UnknownNotification,
    Garbage,
}

#[async_trait]
impl Transport for LenientStdio {
    async fn send(&mut self, message: TransportMessage) -> Result<()> {
        let answers_request = matches!(message, TransportMessage::Response(_));
        let sent = self.writer.lock().await.send(message).await;
        if answers_request {
            // Saturating: a response we did not count (a server-to-client
            // round-trip reply) must never wrap the counter.
            let _ = self
                .in_flight
                .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_sub(1));
        }
        sent
    }

    async fn receive(&mut self) -> Result<TransportMessage> {
        loop {
            // `next_line` is cancellation safe: a line is never lost when the
            // transport actor drops this future to send something.
            if self.eof_at.is_some() {
                return self.drain_then_close().await;
            }
            let line = match self.lines.next_line().await {
                Ok(Some(line)) => line,
                Ok(None) => return self.drain_then_close().await,
                Err(e) => {
                    // Unreadable input (e.g. invalid UTF-8) ends the session the
                    // same way EOF does — after the in-flight replies.
                    eprintln!("brana-mcp: stdin read error, closing after in-flight replies: {e}");
                    return self.drain_then_close().await;
                },
            };
            if line.trim().is_empty() {
                continue;
            }
            match StdioTransport::parse_message(line.as_bytes()) {
                Ok(message) => {
                    if matches!(message, TransportMessage::Request { .. }) {
                        self.in_flight.fetch_add(1, Ordering::SeqCst);
                    }
                    return Ok(message);
                },
                Err(_) => match Self::classify(&line) {
                    Unparseable::UnknownRequest { id, method } => {
                        self.reply_detached(Self::method_not_found(id, &method));
                    },
                    Unparseable::UnknownNotification | Unparseable::Garbage => {
                        eprintln!("brana-mcp: ignoring unparseable line: {}", line.trim());
                    },
                },
            }
        }
    }

    async fn close(&mut self) -> Result<()> {
        self.writer.lock().await.close().await
    }

    fn is_connected(&self) -> bool {
        // `try_lock` only fails while a frame is being written, and a writer
        // mid-frame is by definition still connected.
        self.writer
            .try_lock()
            .map(|w| w.is_connected())
            .unwrap_or(true)
    }

    fn transport_type(&self) -> &'static str {
        "stdio"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_request_is_classified_with_its_id() {
        let got = LenientStdio::classify(
            r#"{"jsonrpc":"2.0","id":0,"method":"server/discover","params":{}}"#,
        );
        assert_eq!(
            got,
            Unparseable::UnknownRequest {
                id: RequestId::Number(0),
                method: "server/discover".into()
            }
        );
    }

    #[test]
    fn unknown_notification_and_garbage_are_skipped() {
        assert_eq!(
            LenientStdio::classify(r#"{"jsonrpc":"2.0","method":"notifications/x"}"#),
            Unparseable::UnknownNotification
        );
        assert_eq!(LenientStdio::classify("not json"), Unparseable::Garbage);
        assert_eq!(
            LenientStdio::classify(r#"{"jsonrpc":"2.0","id":null,"method":"x"}"#),
            Unparseable::UnknownNotification
        );
    }

    #[test]
    fn method_not_found_serializes_as_jsonrpc_error() {
        let msg = LenientStdio::method_not_found(RequestId::Number(7), "foo/bar");
        let bytes = StdioTransport::serialize_message(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(v["id"], 7);
        assert_eq!(v["error"]["code"], METHOD_NOT_FOUND);
    }
}
