# ruflo pattern-namespace hits as context lines (t-3547). Output shape: {results: [{key, score, preview}]}.
include "clean";
.results[]? | "- \(.key | clean) (score \(.score * 100 | floor / 100)): \(.preview | clean)"
