import Sidebar from './Sidebar';
import TopBar from './TopBar';
import MobileHeader from './MobileHeader';
import BottomNav from './BottomNav';
import PageContainer from './PageContainer';
import HomePage from '../pages/HomePage';
import DemoPage from '../pages/DemoPage';

export default function AppShell() {
  const pages = [
    { id: 'home' as const, component: <HomePage /> },
    { id: 'demo' as const, component: <DemoPage /> },
  ];

  return (
    <>
      <Sidebar />
      <div className="main">
        <TopBar />
        <MobileHeader />
        <PageContainer pages={pages} />
        <BottomNav />
      </div>
    </>
  );
}
