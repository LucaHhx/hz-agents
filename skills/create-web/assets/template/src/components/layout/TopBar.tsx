import { useApp, useAuth } from '../../context/AppContext';
import { useTheme } from '../../context/ThemeContext';
import Icon from '../ui/Icon';

const pageTitles: Record<string, { title: string; sub: string }> = {
  home: { title: '首页', sub: '欢迎回来' },
  demo: { title: '组件演示', sub: '所有可用组件' },
};

const themeIcon: Record<string, string> = { light: 'sun', dark: 'moon', system: 'monitor' };
const themeLabel: Record<string, string> = { light: '浅色', dark: '深色', system: '跟随系统' };

export default function TopBar() {
  const { state } = useApp();
  const { mode, cycle } = useTheme();
  const { logout } = useAuth();
  const info = pageTitles[state.currentPage] || { title: '', sub: '' };

  return (
    <div className="top-bar">
      <div>
        <div className="top-bar-title">{info.title}</div>
        <div className="top-bar-sub">{info.sub}</div>
      </div>
      <div className="top-bar-right">
        <div className="theme-toggle" onClick={cycle} title={themeLabel[mode]}>
          <Icon name={themeIcon[mode]} size={18} />
        </div>
        <div className="top-btn">
          <Icon name="bell" size={18} />
        </div>
        <div className="top-btn" onClick={logout} title="退出登录">
          <Icon name="logout" size={18} />
        </div>
      </div>
    </div>
  );
}
