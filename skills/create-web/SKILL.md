---
name: dark-dashboard-kit
description: React + TypeScript dark-theme dashboard UI kit with complete component library, responsive layout system, and project scaffolding. Use when building dashboard apps, admin panels, SaaS interfaces, or any React project needing a premium dark/light theme UI with responsive layout (mobile/tablet/desktop), authentication, charts, forms, modals, toasts, and navigation. Triggers on requests like "create a dashboard app", "build an admin panel", "new React project with dark theme", or "scaffold a dashboard UI".
---

# Dark Dashboard Kit

Premium React + TypeScript + Vite dashboard UI kit. Dark/light theme, responsive 3-breakpoint layout, 20+ production-ready components.

## Quick Start

Initialize a new project:

```bash
bash scripts/init_project.sh my-app .
cd my-app && npm run dev
```

Default login: `admin` / `123456`

## Project Scaffolding

Run `scripts/init_project.sh <name> [dir]` to create a ready-to-run project. The script:

1. Copies `assets/template/` to target directory
2. Replaces `__APP_NAME__` / `__APP_TITLE__` placeholders
3. Auto-detects and runs `bun` / `pnpm` / `npm install`

## Architecture

```
ThemeProvider → AppProvider → AppInner
  ├── Login (if !authenticated)
  └── AppShell (if authenticated)
      ├── Sidebar (desktop)
      ├── TopBar (tablet/desktop)
      ├── MobileHeader (mobile)
      ├── PageContainer [panels]
      └── BottomNav (mobile)
```

- **State**: `useReducer` in AppContext — navigation, toast, modal, auth
- **Theme**: `ThemeContext` with light/dark/system + localStorage persistence
- **Routing**: Panel-based (all pages in DOM, CSS transitions)
- **Auth**: localStorage persistence, guard in AppInner

## Component Overview

| Category | Components |
|----------|-----------|
| **UI** | Icon (24 icons), Button (5 variants), Card, Modal, Toast, Avatar, TabSwitcher, SearchBox, StatPill, ProgressBar, EmptyState |
| **Form** | FormInput, FormSelect, AmountInput, DatePicker, ToggleSwitch |
| **Data** | StatCard, BarChart (animated), DonutChart (SVG) |
| **Layout** | AppShell, Sidebar, TopBar, MobileHeader, BottomNav, PageContainer |

## Adding a New Page

1. Extend `PageId` in `src/types/index.ts`
2. Create `src/components/pages/YourPage.tsx`
3. Register in `AppShell.tsx` pages array
4. Add nav entries in Sidebar, BottomNav, TopBar, MobileHeader

## Extending State

Add new action types and cases to the reducer in `AppContext.tsx`. Create custom hooks (e.g., `useItems()`) for domain-specific state access.

## Customizing Theme

Override CSS variables in `:root` and `[data-theme="light"]` in `styles.css`. Primary accent is `--green` family.

## References

- **Component API**: See [references/components.md](references/components.md) for full props and usage examples
- **Design Tokens**: See [references/design-tokens.md](references/design-tokens.md) for colors, typography, spacing, animation, and responsive breakpoints
- **Layout Patterns**: See [references/layout-patterns.md](references/layout-patterns.md) for architecture, page creation, state management, and common layout patterns

## Design Standards

- CSS variables for all colors — no hardcoded values in components
- 3 responsive breakpoints: mobile (<768), tablet (768-1199), desktop (>=1200)
- Smooth transitions on all interactive elements (0.2-0.4s)
- `prefers-reduced-motion` support
- Safe area insets for notched devices
- Scrollbar customization (thin, themed)
- All icons use `stroke="currentColor"` for automatic theme adaptation
