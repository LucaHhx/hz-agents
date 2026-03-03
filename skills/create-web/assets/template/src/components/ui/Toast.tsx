import Icon from './Icon';

interface ToastProps {
  message: string;
  variant: 'success' | 'error' | 'warning' | 'info';
  visible: boolean;
}

const variantColors: Record<string, string> = {
  success: '#22c55e',
  error: '#ef4444',
  warning: '#f97316',
  info: '#3b82f6',
};

const variantIcons: Record<string, string> = {
  success: 'check',
  error: 'close',
  warning: 'info',
  info: 'info',
};

export default function Toast({ message, variant, visible }: ToastProps) {
  return (
    <div className={`toast ${visible ? 'show' : ''}`}>
      <div className="toast-ic" style={{ background: variantColors[variant] }}>
        <Icon name={variantIcons[variant]} size={14} />
      </div>
      <span>{message}</span>
    </div>
  );
}
