interface TabSwitcherProps {
  tabs: string[];
  activeIndex: number;
  onChange: (index: number) => void;
}

export default function TabSwitcher({ tabs, activeIndex, onChange }: TabSwitcherProps) {
  return (
    <div className="tab-switcher">
      <div
        className="tab-indicator"
        style={{
          width: `${100 / tabs.length}%`,
          transform: `translateX(${activeIndex * 100}%)`,
        }}
      />
      {tabs.map((tab, i) => (
        <button
          key={tab}
          className={`tab-btn ${i === activeIndex ? 'active' : ''}`}
          onClick={() => onChange(i)}
        >
          {tab}
        </button>
      ))}
    </div>
  );
}
