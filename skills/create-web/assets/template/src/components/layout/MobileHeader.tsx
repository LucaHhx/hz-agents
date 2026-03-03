import { useApp, useAuth } from '../../context/AppContext';
import { useTheme } from '../../context/ThemeContext';
import Icon from '../ui/Icon';

const pageTitles: Record<string, string> = {
  home: '首页',
  demo: '组件',
};

const themeIcon: Record<string, string> = { light: 'sun', dark: 'moon', system: 'monitor' };

export default function MobileHeader() {
  const { state } = useApp();
  const { mode, cycle } = useTheme();
  const { logout } = useAuth();

  return (
    <div className="mobile-header">
      <div className="mobile-header-title">{pageTitles[state.currentPage] || ''}</div>
      <div style={{ display: 'flex', gap: 8 }}>
        <div className="theme-toggle" onClick={cycle}>
          <Icon name={themeIcon[mode]} size={18} />
        </div>
        <div className="theme-toggle" onClick={logout} title="退出登录">
          <Icon name="logout" size={18} />
        </div>
      </div>
    </div>
  );
}
