import { useEffect, useRef } from 'react';

interface BarChartProps {
  data: { label: string; value: number }[];
  activeIndex?: number;
}

export default function BarChart({ data, activeIndex }: BarChartProps) {
  const maxVal = Math.max(...data.map(d => d.value), 1);
  const barsRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!barsRef.current) return;
    const bars = barsRef.current.querySelectorAll<HTMLDivElement>('.cb');
    bars.forEach((bar, i) => {
      bar.style.height = '0';
      setTimeout(() => {
        const h = (data[i].value / maxVal) * 100;
        bar.style.height = `${h}%`;
      }, 80 + i * 70);
    });
  }, [data, maxVal]);

  return (
    <div className="chart-bars" ref={barsRef}>
      {data.map((item, i) => (
        <div key={i} className="cb-wrap">
          <div
            className={`cb ${i === (activeIndex ?? data.length - 1) ? 'on' : ''}`}
            style={{ height: 0 }}
          >
            <span className="tip">{item.value}</span>
          </div>
          <span className="cb-label">{item.label}</span>
        </div>
      ))}
    </div>
  );
}
