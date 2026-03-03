interface StatPillProps {
  color: string;
  label: string;
  value: string;
}

export default function StatPill({ color, label, value }: StatPillProps) {
  return (
    <div className="stat-pill">
      <span className="stat-pill-dot" style={{ background: color }} />
      <span className="stat-pill-label">{label}</span>
      <span className="stat-pill-value">{value}</span>
    </div>
  );
}
