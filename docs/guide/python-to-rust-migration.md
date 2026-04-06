# Python to Rust Migration — What Changed and Why

> A learning guide for Python developers transitioning to Rust.
> Based on the brana CLI migration: ~2,950 lines of Python → Rust.

## The Big Picture

Python and Rust solve the same problems with opposite philosophies:

| | Python | Rust |
|---|---|---|
| **When errors happen** | Runtime (you find out when it crashes) | Compile time (compiler rejects bad code) |
| **Who manages memory** | Garbage collector (automatic, invisible) | Ownership system (explicit, zero-cost) |
| **Data shape** | Dicts/lists (flexible, untyped) | Structs/enums (rigid, typed) |
| **Error handling** | Exceptions (throw/catch, can forget to handle) | Result<T,E> (must handle, compiler enforces) |
| **Concurrency** | GIL limits true parallelism | Fearless concurrency (compiler prevents data races) |
| **Dependencies** | pip/virtualenv (runtime, can break) | Cargo (compiled in, deterministic) |

**The core trade-off:** Python lets you move fast by deferring decisions to runtime. Rust forces decisions at compile time, which slows initial writing but eliminates entire categories of runtime bugs.

---

## Concept Map: Python → Rust

### 1. Data Structures

**Python:** Everything is a dict.

```python
task = {
    "id": "t-123",
    "status": "pending",
    "tags": ["cli", "rust"],
    "priority": "P0",
}
# No enforcement — you can put anything in here
task["nonexistent"]  # KeyError at runtime
task["priority"] = 42  # Wrong type, no error until something breaks
```

**Rust:** Structs with typed fields.

```rust
// Option 1: Typed struct (ideal for your own data)
struct Task {
    id: String,
    status: TaskStatus,
    tags: Vec<String>,
    priority: Option<Priority>,
}

enum TaskStatus { Pending, InProgress, Completed, Cancelled }
enum Priority { P0, P1, P2, P3 }

// Option 2: serde_json::Value (when shape is dynamic/external)
// This is what brana uses because tasks.json has many optional fields
use serde_json::Value;
let task: Value = serde_json::from_str(json_string)?;
task["id"].as_str()  // Returns Option<&str>, not panic
```

**What we did in brana:** Used `serde_json::Value` (Rust's equivalent of "dict of anything") because tasks.json has 20+ optional fields and the schema evolves frequently. For a stable schema, you'd use typed structs.

**Learning:** Rust doesn't force you to type everything upfront. `Value` gives you Python-like flexibility when needed. But typed structs catch bugs at compile time that Value can't.

---

### 2. Functions and Return Types

**Python:**

```python
def load_tasks(path):
    """Can return data, raise exception, or return None. Caller guesses."""
    content = open(path).read()  # FileNotFoundError?
    return json.loads(content)   # JSONDecodeError?
```

**Rust:**

```rust
/// Returns Ok(data) or Err(message). Caller MUST handle both.
pub fn load_tasks(path: &Path) -> Result<TasksFile, String> {
    let content = std::fs::read_to_string(path)
        .map_err(|e| format!("{}: {}", path.display(), e))?;  // ? = early return on error
    serde_json::from_str(&content)
        .map_err(|e| format!("invalid JSON: {e}"))
}
```

**Key differences:**
- **`Result<T, E>`** replaces exceptions. The function signature tells you exactly what can fail.
- **`?` operator** replaces try/except — propagates errors up the call stack.
- **No hidden exceptions.** If `load_tasks` can fail, the return type says so.

**What we did in brana:** The Python CLI used `process::exit(1)` for errors (abrupt termination). We refactored to `Result<(), anyhow::Error>` — errors propagate to `main()` which decides how to display them.

---

### 3. Error Handling Patterns

**Python:**

```python
# Pattern: try/except or let it crash
try:
    data = load_tasks(path)
except Exception as e:
    print(f"error: {e}")
    sys.exit(1)

# Or worse: silent failure
task = tasks.get("nonexistent")  # Returns None, bugs later
```

**Rust:**

```rust
// Pattern 1: ? operator (propagate up)
let data = load_tasks(&path)?;  // returns error to caller

// Pattern 2: .context() (add info to error)
let data = load_tasks(&path)
    .context("failed to load task database")?;

// Pattern 3: match (handle explicitly)
match load_tasks(&path) {
    Ok(data) => process(data),
    Err(e) => eprintln!("warning: {e}"),  // continue anyway
}
```

**brana's approach:**
- **brana-core** (library): Returns `Result<T, String>` — never panics, never exits.
- **brana-cli** (binary): Calls core, formats output, handles `Result` at `main()`.
- **brana-mcp** (server): Calls core, converts `Result` to MCP error responses.

This is the key architectural insight: **the library never decides how to display errors.** The application (CLI or MCP) decides.

---

### 4. Ownership and Borrowing

This is the biggest Rust concept with no Python equivalent.

**Python:** Everything is a reference. You never think about who "owns" data.

```python
tasks = load_tasks()
filtered = [t for t in tasks if t["status"] == "pending"]
# `tasks` and `filtered` point to the same dict objects
# Modify one, the other sees it. Usually fine. Sometimes a bug.
```

**Rust:** Every value has exactly one owner. Others can borrow temporarily.

```rust
let tasks = load_tasks(&path)?;  // `tasks` owns the data

// Borrowing: filter returns references, doesn't copy data
let filtered: Vec<&Value> = tasks.iter()
    .filter(|t| t["status"].as_str() == Some("pending"))
    .collect();

// `filtered` borrows from `tasks`. If `tasks` is dropped, `filtered` is invalid.
// The compiler prevents this.
```

**What tripped us up in brana:** The `backlog_set` tool had this error:

```rust
let tasks = val["tasks"].as_array_mut()?;  // mutable borrow of `val`
let task = tasks.iter_mut().find(/* ... */)?;
task["status"] = "completed".into();       // still borrowing `val` mutably
save_tasks(&tf, &val)?;                    // ERROR: can't borrow `val` immutably
```

**Fix:** Scope the mutable borrow:

```rust
{
    let tasks = val["tasks"].as_array_mut()?;
    let task = tasks.iter_mut().find(/* ... */)?;
    task["status"] = "completed".into();
}  // mutable borrow ends here
save_tasks(&tf, &val)?;  // now we can borrow immutably
```

**Learning:** The borrow checker prevents data races at compile time. It's frustrating at first but eliminates an entire class of bugs (concurrent modification, use-after-free, iterator invalidation).

---

### 5. Lifetimes

**Python:** No concept of lifetimes. GC handles it.

```python
def stale_tasks(tasks):
    return [t for t in tasks if is_stale(t)]
# Returned list references same objects as input. Always valid because GC.
```

**Rust:** When returning references, you must tell the compiler how long they live.

```rust
// 'a means: the returned Vec lives as long as the input `tasks`
pub fn stale_tasks<'a>(tasks: &'a [Value], all: &'a [Value], days: i64) -> Vec<&'a Value> {
    tasks.iter()
        .filter(|t| /* ... */)
        .collect()
}
```

**Why?** Without `'a`, Rust doesn't know if the returned `Vec<&Value>` references data from `tasks` or `all`. If `tasks` is dropped but the return value is still used, that's a use-after-free bug. Lifetimes prevent this at compile time.

**Shortcut:** Most of the time, Rust infers lifetimes automatically ("lifetime elision"). You only write them explicitly when the compiler asks.

---

### 6. Pattern Matching

**Python:**

```python
status = task.get("priority", "")
if status == "P0":
    weight = 400
elif status == "P1":
    weight = 300
else:
    weight = 50
```

**Rust:** `match` is exhaustive — the compiler forces you to handle every case.

```rust
let weight = match task["priority"].as_str() {
    Some("P0") => 400.0,
    Some("P1") => 300.0,
    Some("P2") => 200.0,
    Some("P3") => 100.0,
    _ => 50.0,  // covers None and unknown strings
};
```

**Why `Some()`?** `task["priority"].as_str()` returns `Option<&str>` — it might not exist. `match` on `Option` forces you to handle the missing case. No `KeyError` surprise at 3am.

---

### 7. Iterators vs List Comprehensions

**Python:**

```python
# List comprehension: builds full list in memory
pending = [t for t in tasks if t["status"] == "pending"]
ids = [t["id"] for t in pending]
```

**Rust:** Iterators are lazy — they don't allocate until you `.collect()`.

```rust
// Chained iterators: zero intermediate allocations
let ids: Vec<&str> = tasks.iter()
    .filter(|t| t["status"].as_str() == Some("pending"))
    .filter_map(|t| t["id"].as_str())
    .collect();  // only one allocation here
```

**Key difference:** Python comprehensions create a new list at each step. Rust iterators compose without allocating. The `.collect()` at the end does one allocation for the final result.

---

### 8. Project Structure

**Python:**

```
system/cli/
├── main.py          # entry point + health checks + version
├── backlog.py       # task commands (688 lines, mixed logic + UI)
├── ops.py           # scheduler commands (483 lines, mixed)
├── config.py        # shared paths and loaders
├── theme.py         # terminal formatting
└── __init__.py
```

Everything in one flat package. Logic and presentation mixed in every file. Testing requires mocking subprocess calls.

**Rust (after migration):**

```
system/cli/rust/crates/
├── brana-core/      # pure business logic — no CLI, no MCP
│   ├── tasks.rs     # 1,700 lines, all tested
│   ├── files.rs     # manifest tracking
│   └── util.rs      # path discovery
├── brana-cli/       # terminal presentation only
│   ├── main.rs      # clap dispatch → core → println
│   ├── theme.rs     # ANSI formatting
│   └── commands/    # thin handlers calling core
└── brana-mcp/       # MCP protocol adapter only
    ├── main.rs      # pmcp server → core → JSON-RPC
    └── tools/       # typed tool wrappers
```

**Key architectural difference:**
- Python: one module does everything (load data, process it, format output, handle errors).
- Rust: core does logic, CLI does presentation, MCP does protocol. Each is independently testable.

---

### 9. The Workspace Pattern

**Python:** One `pyproject.toml`, one virtualenv, all code sees all code.

**Rust workspace:** Multiple crates (libraries/binaries) in one repo, sharing dependencies.

```toml
# Root Cargo.toml
[workspace]
members = ["crates/brana-core", "crates/brana-cli", "crates/brana-mcp"]

[workspace.dependencies]  # shared versions
serde = { version = "1", features = ["derive"] }
chrono = "0.4"
```

```toml
# brana-cli/Cargo.toml
[dependencies]
brana-core = { path = "../brana-core" }  # local dependency
serde.workspace = true                    # inherits version from root
clap.workspace = true                     # CLI-only dep
```

**Why this matters:** `brana-core` can't accidentally depend on `clap` (CLI) or `pmcp` (MCP). The dependency graph is enforced by Cargo. In Python, any file can import any module — there's no enforcement of architectural boundaries.

---

### 10. Testing

**Python:**

```python
# Requires mocking, subprocess capture, stdout parsing
@mock.patch("subprocess.run")
def test_sync(mock_run):
    mock_run.return_value = Mock(stdout='{"ok":true}')
    result = sync_task("t-123")
    assert result == expected
```

**Rust:**

```rust
#[test]
fn test_burndown_shrinking() {
    let today = chrono::Local::now().date_naive().format("%Y-%m-%d").to_string();
    let tasks = vec![
        json!({"id": "t-1", "type": "task", "created": "2020-01-01", "completed": &today}),
        json!({"id": "t-2", "type": "task", "created": "2020-01-02", "completed": &today}),
    ];
    let result = burndown(&tasks, "week");
    assert_eq!(result["completed"], 2);
    assert_eq!(result["direction"], "shrinking");
}
```

**Key difference:** Because core functions are pure (data in, data out, no subprocess calls), testing requires no mocking. You construct input data, call the function, assert on the output. The 89 core tests run in 0.01 seconds.

---

## Migration Decisions We Made

| Decision | Why |
|----------|-----|
| Keep `serde_json::Value` instead of typed Task struct | Schema evolves frequently, 20+ optional fields — typed struct would require constant updates |
| `anyhow` for error handling | Application code (not library) — ergonomic error chaining over custom error types |
| Workspace with 3 crates | Enforces architecture: core can't depend on CLI or MCP |
| Re-export pattern (`pub use brana_core::tasks::*`) | Gradual migration — CLI code doesn't need to change import paths |
| MCP tools call core directly, not through CLI | Avoids the presentation layer — structured data, not formatted strings |
| Standalone binaries for infrequent tools | decisions, specgraph, reference don't share types with backlog — no reason to be in core |

---

## What Surprised Me (as a Python developer would say)

1. **The compiler is your pair programmer.** It catches bugs that Python unit tests wouldn't — use-after-free, data races, missing error handling. Frustrating at first, saves hours later.

2. **"Zero-cost abstractions" is real.** Iterators, generics, traits — they compile down to the same code you'd write by hand. No runtime overhead for using high-level patterns.

3. **Cargo is pip + virtualenv + make + CI combined.** One tool builds, tests, benchmarks, lints, and manages dependencies. No "works on my machine" problems.

4. **Lifetimes are scary but rare.** 95% of the time, elision handles it. The 5% where you write `'a` explicitly is when you're doing something the compiler needs help reasoning about.

5. **The borrow checker changes how you think about architecture.** You naturally separate "read this data" from "modify this data" because the compiler enforces it. This leads to cleaner APIs.
