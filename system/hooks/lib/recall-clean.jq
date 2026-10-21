# `brana recall --json` lines injected into session context (t-3540). A missing file fails closed (no lines).
include "clean";
.[] | (.doc.MemoryFile.slug // .doc.KnowledgeEntry.key // "?") as $k |
"- \($k | clean): \(.snippet | clean | .[0:120])"
