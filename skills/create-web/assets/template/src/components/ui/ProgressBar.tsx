interface ProgressBarProps {
  label: string;
  current: number;
  total: number;
  color?: string;
  showAmount?: boolean;
}

export default function ProgressBar({ label, current, total, color = '#2cd9a0', showAmount = true }: ProgressBarProps) {
  const pct = Math.min((current / total) * 100, 100);
  const isOver = current > total;

  return (
    <div className="progress-wrap">
      <div className="progress-header">
        <span className="progress-label">{label}</span>
        {showAmount && (
          <span className="progress-amount" style={{ color: isOver ? '#ef4444' : undefined }}>
            {current.toLocaleString()} / {total.toLocaleString()}
          </span>
        )}
      </div>
      <div className="progress-bar">
        <div
          className="progress-fill"
          style={{ width: `${pct}%`, background: isOver ? '#ef4444' : color }}
        />
      </div>
    </div>
  );
}
