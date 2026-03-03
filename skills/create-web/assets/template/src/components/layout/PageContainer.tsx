import type { ReactNode } from 'react';
import type { PageId } from '../../types';
import { useApp } from '../../context/AppContext';

interface PageContainerProps {
  pages: { id: PageId; component: ReactNode }[];
}

export default function PageContainer({ pages }: PageContainerProps) {
  const { state } = useApp();

  return (
    <div className="content-area">
      {pages.map(page => (
        <div
          key={page.id}
          className={`panel ${state.currentPage === page.id ? 'active' : ''}`}
        >
          {page.component}
        </div>
      ))}
    </div>
  );
}
