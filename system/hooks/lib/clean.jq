# Shared by session-start.sh (t-3540, t-3547): note text is untrusted. Collapse whitespace, then drop
# control and format characters (escapes, bidi, zero-width, tag block). Use: include "clean"; with jq -L lib.
def clean: gsub("\\s+"; " ") | gsub("[\\p{Cc}\\p{Cf}  ]"; "");
