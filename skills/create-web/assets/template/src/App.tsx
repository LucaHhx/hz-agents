import { AppProvider, useApp, useAuth } from './context/AppContext';
import { ThemeProvider } from './context/ThemeContext';
import AppShell from './components/layout/AppShell';
import Login from './components/pages/Login';
import Toast from './components/ui/Toast';
import Modal from './components/ui/Modal';

function AppInner() {
  const { state, dispatch } = useApp();
  const { isAuthenticated } = useAuth();

  if (!isAuthenticated) {
    return <Login />;
  }

  return (
    <>
      <AppShell />
      <Toast
        message={state.toast.message}
        variant={state.toast.variant}
        visible={state.toast.visible}
      />
      <Modal
        visible={state.modal.visible}
        onClose={() => dispatch({ type: 'CLOSE_MODAL' })}
        title="详情"
      >
        {state.modal.content}
      </Modal>
    </>
  );
}

export default function App() {
  return (
    <ThemeProvider>
      <AppProvider>
        <AppInner />
      </AppProvider>
    </ThemeProvider>
  );
}
