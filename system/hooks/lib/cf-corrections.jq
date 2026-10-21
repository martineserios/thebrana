# correction-keyed ruflo hits (t-3547).
include "clean";
.results[]? | select(.key | test("correction"; "i")) | ((.key | clean) + ": " + (.preview | clean))
