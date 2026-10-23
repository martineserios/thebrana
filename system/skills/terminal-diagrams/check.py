#!/usr/bin/env python3
"""Alignment checker for terminal diagrams (stdlib only, Python 3.9+).

Usage:
  check.py FILE.md        check fenced blocks with no language, text, txt, ascii or diagram
                          (add `nocheck` to the fence info string to skip a block)
  check.py --raw FILE     treat the whole file as one diagram
  check.py -              read one diagram from stdin
  --width N               max columns per line (default 100)

Exit 0 when clean, 1 when issues are found (printed as path:line:col: message), 2 on usage error.

Checks:
  glyphs  - every character must render one cell wide: no emoji, CJK, tabs, variation
            selectors, zero-width joiners, combining marks, diagonals or block art
  width   - no line longer than --width columns
  boxes   - every ┌...┐ top border has straight left and right edges down to └...┘
  joints  - every corner/junction arm meets a matching arm, an arrow on the same axis,
            or (upward only) a text label it hangs from
"""
import sys
import unicodedata

# Arms per box-drawing character: u(p) d(own) l(eft) r(ight).
ARMS = {
    "─": "lr", "│": "ud", "┄": "lr", "┆": "ud", "═": "lr", "║": "ud",
    "┌": "dr", "┐": "dl", "└": "ur", "┘": "ul",
    "╭": "dr", "╮": "dl", "╰": "ur", "╯": "ul",
    "╔": "dr", "╗": "dl", "╚": "ur", "╝": "ul",
    "├": "udr", "┤": "udl", "┬": "dlr", "┴": "ulr", "┼": "udlr",
    "╠": "udr", "╣": "udl", "╦": "dlr", "╩": "ulr", "╬": "udlr",
}
LINES = set("─│┄┆═║")  # plain runs may end anywhere; only corners and junctions are checked
V_ARROWS = set("▼▲↓↑")
H_ARROWS = set("►◄→←<>")
OPPOSITE = {"u": "d", "d": "u", "l": "r", "r": "l"}
STEP = {"u": (-1, 0), "d": (1, 0), "l": (0, -1), "r": (0, 1)}

TOP_LEFT, TOP_RIGHT = set("┌╭╔"), set("┐╮╗")
BOTTOM_LEFT, BOTTOM_RIGHT = set("└╰╚"), set("┘╯╝")
TOP_BORDER = set("─┄═┬┴┼╦╩╬▼▲")
LEFT_EDGE = set("│┆║├┤┼╠╣╬")
RIGHT_EDGE = LEFT_EDGE

TEXT_FENCES = {"", "text", "txt", "plain", "ascii", "diagram"}


def glyph_problem(ch):
    cp = ord(ch)
    if ch == "\t":
        return "tab character (use spaces)"
    if cp < 0x20 or 0x7F <= cp < 0xA0:
        return "control character U+%04X" % cp
    if 0xFE00 <= cp <= 0xFE0F or 0x200B <= cp <= 0x200F or cp == 0x2060:
        return "zero-width/variation character U+%04X (breaks cell width)" % cp
    if unicodedata.combining(ch):
        return "combining mark U+%04X (zero width)" % cp
    if unicodedata.east_asian_width(ch) in ("W", "F"):
        return "wide glyph %r U+%04X renders 2 cells" % (ch, cp)
    if cp >= 0x1F000:
        return "emoji/pictograph U+%04X (width varies by terminal)" % cp
    if 0x2571 <= cp <= 0x2573 or 0x254C <= cp <= 0x254F or 0x2574 <= cp <= 0x257F:
        return "box-drawing U+%04X has unreliable width/font coverage" % cp
    if 0x2580 <= cp <= 0x259F:
        return "block element U+%04X has unreliable width" % cp
    return None


def at(grid, r, c):
    if 0 <= r < len(grid) and 0 <= c < len(grid[r]):
        return grid[r][c]
    return " "


def check_joints(grid):
    issues = []
    for r, row in enumerate(grid):
        for c, ch in enumerate(row):
            if ch not in ARMS or ch in LINES:
                continue
            for arm in ARMS[ch]:
                dr, dc = STEP[arm]
                nb = at(grid, r + dr, c + dc)
                if nb in ARMS:
                    ok = OPPOSITE[arm] in ARMS[nb]
                elif arm in "ud":
                    ok = nb in V_ARROWS or (arm == "u" and nb != " " and nb not in H_ARROWS)
                else:
                    ok = nb in H_ARROWS
                if not ok:
                    side = {"u": "above", "d": "below", "l": "left of", "r": "right of"}[arm]
                    issues.append((r, c, "%s has a dangling arm: %r %s it does not connect" % (ch, nb, side)))
    return issues


def lands_on_child(ch):
    """A bracket leg ending on a child's top-border junction (┴ ┼ ...), not on an edge."""
    return ch in ARMS and "u" in ARMS[ch] and ch not in LEFT_EDGE and ch not in BOTTOM_LEFT and ch not in BOTTOM_RIGHT


def check_boxes(grid):
    issues = []
    for r, row in enumerate(grid):
        for c, ch in enumerate(row):
            if ch not in TOP_LEFT:
                continue
            j = c + 1
            while j < len(row) and row[j] in TOP_BORDER:
                j += 1
            if j >= len(row) or row[j] not in TOP_RIGHT:
                continue  # not a box top; joint check covers the corner
            for k in range(r + 1, len(grid) + 1):
                if k == len(grid):
                    issues.append((r, c, "box opened here is never closed (no └...┘ below)"))
                    break
                left, right = at(grid, k, c), at(grid, k, j)
                if left in BOTTOM_LEFT and right in BOTTOM_RIGHT:
                    break
                if left in V_ARROWS or right in V_ARROWS or lands_on_child(left) or lands_on_child(right):
                    break  # a fork bracket (┌──┴──┐ over ▼ ▼ or child boxes), not a box; joints check the legs
                if left not in LEFT_EDGE and left not in BOTTOM_LEFT:
                    issues.append((k, c, "left edge of the box opened %d line(s) above is broken: found %r" % (k - r, left)))
                    break
                if right not in RIGHT_EDGE:
                    issues.append((k, j, "right edge of the box opened %d line(s) above is broken: found %r (edge belongs at col %d)"
                                   % (k - r, right, j + 1)))
                    break
    return issues


def check_diagram(lines, width):
    issues = []
    for r, line in enumerate(lines):
        for c, ch in enumerate(line):
            problem = glyph_problem(ch)
            if problem:
                issues.append((r, c, problem))
        if len(line.rstrip()) > width:
            issues.append((r, width, "line is %d columns (max %d)" % (len(line.rstrip()), width)))
    issues += check_boxes(lines)
    issues += check_joints(lines)
    return sorted(set(issues))


def fenced_blocks(text):
    """Yield (first_line_index, lines) for checkable fenced blocks in markdown."""
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        stripped = lines[i].lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            fence = stripped[:3]
            info = stripped[3:].strip().lower()
            words = info.split()
            start = i + 1
            j = start
            while j < len(lines) and not lines[j].lstrip().startswith(fence):
                j += 1
            lang = words[0] if words else ""
            if lang in TEXT_FENCES and "nocheck" not in words:
                yield start, lines[start:j]
            i = j + 1
        else:
            i += 1


def main(argv):
    width = 100
    raw = False
    paths = []
    args = iter(argv)
    for a in args:
        if a == "--width":
            try:
                width = int(next(args))
            except (StopIteration, ValueError):
                print("--width needs an integer", file=sys.stderr)
                return 2
        elif a == "--raw":
            raw = True
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            paths.append(a)
    if len(paths) != 1:
        print(__doc__, file=sys.stderr)
        return 2

    path = paths[0]
    if path == "-":
        text, name, raw = sys.stdin.read(), "<stdin>", True
    else:
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
        except OSError as e:
            print("cannot read %s: %s" % (path, e), file=sys.stderr)
            return 2
        name = path

    blocks = [(0, text.rstrip("\n").split("\n"))] if raw else list(fenced_blocks(text))
    found = 0
    for offset, lines in blocks:
        for r, c, msg in check_diagram(lines, width):
            print("%s:%d:%d: %s" % (name, offset + r + 1, c + 1, msg))
            found += 1
    if found:
        print("%d issue(s) in %d block(s) checked" % (found, len(blocks)), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
