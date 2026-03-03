import type { PageId } from '../../types';
import { useApp, useNavigate, useAuth } from '../../context/AppContext';
import { useTheme } from '../../context/ThemeContext';
import Icon from '../ui/Icon';

const navItems: { id: PageId; label: string; icon: string }[] = [
  { id: 'home', label: '首页', icon: 'home' },
  { id: 'demo', label: '组件', icon: 'grid' },
];

const themeIcon: Record<string, string> = { light: 'sun', dark: 'moon', system: 'monitor' };
const themeLabel: Record<string, string> = { light: '浅色模式', dark: '深色模式', system: '跟随系统' };

export default function Sidebar() {
  const { state } = useApp();
  const navigate = useNavigate();
  const { mode, cycle } = useTheme();
  const { username, logout } = useAuth();

  return (
    <nav className="sidebar">
      <div className="sidebar-logo">
        <div className="logo-icon">D</div>
        <div>
          <div className="logo-text">Dashboard</div>
          <div className="logo-sub">UI Kit</div>
        </div>
      </div>
      <div className="sidebar-section">
        <div className="sidebar-section-label">菜单</div>
        {navItems.map(item => (
          <div
            key={item.id}
            className={`sidebar-item ${state.currentPage === item.id ? 'active' : ''}`}
            onClick={() => navigate(item.id)}
          >
            <Icon name={item.icon} size={20} />
            <span className="item-label">{item.label}</span>
          </div>
        ))}
      </div>
      <div className="sidebar-bottom">
        <div className="sidebar-theme" onClick={cycle} title={themeLabel[mode]}>
          <Icon name={themeIcon[mode]} size={20} />
          <span className="item-label">{themeLabel[mode]}</span>
        </div>
        <div className="logout-btn" onClick={logout} title="退出登录">
          <Icon name="logout" size={20} />
          <span className="item-label">退出登录</span>
        </div>
        <div className="sidebar-user">
          <div className="sidebar-user-avatar">{username[0]?.toUpperCase() || 'U'}</div>
          <div>
            <div className="sidebar-user-name">{username}</div>
            <div className="sidebar-user-email">{username}@example.com</div>
          </div>
        </div>
      </div>
    </nav>
  );
}
