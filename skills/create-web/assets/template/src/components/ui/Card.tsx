import type { ReactNode } from 'react';

interface CardProps {
  title?: string;
  linkText?: string;
  onLinkClick?: () => void;
  children: ReactNode;
  className?: string;
}

export default function Card({ title, linkText, onLinkClick, children, className = '' }: CardProps) {
  return (
    <div className={`card ${className}`}>
      {(title || linkText) && (
        <div className="card-header">
          {title && <span className="card-title">{title}</span>}
          {linkText && <span className="card-link" onClick={onLinkClick}>{linkText}</span>}
        </div>
      )}
      {children}
    </div>
  );
}
