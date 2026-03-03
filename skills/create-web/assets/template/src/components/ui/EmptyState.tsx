import Icon from './Icon';

interface EmptyStateProps {
  icon?: string;
  message: string;
}

export default function EmptyState({ icon = 'info', message }: EmptyStateProps) {
  return (
    <div className="empty-state">
      <Icon name={icon} size={48} />
      <p>{message}</p>
    </div>
  );
}
