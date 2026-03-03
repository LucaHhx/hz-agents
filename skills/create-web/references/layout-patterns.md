# Layout Patterns Guide

## Table of Contents

- [App Architecture](#app-architecture)
- [Adding a New Page](#adding-a-new-page)
- [State Management](#state-management)
- [Authentication Flow](#authentication-flow)
- [Navigation System](#navigation-system)
- [Common Layout Patterns](#common-layout-patterns)

---

## App Architecture

```
App
├── ThemeProvider (light/dark/system)
└── AppProvider (global state)
    └── AppInner
        ├── IF !isAuthenticated → Login
        └── IF isAuthenticated → AppShell
            ├── Sidebar
            └── div.main
                ├── TopBar
                ├── MobileHeader
                ├── PageContainer
                │   └── [Page1, Page2, ...]
                └── BottomNav
```

Toast and Modal are rendered at App level (outside AppShell) for global access.

---

## Adding a New Page

### Step 1: Define PageId

```typescript
// src/types/index.ts
export type PageId = 'home' | 'demo' | 'your-page';
```

### Step 2: Create Page Component

```typescript
// src/components/pages/YourPage.tsx
export default function YourPage() {
  return (
    <>
      <div className="stat-grid">
        {/* Content */}
      </div>
    </>
  );
}
```

Pages render directly inside a `.panel` div — no need for wrapper container.

### Step 3: Register in AppShell

```typescript
// src/components/layout/AppShell.tsx
import YourPage from '../pages/YourPage';

const pages = [
  { id: 'home' as const, component: <HomePage /> },
  { id: 'demo' as const, component: <DemoPage /> },
  { id: 'your-page' as const, component: <YourPage /> },
];
```

### Step 4: Add Navigation

Add entries to all 4 navigation components:

```typescript
// Sidebar.tsx, BottomNav.tsx
const navItems = [
  ...existing,
  { id: 'your-page', label: '新页面', icon: 'list' },
];

// TopBar.tsx
const pageTitles = {
  ...existing,
  'your-page': { title: '新页面', sub: '页面描述' },
};

// MobileHeader.tsx
const pageTitles = {
  ...existing,
  'your-page': '新页面',
};
```

---

## State Management

### Reducer Pattern

State is managed via `useReducer` in AppContext. To add business state:

```typescript
// 1. Extend AppState
interface AppState {
  currentPage: PageId;
  toast: ToastState;
  modal: ModalState;
  auth: AuthState;
  // Add your state:
  items: Item[];
}

// 2. Add action types
type AppAction =
  | ... existing
  | { type: 'ADD_ITEM'; item: Item }
  | { type: 'REMOVE_ITEM'; id: string };

// 3. Handle in reducer
case 'ADD_ITEM':
  return { ...state, items: [...state.items, action.item] };

// 4. Create a custom hook
export function useItems() {
  const { state, dispatch } = useApp();
  const add = useCallback((item: Item) =>
    dispatch({ type: 'ADD_ITEM', item }), [dispatch]);
  return { items: state.items, add };
}
```

### Available Hooks

| Hook | Returns | Purpose |
|------|---------|---------|
| `useApp()` | `{ state, dispatch }` | Raw state access |
| `useAuth()` | `{ isAuthenticated, username, login, logout }` | Auth operations |
| `useNavigate()` | `(page: PageId) => void` | Page navigation |
| `useToast()` | `(msg, variant?) => void` | Show toast (auto-dismiss 2.5s) |
| `useModal()` | `{ open(content), close() }` | Modal control |

---

## Authentication Flow

Default credentials: `admin` / `123456`

### Customizing Auth

Edit `Login.tsx` to change validation logic:

```typescript
// For API-based auth:
const handleSubmit = async (e: React.FormEvent) => {
  e.preventDefault();
  try {
    const res = await fetch('/api/login', {
      method: 'POST',
      body: JSON.stringify({ username, password }),
    });
    if (res.ok) {
      const data = await res.json();
      login(data.username);
    } else {
      setError('认证失败');
    }
  } catch {
    setError('网络错误');
  }
};
```

Auth state persists in `localStorage` under key `"auth"`.

---

## Navigation System

### Panel-Based Routing

All pages coexist in DOM. Only the active page has `opacity: 1` and `pointer-events: auto`. This enables:

- Smooth CSS transitions between pages
- State preservation when switching pages
- No re-mounting of components

### Responsive Navigation

| Screen | Navigation |
|--------|------------|
| Mobile (<768px) | BottomNav (bottom) + MobileHeader (top) |
| Tablet (768-1199px) | Collapsed Sidebar (72px, icons only) + TopBar |
| Desktop (>=1200px) | Full Sidebar (260px) + TopBar |

---

## Common Layout Patterns

### Dashboard Grid

```tsx
<div className="stat-grid">
  <StatCard ... />
  <StatCard ... />
  <StatCard ... />
</div>

<div className="grid">
  <Card title="Chart">{/* chart */}</Card>
  <Card title="List">{/* list */}</Card>
</div>
```

stat-grid: 2 cols mobile, 2 cols tablet, 3 cols desktop
grid: 1 col mobile, 2 cols tablet, 2 cols desktop

### Form Page

```tsx
<Card title="Form Section">
  <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
    <FormInput ... />
    <FormSelect ... />
    <DatePicker ... />
  </div>
</Card>
<Button variant="primary">Submit</Button>
```

### List Page

```tsx
<div style={{ marginBottom: 16 }}>
  <SearchBox value={q} onChange={setQ} />
</div>
<TabSwitcher tabs={['All', 'Active', 'Done']} ... />
<div style={{ marginTop: 16 }}>
  {items.map(item => (
    <Card key={item.id}>{/* item content */}</Card>
  ))}
  {items.length === 0 && <EmptyState message="No items" />}
</div>
```

### Detail Modal

```tsx
const modal = useModal();

const showDetail = (item: Item) => {
  modal.open(
    <div>
      <div className="modal-row">
        <span className="ml">Label</span>
        <span className="mv">{item.value}</span>
      </div>
    </div>
  );
};
```
