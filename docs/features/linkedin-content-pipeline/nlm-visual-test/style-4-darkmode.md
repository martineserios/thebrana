# Visual Style Guide: Dark Mode / Terminal

## Identity

Developer-native. Looks like it belongs in a code editor, a terminal, or a monitoring dashboard. Appeals strongly to the technical secondary audience while signaling "this person lives in the tooling." Dark interfaces feel premium and modern.

## Visual Characteristics

- **Line quality:** Clean, precise. Slightly glowing effect on connection lines — like data flowing through a circuit.
- **Shapes:** Rounded rectangles with subtle borders. Components feel like UI cards or terminal windows. Slight glow or border highlight on active components.
- **Arrows:** Animated feel — dashed lines suggesting flow direction. Small dots or chevrons along the path suggesting data movement.
- **Text:** Monospace font (JetBrains Mono, Fira Code feel). Component names in bright text on dark background. Labels are concise, almost like code comments.
- **Colors:** Dark background (#1a1a2e or #0d1117 — GitHub dark). Bright accent colors for components: cyan (#00d4ff), green (#00ff87), amber (#ffb800), coral (#ff6b6b). Each component type gets a consistent color.
- **Background:** Dark solid or very subtle grid (like a terminal or graph paper on dark mode). No noise.
- **Layout:** Structured. Horizontal or vertical flow. Components aligned on a grid. Feels systematic.

## How to Show Before/After

- **Before:** Components in dim/muted colors. Broken connections shown as red dashed lines. The silent bottleneck pulses red or has a warning icon. Error state aesthetic.
- **After:** Same components now bright, fully colored. Connections are solid cyan or green lines with flow indicators. New components (memory layer, correction loop) glow with accent color. Health state aesthetic.
- Two panels: top "BEFORE" in red/muted tones, bottom "AFTER" in green/bright tones. Status bar aesthetic.

## Component Visual Language

- **The human gate:** A component with a lock or pause icon. Border color: amber (caution/review needed). Stands out from automated components.
- **The silent bottleneck:** A broken connection in red. Flashing or warning aesthetic. Label: `// 40% PATIENT LOSS — UNMONITORED`
- **The memory layer:** A component styled like a database card. Color: cyan. Small icon suggesting data persistence.
- **The correction loop:** A bright green feedback arrow. Feels like a health check loop. Label: `FEEDBACK_LOOP`
- **The bridge:** A component with two-tone coloring — one side analog (warm), one side digital (cool). Transition element.

## Mood

Technical credibility. "This person builds real systems." Feels like looking at a system architecture diagram in a production monitoring tool. The secondary audience (CTOs, engineers) immediately feels at home.

## LinkedIn Dimensions

- Carousel slide: 1080 x 1350 px (4:5 ratio, portrait)
- Bright text on dark background — test readability on mobile (dark mode can be hard to read at small sizes)
- Title at top in bright text, diagram in center, "Todo es un sistema." at bottom in muted/accent color
