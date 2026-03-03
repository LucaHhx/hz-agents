interface AmountInputProps {
  value: string;
  onChange: (value: string) => void;
  symbol?: string;
}

export default function AmountInput({ value, onChange, symbol = '¥' }: AmountInputProps) {
  const handleChange = (raw: string) => {
    const cleaned = raw.replace(/[^\d.]/g, '');
    const parts = cleaned.split('.');
    if (parts.length > 2) return;
    if (parts[1] && parts[1].length > 2) return;
    onChange(cleaned);
  };

  return (
    <div className="amount-input-wrap">
      <span className="amount-symbol">{symbol}</span>
      <input
        className="amount-input"
        type="text"
        inputMode="decimal"
        value={value}
        onChange={e => handleChange(e.target.value)}
        placeholder="0.00"
      />
    </div>
  );
}
