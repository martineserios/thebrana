# Filter for `brana recall --json` text injected into session context (t-3540). Slugs, keys and
# snippets come from note files (untrusted): collapse whitespace, then drop control and format
# characters (escapes, bidi, zero-width, tag block). A missing file fails closed (no lines).
def clean: gsub("\\s+"; " ") | gsub("[\\p{Cc}\\p{Cf}  ]"; "");
.[] | (.doc.MemoryFile.slug // .doc.KnowledgeEntry.key // "?") as $k |
"- \($k | clean): \(.snippet | clean | .[0:120])"
