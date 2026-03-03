# Design Token System

## Table of Contents

- [Color Tokens](#color-tokens)
- [Typography](#typography)
- [Spacing & Radius](#spacing--radius)
- [Animation](#animation)
- [Responsive Breakpoints](#responsive-breakpoints)
- [Theme Customization](#theme-customization)

---

## Color Tokens

### Dark Mode (Default)

```css
--bg-base: #0b0e11          /* Page background */
--bg-phone: #0f1117         /* Mobile background */
--bg-card: #161a21          /* Card background */
--bg-card-hover: #1c2028    /* Card hover state */
--bg-elevated: #1e222b      /* Elevated surfaces */
--bg-sidebar: #0d1015       /* Sidebar background */
```

### Light Mode

```css
--bg-base: #f4f5f7
--bg-phone: #ffffff
--bg-card: #ffffff
--bg-card-hover: #f0f1f3
--bg-elevated: #e9ebee
--bg-sidebar: #ffffff
```

### Accent Colors

```css
--green: #2cd9a0            /* Primary accent */
--green-dark: #1a8a65       /* Gradient dark end */
--green-glow: rgba(44, 217, 160, 0.15)  /* Glow effect */
```

### Text Colors

```css
--text-1: #ffffff / #1a1d23     /* Primary text */
--text-2: #8b8f9a / #5f6775    /* Secondary text */
--text-3: #5a5e6a / #9ca3af    /* Tertiary/muted text */
```

### Semantic Colors

```css
--color-success: #22c55e
--color-danger: #ef4444
--color-warning: #f97316
--color-info: #3b82f6
```

### Borders & Shadows

```css
--border: rgba(255, 255, 255, 0.06) / rgba(0, 0, 0, 0.08)
--hover-bg: rgba(255, 255, 255, 0.03) / rgba(0, 0, 0, 0.03)
--shadow-card: rgba(0, 0, 0, 0.15) / rgba(0, 0, 0, 0.06)
--shadow-toast: rgba(0, 0, 0, 0.4) / rgba(0, 0, 0, 0.12)
--modal-overlay: rgba(0, 0, 0, 0.6) / rgba(0, 0, 0, 0.3)
```

---

## Typography

Font family: `'Inter', -apple-system, BlinkMacSystemFont, sans-serif`

| Usage | Size | Weight |
|-------|------|--------|
| Page title | 20px | 700 |
| Card title | 15px | 700 |
| Stat value | 24-28px | 800 |
| Body text | 14px | 500 |
| Label | 12px | 600 |
| Caption | 11px | 500-600 |
| Section label | 10px | 600 |

Helper classes: `.fw-600`, `.fw-700`, `.fw-800`, `.text-muted`, `.text-dim`, `.text-green`

---

## Spacing & Radius

### Border Radius

```css
--radius: 16px              /* Cards, main containers */
12px                        /* Buttons, inputs, sidebar items */
10px                        /* Stat card icons */
8px                         /* Small elements, pills */
6px                         /* Chart bars */
```

### Common Spacing

| Context | Value |
|---------|-------|
| Card padding | 20px |
| Sidebar padding | 24px |
| Panel padding (mobile) | 20px |
| Panel padding (tablet) | 24px 28px |
| Panel padding (desktop) | 28px 32px |
| Grid gap | 16px |
| Stat grid gap | 12px |
| Component internal gap | 8-16px |

### Safe Area

```css
--safe-top: env(safe-area-inset-top, 0px)
--safe-bottom: env(safe-area-inset-bottom, 0px)
```

---

## Animation

### Easing

```css
--ease: cubic-bezier(0.32, 0.72, 0, 1)   /* Spring-like easing */
```

### Duration Guide

| Element | Duration |
|---------|----------|
| Hover effects | 0.2s |
| Sidebar items | 0.25s |
| Panel transitions | 0.4s |
| Modal slide | 0.45s |
| Chart bars | 0.6s |
| Donut chart | 0.8s |

### Built-in Keyframes

- `nav-in` — Bottom nav indicator appear
- `fade-in` — Simple opacity fade
- `slide-up` — Opacity + translateY entrance

---

## Responsive Breakpoints

```
Mobile:  < 768px   → BottomNav + MobileHeader, single column
Tablet:  768-1199px → Collapsed sidebar (72px), TopBar, 2-column grid
Desktop: >= 1200px  → Full sidebar (260px), TopBar, 2-3 column grid
```

### Grid Behavior

| Grid | Mobile | Tablet | Desktop |
|------|--------|--------|---------|
| stat-grid | 1fr 1fr | 1fr 1fr | 1fr 1fr 1fr |
| grid | 1fr | 1fr 1fr | 1fr 1fr |

---

## Theme Customization

### Changing Accent Color

Replace `--green` variables in `:root` and `[data-theme="light"]`:

```css
:root {
  --green: #6366f1;            /* Indigo accent */
  --green-dark: #4338ca;
  --green-glow: rgba(99, 102, 241, 0.15);
}
```

Also update `.sidebar-item.active`, `.stat-change.up`, and other green references in light mode overrides.

### Adding a New Theme Variant

1. Add `[data-theme="your-theme"]` block in styles.css overriding CSS variables
2. Add the theme string to `ThemeContext.tsx` cycle order
3. Add icon mapping in navigation components
