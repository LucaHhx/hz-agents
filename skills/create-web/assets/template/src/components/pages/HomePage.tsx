import { useAuth, useToast } from '../../context/AppContext';
import Card from '../ui/Card';
import StatCard from '../data-display/StatCard';
import BarChart from '../data-display/BarChart';
import DonutChart from '../data-display/DonutChart';
import StatPill from '../ui/StatPill';

const weeklyData = [
  { label: '周一', value: 320 },
  { label: '周二', value: 450 },
  { label: '周三', value: 180 },
  { label: '周四', value: 620 },
  { label: '周五', value: 390 },
  { label: '周六', value: 780 },
  { label: '周日', value: 420 },
];

const donutData = [
  { label: '类目A', value: 35, color: '#f97316' },
  { label: '类目B', value: 25, color: '#3b82f6' },
  { label: '类目C', value: 20, color: '#a855f7' },
  { label: '类目D', value: 15, color: '#22c55e' },
  { label: '其他', value: 5, color: '#8b8f9a' },
];

export default function HomePage() {
  const { username } = useAuth();
  const toast = useToast();

  return (
    <>
      <div style={{ marginBottom: 20 }}>
        <h2 style={{ fontSize: 18, fontWeight: 700 }}>你好, {username}</h2>
        <p className="text-muted" style={{ fontSize: 13, marginTop: 4 }}>这是你的仪表盘概览</p>
      </div>

      <div className="stat-grid">
        <StatCard icon="dollar" label="总资产" value="¥76,120.00" change="+12.5%" changeType="up" />
        <StatCard icon="trendUp" label="本月收入" value="¥15,800.00" change="+8.2%" changeType="up" iconColor="#3b82f6" />
        <StatCard icon="trendDown" label="本月支出" value="¥6,480.00" change="-3.1%" changeType="down" iconColor="#ef4444" />
      </div>

      <div className="grid">
        <Card title="本周趋势" linkText="查看详情" onLinkClick={() => toast('这是一个 Toast 提示', 'info')}>
          <BarChart data={weeklyData} />
        </Card>
        <Card title="分类占比">
          <DonutChart segments={donutData} centerValue="100%" centerLabel="总计" />
        </Card>
      </div>

      <Card title="快捷信息">
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12 }}>
          <StatPill color="#22c55e" label="活跃" value="128" />
          <StatPill color="#3b82f6" label="待处理" value="24" />
          <StatPill color="#f97316" label="警告" value="3" />
        </div>
      </Card>
    </>
  );
}
