bie# Component API Reference

## Table of Contents

- [UI Components](#ui-components)
- [Form Components](#form-components)
- [Data Display Components](#data-display-components)
- [Layout Components](#layout-components)

---

## UI Components

### Icon

SVG icon system. All icons use `stroke="currentColor"` for theme-aware coloring.

```tsx
import Icon from './components/ui/Icon';

<Icon name="home" size={20} className="my-icon" />
```

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| name | string | required | Icon name from built-in set |
| size | number | 20 | Width and height in px |
| className | string | - | Additional CSS class |

**Built-in icons:** home, plus, search, bell, close, check, dollar, trendUp, trendDown, settings, logout, user, lock, sun, moon, monitor, filter, calendar, info, arrowRight, list, grid, chart, wallet

**Adding custom icons:** Add SVG path markup to the `paths` record in Icon.tsx:
```tsx
const paths: Record<string, string> = {
  // ... existing icons
  myIcon: '<path d="M..."/>',
};
```

### Button

```tsx
<Button variant="primary" onClick={fn}>Label</Button>
<Button variant="secondary">Label</Button>
<Button variant="danger">Label</Button>
<Button variant="ghost">Label</Button>
<Button disabled>Label</Button>
```

| Prop | Type | Default |
|------|------|---------|
| variant | 'primary' \| 'secondary' \| 'danger' \| 'ghost' \| 'icon' | 'primary' |
| disabled | boolean | false |
| type | 'button' \| 'submit' | 'button' |

### Card

Container with optional header (title + link).

```tsx
<Card title="Section Title" linkText="View All" onLinkClick={fn}>
  {children}
</Card>
```

### Modal

Bottom sheet (mobile) / centered dialog (desktop). Uses React Portal.

```tsx
// Controlled via AppContext:
const modal = useModal();
modal.open(<div>Content</div>);
modal.close();

// Or direct usage:
<Modal visible={show} onClose={onClose} title="Title">{children}</Modal>
```

Auto-locks body scroll when visible.

### Toast

Notification that auto-dismisses after 2.5s.

```tsx
const toast = useToast();
toast('Message', 'success');   // success | error | warning | info
```

Position: top-center (mobile), top-right (desktop).

### Avatar

Circular avatar with icon or initials.

```tsx
<Avatar icon="user" color="#3b82f6" size={48} />
<Avatar initials="AB" color="#22c55e" size={36} />
```

### TabSwitcher

Animated tab bar with sliding indicator.

```tsx
const [tab, setTab] = useState(0);
<TabSwitcher tabs={['Tab A', 'Tab B', 'Tab C']} activeIndex={tab} onChange={setTab} />
```

### StatPill

Small inline stat badge.

```tsx
<StatPill color="#22c55e" label="Active" value="128" />
```

### ProgressBar

```tsx
<ProgressBar label="Usage" current={750} total={1000} color="#3b82f6" />
```

Automatically shows red when `current > total`.

### SearchBox

```tsx
<SearchBox value={q} onChange={setQ} placeholder="Search..." />
```

### EmptyState

```tsx
<EmptyState icon="search" message="No results found" />
```

---

## Form Components

### FormInput

Text input with label, error, and hint support.

```tsx
<FormInput
  label="Username"
  value={val}
  onChange={setVal}
  placeholder="Enter..."
  error="Required field"
  hint="Hint text"
  type="password"
/>
```

### AmountInput

Large currency input with decimal validation (max 2 decimal places).

```tsx
<AmountInput value={amount} onChange={setAmount} symbol="¥" />
```

### FormSelect

Dropdown select with custom styling.

```tsx
<FormSelect
  label="Category"
  value={val}
  onChange={setVal}
  placeholder="Choose..."
  options={[{ value: 'a', label: 'Option A' }]}
/>
```

### DatePicker

Native HTML5 date input wrapped in form styling.

```tsx
<DatePicker label="Date" value={date} onChange={setDate} />
```

### ToggleSwitch

```tsx
<ToggleSwitch label="Enable" checked={on} onChange={setOn} />
```

---

## Data Display Components

### StatCard

Stat display with icon, value, and change indicator.

```tsx
<StatCard
  icon="dollar"
  label="Revenue"
  value="¥76,120"
  change="+12.5%"
  changeType="up"
  iconColor="#3b82f6"
/>
```

### BarChart

Animated bar chart with hover tooltips.

```tsx
<BarChart
  data={[
    { label: 'Mon', value: 320 },
    { label: 'Tue', value: 450 },
  ]}
  activeIndex={1}  // Highlighted bar (default: last)
/>
```

### DonutChart

SVG donut chart with center value and legend.

```tsx
<DonutChart
  segments={[
    { label: 'A', value: 35, color: '#f97316' },
    { label: 'B', value: 25, color: '#3b82f6' },
  ]}
  centerValue="100%"
  centerLabel="Total"
  size={160}
/>
```

---

## Layout Components

### AppShell

Root layout orchestrator. Renders Sidebar + main area (TopBar, MobileHeader, PageContainer, BottomNav).

**To add a new page:**
1. Add PageId to `src/types/index.ts`
2. Create page component in `src/components/pages/`
3. Add entry in `AppShell.tsx` pages array
4. Add nav items in `Sidebar.tsx`, `BottomNav.tsx`, `TopBar.tsx`, `MobileHeader.tsx`

### PageContainer

Panel-based page switching with CSS transitions. All pages coexist in DOM; only active panel is visible.

### Sidebar / TopBar / MobileHeader / BottomNav

Navigation components. Visibility controlled by CSS media queries:
- Mobile (<768px): MobileHeader + BottomNav
- Tablet (768-1199px): Collapsed Sidebar (icon-only) + TopBar
- Desktop (>=1200px): Full Sidebar + TopBar
