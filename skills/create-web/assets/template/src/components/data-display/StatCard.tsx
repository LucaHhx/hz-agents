import Icon from '../ui/Icon';

interface StatCardProps {
  icon: string;
  label: string;
  value: string;
  change?: string;
  changeType?: 'up' | 'down';
  iconColor?: string;
}

export default function StatCard({ icon, label, value, change, changeType, iconColor = '#2cd9a0' }: StatCardProps) {
  return (
    <div className="stat-card">
      <div className="stat-card-top">
        <div className="stat-card-icon" style={{ background: `${iconColor}20`, color: iconColor }}>
          <Icon name={icon} size={18} />
        </div>
      </div>
      <div className="stat-card-label">{label}</div>
      <div className="stat-card-value">{value}</div>
      {change && (
        <span className={`stat-change ${changeType}`}>{change}</span>
      )}
    </div>
  );
}
