interface Option {
  value: string;
  label: string;
}

interface FormSelectProps {
  label?: string;
  value: string;
  onChange: (value: string) => void;
  options: Option[];
  placeholder?: string;
}

export default function FormSelect({ label, value, onChange, options, placeholder }: FormSelectProps) {
  return (
    <div className="form-group">
      {label && <label className="form-label">{label}</label>}
      <select
        className="form-select"
        value={value}
        onChange={e => onChange(e.target.value)}
      >
        {placeholder && <option value="">{placeholder}</option>}
        {options.map(o => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </select>
    </div>
  );
}
