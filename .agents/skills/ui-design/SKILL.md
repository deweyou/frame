---
name: ui-design
description: >
  Use this skill whenever Dewey asks to design, implement, refine, or review a
  UI in his personal style across web, component libraries, H5/mobile screens,
  iOS/Android apps, HarmonyOS apps, WeChat/Alipay mini programs, macOS apps,
  dashboards, tools, landing pages, or Sleek prompts. This is a standalone
  skill: all required Dewey design rules and token snapshots are bundled inside
  the skill, so do not depend on any external repository files to apply it.
  Trigger strongly for personal-style or interface requests, including Chinese
  phrases such as "我的风格", "Dewey 的设计风格", "专属于我风格", "帮我设计",
  "优化 UI", "审一下界面", "做个移动端/H5", "鸿蒙", "HarmonyOS", "小程序",
  "微信小程序", "支付宝小程序", "mac app", "生成 Sleek prompt", "组件库风格",
  or English phrases such as "Dewey interface". It should guide
  platform-neutral visual taste plus platform-specific implementation quality:
  restrained Chinese-first copy, sans controls with serif content, neutral
  surfaces, emerald emphasis, border-first layout, native/headless behavior
  primitives, web/mobile/desktop/mini-program checks, touch/pointer/keyboard
  interaction, motion, and verification. For web work, prefer the current Dewey
  component library when available; for mobile, HarmonyOS, mini programs, or
  macOS, adapt the style through native platform patterns instead of forcing web
  components.
---

# Dewey Interface Design

This skill defines Dewey's current interface taste as an executable design workflow. It is not a generic style pack and it is not based on any older personal-brand skill. It is a standalone condensation of Dewey's current component-library taste, generalized for web, mobile, HarmonyOS, mini program, desktop, and prototype work.

Use it when the task changes how an interface looks, feels, moves, reads, or is interacted with in Dewey's personal interface style, in Dewey's component library, or in a UI that the user explicitly wants reviewed against that style. Do not use it for every generic UI request.

Do not trigger this skill when the user asks for a clearly different visual direction, such as a highly colorful campaign page, game-like UI, expressive illustration-heavy brand site, or another named design system, unless the user also asks to reconcile that direction with Dewey's style.

## Bundled Sources

This skill must work outside any single repository. Do not require the model to read external repo docs before applying the style.

Use the bundled references instead:

- `references/component-library-snapshot.md` — copied design-system facts, component model, behavior-layer rules, and anti-patterns.
- `references/design-tokens.css` — portable CSS custom-property snapshot for prototypes and style examples.

If the user is actively working in a repository that has newer local rules, follow the user's repo for that task. Otherwise, this skill's bundled references are the source of truth.

## Design Thesis

Dewey's interface style is restrained, typographic, component-driven, and functional. It should feel like a small, carefully made product system rather than a generic SaaS template. The style is platform-neutral; the implementation should remain platform-native.

Core judgment phrase:

> Simple, clean, and with clean lines. Less is more.

Translate that into these decisions:

- Use structure before decoration: type, spacing, borders, hierarchy, and state clarity come first.
- Keep color semantic: neutral for structure, emerald for primary emphasis, red for danger. Warning is feedback-only.
- Let typography carry personality: Source Han Sans for controls and dense UI; Source Han Serif for content, Markdown, prose, and display hierarchy.
- Prefer neutral canvases and white surfaces. Avoid cream/beige themes, pure-white page wash, gradient atmospheres, glassmorphism, bokeh, and stock-like imagery.
- Build with accessible primitives. Complex interaction should come from Ark UI, native platform primitives, or another established headless behavior layer, not hand-rolled focus and keyboard logic.
- Preserve calm density. Tools and dashboards should be compact and scannable; marketing surfaces can breathe more, but should not become decorative.
- Respect platform idioms. Web, iOS/Android, HarmonyOS, mini programs, macOS, and H5 can share the same taste, but should not share identical navigation, density, controls, capability constraints, or gesture assumptions.

## Operating Workflow

When starting a UI task, do this in order:

1. Classify the platform and surface: web component, website page, dashboard/tool, H5/mobile web, iOS/Android app, HarmonyOS app, mini program, macOS app, landing page, Sleek prompt, or review.
2. Identify the user's real workflow: what must be scanned, compared, edited, selected, confirmed, or recovered from.
3. Choose the information hierarchy before choosing decoration.
4. Map visual decisions to bundled tokens, host-project tokens, and platform-appropriate components.
5. Add interaction states: hover, press, focus, loading, disabled, selected, error, empty.
6. Check accessibility and responsive behavior before calling the design finished.
7. If implementing, verify in the browser or relevant renderer whenever possible.

For ambiguous design requests, make a conservative assumption and proceed. Ask only when the target product, platform, or output artifact is genuinely unclear.

## Visual System

### Typography

Use the current split:

- Controls and dense UI: `--ui-font-sans`, `--ui-font-body`, `--ui-font-control`.
- Content and display: `--ui-font-content`, `--ui-font-display`.
- Code, package names, technical identifiers: `--ui-font-mono`.

Rules:

- Do not use serif everywhere. The current component library intentionally uses sans for controls.
- Use `Text` or existing typography primitives for semantic content where available.
- Keep display type for real display moments. Compact panels, cards, sidebars, and controls need smaller, tighter headings.
- Use weights 400, 500, 600, 700 only.
- Body line-height should be readable; display line-height can be tight.
- Avoid negative letter spacing. Eyebrows may use modest uppercase tracking only at small sizes.

### Color

Use semantic tokens instead of raw colors:

- `neutral` / stone: text, borders, surfaces, neutral actions.
- `primary` / emerald: selected states, focus, primary actions, brand emphasis.
- `danger` / red: destructive actions and errors.
- `warning` / amber: temporary feedback such as toast warnings, not a general component color.

Rules:

- Components should consume `--ui-*` semantic tokens. Use `references/design-tokens.css` for standalone prototypes.
- Raw hex/hsl/rgba values belong in token definitions, not component styles.
- Use `color-mix()` for subtle hover/active/selection tints when existing tokens do not cover the state.
- Do not introduce a fourth regular semantic color to make a screen more exciting.
- The logo or brand mark may have a gradient; product surfaces should not use decorative gradients.

### Surface, Layout, And Density

- Canvas: neutral light-gray in light mode; low-glare stone dark mode.
- Surfaces: white or raised token surfaces, separated by borders first.
- Cards: 1px border, surface background, no shadow by default.
- Floating layers: dialogs, popovers, menus, toasts can use shadow and raised surfaces.
- Spacing: use the 4px rhythm and established `xs/sm/md/lg/xl` spacing.
- Radius: use existing tiers only: `rect`, `float`, `auto`, `pill`.
- Avoid nested cards. Use full-width bands, sections, or clear layout groupings instead.
- Reserve stable dimensions for controls, toolbars, grids, tabs, tiles, and counters so dynamic content does not shift layout.

## Platform Adaptation

The visual language stays consistent across platforms, but the interaction model should come from the platform.

### Web

- Prefer the current Dewey component library when it is available in the host project.
- Use `@deweyou-design/react` components before making custom local UI.
- Use `references/design-tokens.css` for standalone HTML prototypes or non-Dewey web projects.
- Use Ark UI or another headless primitive for complex browser interactions.
- Verify keyboard navigation, focus order, hover/focus/active states, reduced motion, responsive breakpoints, and no horizontal overflow.

### H5 / Mobile Web

- Keep the Dewey typography/color/surface rules, but design for thumb reach and browser chrome.
- Use safe-area insets for fixed headers, bottom bars, sheets, and CTAs.
- Avoid dense desktop tables; convert to grouped rows, filters, or detail drill-downs.
- Do not rely on hover. Every primary interaction must work by tap.

### iOS / Android

- Use native platform primitives or the app's design-system components rather than web component assumptions.
- Preserve platform navigation expectations: tab bars for top-level mobile destinations, predictable back behavior, sheets for transient tasks, and clear modal escape routes.
- Translate tokens into native theme values: surface, text, border, primary, danger, radius, shadow/elevation, and motion.
- Respect Dynamic Type / font scaling, safe areas, accessibility labels, touch targets, and system gestures.
- Use haptics sparingly for confirmations or important state transitions.

### HarmonyOS

- Treat HarmonyOS as a native mobile platform, not as H5 with a different shell.
- Use ArkTS/ArkUI or the host app's Harmony components when implementing.
- Translate Dewey tokens into Harmony theme values: surfaces, text, brand/danger colors, radius, divider, shadow/elevation, and motion.
- Respect Harmony navigation patterns, window/status areas, back behavior, gestures, font scaling, and accessibility labels.
- Keep layouts adaptive across phones, foldables, tablets, and multi-window modes where relevant.
- Avoid copying iOS-only or Material-only visual conventions if Harmony native components provide a clearer expected pattern.

### Mini Programs

- Apply this branch for WeChat Mini Programs, Alipay Mini Programs, and similar super-app platforms.
- Respect platform constraints: page stack navigation, capsule/menu button safe area, limited viewport, subpackage/load performance, and platform component availability.
- Use native mini-program components where they improve reliability and accessibility; style them with Dewey tokens instead of rebuilding everything from custom views.
- Keep interactions tap-first, lightweight, and resilient to slow network startup.
- Avoid heavy web effects, large custom font payloads, and desktop-style layouts.
- Design explicit empty, loading, permission-denied, login-required, and network-error states, because mini programs often start in constrained session contexts.

### macOS / Desktop Apps

- Favor quiet density, clear sidebars/toolbars, keyboard access, and precise alignment.
- Use native macOS controls where they improve familiarity; apply Dewey tokens through color, typography, spacing, and icon style rather than replacing platform behavior.
- Support pointer hover, focus rings, keyboard shortcuts, menu commands, resizable windows, and empty/error states.
- Avoid mobile-first spacing inflation. Desktop surfaces can be compact, but must remain readable and accessible.

### Iconography

- Use the host project's icon system when available.
- Prefer Tabler-style stroked SVG icons, 1.5 stroke, square linecap, miter linejoin.
- Use icons for tools and compact actions where recognizable.
- Icon-only controls need accessible names.
- Do not use emoji as structural UI icons.
- Keep icon family, stroke, size, and alignment consistent.

### Copy

Chinese user-facing copy is usually primary. Keep it factual and compact:

- Use clear nouns and action verbs.
- Avoid hype, slogans, inflated promises, and exclamation marks.
- Use `·` as the house separator for metadata, eyebrows, and parallel labels.
- Do not manually add spaces between Chinese and English in Chinese product copy.
- Button labels should be commands: `保存`, `复制`, `删除`, `打开菜单`.

## Interaction Rules

Borrow the discipline of strong UI/UX guidelines, but express it through Dewey's restrained style.

- Touch targets: at least `--ui-touch-target-min`; mobile targets should be at least 44px.
- Focus: visible `:focus-visible`, no focus removal. Prefer tokenized box-shadow rings.
- Hover: never the only affordance.
- Press: provide quick feedback without moving surrounding layout.
- Loading: disable repeat actions, preserve layout width, show spinner or skeleton when useful.
- Disabled: semantic disabled state plus reduced emphasis; disabled controls must not look tappable.
- Errors: show the cause and recovery path near the field or affected area.
- Empty states: explain what is missing and provide the next useful action.
- Destructive actions: visually separate and confirm when risk is meaningful.
- Motion: 140-300ms, cause-and-effect, transform/opacity only where possible, respect reduced motion.

## Responsive And Mobile/H5 Rules

Use mobile rules when designing H5, responsive web, or Sleek/mobile concepts:

- Start from a 375px small-phone viewport and scale up.
- Respect safe areas for fixed headers, tab bars, bottom CTAs, sheets, and overlays.
- Avoid horizontal scroll. Long text wraps before it truncates.
- Bottom navigation should stay at five items or fewer and include labels.
- Primary actions should remain reachable without colliding with OS gestures.
- Preserve back behavior and scroll state where relevant.
- Use visible alternatives for critical gestures; do not rely on swipe-only actions.
- Test dark mode, large text, landscape, and reduced motion when the UI is user-facing.

## Production Implementation

For Web / React component-library work:

- Follow the host repository's file conventions. If no convention exists, prefer TSX components, CSS Modules or scoped CSS, lowercase kebab-case source units, colocated tests, and clear package exports.
- Use Ark UI for non-trivial interactions: Dialog, Popover, Select/Combobox, Menu, Tabs, Toast, Switch, Checkbox, Accordion, Tooltip.
- Keep Ark UI data attributes (`data-state`, `data-disabled`, `data-highlighted`) as styling hooks.
- Do not duplicate behavior logic that the primitive already owns.
- Use existing public component dimensions: `variant`, `color`, `size`, and `shape` should stay orthogonal.
- Add or update colocated tests, stories, and docs according to the host repository's delivery rules.

For Web app/page work:

- Prefer existing `@deweyou-design/react` components before making custom local UI.
- Use root imports when a file consumes several components; use subpath imports for focused examples and docs.
- Keep route navigation and tab semantics distinct. Use `Nav` for navigation landmarks and `Tabs` for tabbed content or controlled tab bars.

## Sleek Or AI Design Prompting

When using Sleek or another design generator, do not paste a generic "make it beautiful" prompt. Give a compact style brief:

```text
Design in Dewey's current interface style: restrained Chinese-first product UI, Source Han Sans controls, Source Han Serif content/display, neutral light-gray canvas, white bordered surfaces, deep emerald primary emphasis, red only for danger, no emoji, no decorative gradients, no glassmorphism, no generic stock atmosphere. Prioritize clear workflow, compact hierarchy, accessible touch targets, safe areas, visible states, and calm motion.
```

Then add the user's specific product requirements. After generation, review screenshots against this skill and ask for revisions that remove generic mobile-app decoration, excessive color, unreadable density, or missing states.

## Review Checklist

When reviewing UI, lead with concrete issues. Prioritize:

1. Accessibility: contrast, focus, labels, keyboard, touch target size, reduced motion.
2. Interaction correctness: disabled/loading/error/empty states, destructive flows, state preservation.
3. Token drift: raw colors, arbitrary radius/shadows, fourth semantic colors, off-system typography.
4. Layout: horizontal overflow, unsafe fixed bars, nested cards, unstable dimensions, text overflow.
5. Visual taste: generic gradients, decorative blur, one-note palette, stock imagery, oversized hero treatment in tool UIs.
6. Component architecture: hand-rolled behavior where Ark UI or existing primitives should own it.

Output review findings with file/line references when files are available. If there are no material issues, say so and mention any remaining verification gaps.

## Output Patterns

For design plans:

- State the surface and intended workflow.
- Give the hierarchy, component map, and token decisions.
- Name interaction states and responsive checks.
- Keep recommendations concise enough to implement.

For implementation:

- Edit the relevant files directly.
- Start a local dev server when the app needs one.
- Use browser verification for significant visual changes.

For prototypes:

- Build the actual usable first screen, not a marketing placeholder.
- Use local HTML/CSS or the target stack.
- Keep the result token-aligned and inspectable.

For mobile / HarmonyOS / mini program concepts:

- Specify screen structure, navigation model, safe-area behavior, touch targets, and state model.
- Avoid purely decorative UI trends unless the product genuinely needs them.
