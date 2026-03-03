interface DonutSegment {
  label: string;
  value: number;
  color: string;
}

interface DonutChartProps {
  segments: DonutSegment[];
  centerValue?: string;
  centerLabel?: string;
  size?: number;
}

export default function DonutChart({ segments, centerValue, centerLabel, size = 160 }: DonutChartProps) {
  const total = segments.reduce((s, seg) => s + seg.value, 0);
  const radius = 60;
  const circumference = 2 * Math.PI * radius;
  let offset = 0;

  return (
    <div className="donut-wrap">
      <div className="donut-chart">
        <svg width={size} height={size} viewBox="0 0 160 160">
          {segments.map((seg, i) => {
            const pct = total > 0 ? seg.value / total : 0;
            const dash = pct * circumference;
            const gap = circumference - dash;
            const currentOffset = offset;
            offset += dash;

            return (
              <circle
                key={i}
                cx="80"
                cy="80"
                r={radius}
                fill="none"
                stroke={seg.color}
                strokeWidth="20"
                strokeDasharray={`${dash} ${gap}`}
                strokeDashoffset={-currentOffset}
                strokeLinecap="round"
                style={{
                  transform: 'rotate(-90deg)',
                  transformOrigin: '80px 80px',
                  transition: 'stroke-dasharray 0.8s cubic-bezier(0.32,0.72,0,1), stroke-dashoffset 0.8s cubic-bezier(0.32,0.72,0,1)',
                  transitionDelay: `${i * 0.1}s`,
                }}
              />
            );
          })}
        </svg>
        {(centerValue || centerLabel) && (
          <div className="donut-center">
            {centerValue && <div className="donut-center-value">{centerValue}</div>}
            {centerLabel && <div className="donut-center-label">{centerLabel}</div>}
          </div>
        )}
      </div>
      <div className="donut-legend">
        {segments.map((seg, i) => (
          <div key={i} className="donut-legend-item">
            <span className="donut-legend-dot" style={{ background: seg.color }} />
            <span className="donut-legend-label">{seg.label}</span>
            <span className="donut-legend-value">{total > 0 ? Math.round((seg.value / total) * 100) : 0}%</span>
          </div>
        ))}
      </div>
    </div>
  );
}
