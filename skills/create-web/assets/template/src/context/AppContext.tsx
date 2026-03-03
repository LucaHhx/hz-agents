import { createContext, useContext, useReducer, useCallback } from 'react';
import type { ReactNode } from 'react';
import type { PageId, ToastVariant } from '../types';

// ========================================
// State
// ========================================

interface ToastState {
  message: string;
  variant: ToastVariant;
  visible: boolean;
}

interface ModalState {
  content: ReactNode | null;
  visible: boolean;
}

interface AuthState {
  isAuthenticated: boolean;
  username: string;
}

interface AppState {
  currentPage: PageId;
  toast: ToastState;
  modal: ModalState;
  auth: AuthState;
}

// ========================================
// Actions — extend with your business actions
// ========================================

type AppAction =
  | { type: 'NAVIGATE'; page: PageId }
  | { type: 'SHOW_TOAST'; message: string; variant?: ToastVariant }
  | { type: 'DISMISS_TOAST' }
  | { type: 'OPEN_MODAL'; content: ReactNode }
  | { type: 'CLOSE_MODAL' }
  | { type: 'LOGIN'; username: string }
  | { type: 'LOGOUT' };

// ========================================
// Auth persistence
// ========================================

function loadAuth(): AuthState {
  try {
    const saved = localStorage.getItem('auth');
    if (saved) {
      const parsed = JSON.parse(saved);
      if (parsed.isAuthenticated && parsed.username) {
        return { isAuthenticated: true, username: parsed.username };
      }
    }
  } catch { /* ignore */ }
  return { isAuthenticated: false, username: '' };
}

// ========================================
// Reducer
// ========================================

const initialState: AppState = {
  currentPage: 'home',
  toast: { message: '', variant: 'success', visible: false },
  modal: { content: null, visible: false },
  auth: loadAuth(),
};

function appReducer(state: AppState, action: AppAction): AppState {
  switch (action.type) {
    case 'NAVIGATE':
      return { ...state, currentPage: action.page };
    case 'SHOW_TOAST':
      return { ...state, toast: { message: action.message, variant: action.variant || 'success', visible: true } };
    case 'DISMISS_TOAST':
      return { ...state, toast: { ...state.toast, visible: false } };
    case 'OPEN_MODAL':
      return { ...state, modal: { content: action.content, visible: true } };
    case 'CLOSE_MODAL':
      return { ...state, modal: { content: null, visible: false } };
    case 'LOGIN': {
      const auth = { isAuthenticated: true, username: action.username };
      localStorage.setItem('auth', JSON.stringify(auth));
      return { ...state, auth };
    }
    case 'LOGOUT': {
      localStorage.removeItem('auth');
      return { ...state, auth: { isAuthenticated: false, username: '' } };
    }
    default:
      return state;
  }
}

// ========================================
// Context + Provider
// ========================================

interface AppContextType {
  state: AppState;
  dispatch: React.Dispatch<AppAction>;
}

const AppContext = createContext<AppContextType | null>(null);

export function AppProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(appReducer, initialState);
  return (
    <AppContext.Provider value={{ state, dispatch }}>
      {children}
    </AppContext.Provider>
  );
}

// ========================================
// Hooks
// ========================================

export function useApp() {
  const ctx = useContext(AppContext);
  if (!ctx) throw new Error('useApp must be inside AppProvider');
  return ctx;
}

export function useAuth() {
  const { state, dispatch } = useApp();
  const login = useCallback((username: string) => dispatch({ type: 'LOGIN', username }), [dispatch]);
  const logout = useCallback(() => dispatch({ type: 'LOGOUT' }), [dispatch]);
  return { ...state.auth, login, logout };
}

export function useNavigate() {
  const { dispatch } = useApp();
  return useCallback((page: PageId) => dispatch({ type: 'NAVIGATE', page }), [dispatch]);
}

export function useToast() {
  const { dispatch } = useApp();
  return useCallback((message: string, variant?: ToastVariant) => {
    dispatch({ type: 'SHOW_TOAST', message, variant });
    setTimeout(() => dispatch({ type: 'DISMISS_TOAST' }), 2500);
  }, [dispatch]);
}

export function useModal() {
  const { dispatch } = useApp();
  return {
    open: useCallback((content: ReactNode) => dispatch({ type: 'OPEN_MODAL', content }), [dispatch]),
    close: useCallback(() => dispatch({ type: 'CLOSE_MODAL' }), [dispatch]),
  };
}
