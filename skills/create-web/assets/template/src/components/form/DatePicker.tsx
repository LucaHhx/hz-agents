interface DatePickerProps {
  label?: string;
  value: string;
  onChange: (value: string) => void;
}

export default function DatePicker({ label, value, onChange }: DatePickerProps) {
  return (
    <div className="form-group">
      {label && <label className="form-label">{label}</label>}
      <input
        className="form-input"
        type="date"
        value={value}
        onChange={e => onChange(e.target.value)}
      />
    </div>
  );
}
