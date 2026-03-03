import Icon from './Icon';

interface AvatarProps {
  icon?: string;
  initials?: string;
  color: string;
  size?: number;
}

export default function Avatar({ icon, initials, color, size = 40 }: AvatarProps) {
  return (
    <div
      style={{
        width: size,
        height: size,
        borderRadius: '50%',
        background: color,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        flexShrink: 0,
        fontSize: size * 0.35,
        fontWeight: 700,
        color: '#fff',
      }}
    >
      {icon ? <Icon name={icon} size={size * 0.45} /> : initials}
    </div>
  );
}
