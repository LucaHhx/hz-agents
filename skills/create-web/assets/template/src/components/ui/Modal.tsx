import { useEffect } from 'react';
import type { ReactNode } from 'react';
import { createPortal } from 'react-dom';

interface ModalProps {
  visible: boolean;
  onClose: () => void;
  children: ReactNode;
  title?: string;
}

export default function Modal({ visible, onClose, children, title }: ModalProps) {
  useEffect(() => {
    if (visible) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
    }
    return () => { document.body.style.overflow = ''; };
  }, [visible]);

  return createPortal(
    <>
      <div className={`modal-bg ${visible ? 'show' : ''}`} onClick={onClose} />
      <div className={`modal-sheet ${visible ? 'show' : ''}`}>
        <div className="modal-handle" />
        {title && <div className="modal-title">{title}</div>}
        {children}
      </div>
    </>,
    document.body
  );
}
