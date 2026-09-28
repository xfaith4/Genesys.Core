/** Small shared UI atoms. Skin-agnostic: every colour comes from CSS custom properties. */

import type { ChangeEvent, ReactNode } from 'react';

export const Badge = ({
  children,
  tone = 'neutral',
  title,
}: {
  children: ReactNode;
  tone?: 'neutral' | 'accent' | 'good' | 'warn' | 'bad' | 'muted';
  title?: string;
}) => (
  <span className={`badge badge--${tone}`} title={title}>
    {children}
  </span>
);

export const Button = ({
  children,
  onClick,
  variant = 'default',
  disabled,
  title,
  type = 'button',
  'aria-pressed': ariaPressed,
}: {
  children: ReactNode;
  onClick?: () => void;
  variant?: 'default' | 'primary' | 'ghost' | 'danger';
  disabled?: boolean;
  title?: string;
  type?: 'button' | 'submit';
  'aria-pressed'?: boolean;
}) => (
  <button
    type={type}
    className={`btn btn--${variant}`}
    onClick={onClick}
    disabled={disabled}
    title={title}
    aria-pressed={ariaPressed}
  >
    {children}
  </button>
);

export const IconButton = ({
  label,
  onClick,
  children,
  disabled,
}: {
  label: string;
  onClick?: () => void;
  children: ReactNode;
  disabled?: boolean;
}) => (
  <button type="button" className="icon-btn" onClick={onClick} aria-label={label} title={label} disabled={disabled}>
    {children}
  </button>
);

export const Select = <T extends string>({
  value,
  onChange,
  options,
  label,
  id,
}: {
  value: T;
  onChange: (value: T) => void;
  options: { value: T; label: string }[];
  label?: string;
  id?: string;
}) => (
  <label className="field" htmlFor={id}>
    {label ? <span className="field__label">{label}</span> : null}
    <select
      id={id}
      className="field__control"
      value={value}
      onChange={(event: ChangeEvent<HTMLSelectElement>) => onChange(event.target.value as T)}
    >
      {options.map((option) => (
        <option key={option.value} value={option.value}>
          {option.label}
        </option>
      ))}
    </select>
  </label>
);

export const TextInput = ({
  value,
  onChange,
  placeholder,
  label,
  id,
  type = 'text',
}: {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  label?: string;
  id?: string;
  type?: string;
}) => (
  <label className="field" htmlFor={id}>
    {label ? <span className="field__label">{label}</span> : null}
    <input
      id={id}
      type={type}
      className="field__control"
      value={value}
      placeholder={placeholder}
      onChange={(event) => onChange(event.target.value)}
    />
  </label>
);

export const Toggle = ({
  checked,
  onChange,
  label,
}: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  label: string;
}) => (
  <label className="toggle">
    <input type="checkbox" checked={checked} onChange={(event) => onChange(event.target.checked)} />
    <span>{label}</span>
  </label>
);

export const Spinner = ({ label = 'Loading' }: { label?: string }) => (
  <div className="spinner" role="status" aria-live="polite">
    <span className="spinner__dot" />
    <span>{label}</span>
  </div>
);

export const EmptyState = ({ title, hint }: { title: string; hint?: ReactNode }) => (
  <div className="empty-state">
    <p className="empty-state__title">{title}</p>
    {hint ? <p className="empty-state__hint">{hint}</p> : null}
  </div>
);

export const ErrorState = ({ message, onRetry }: { message: string; onRetry?: () => void }) => (
  <div className="error-state" role="alert">
    <p className="error-state__title">Could not load data</p>
    <p className="error-state__message">{message}</p>
    {onRetry ? (
      <Button onClick={onRetry} variant="primary">
        Try again
      </Button>
    ) : null}
  </div>
);

/** Fixed-width label/value pair used across detail panels. */
export const DetailRow = ({ label, children }: { label: string; children: ReactNode }) => (
  <div className="detail-row">
    <span className="detail-row__label">{label}</span>
    <span className="detail-row__value">{children}</span>
  </div>
);

export const MethodBadge = ({ method }: { method: string }) => {
  const tone =
    method === 'GET' ? 'good' : method === 'POST' ? 'accent' : method === 'DELETE' ? 'bad' : 'warn';
  return (
    <Badge tone={tone}>
      <code>{method}</code>
    </Badge>
  );
};

const COVERAGE_TONE: Record<string, 'good' | 'accent' | 'warn' | 'muted'> = {
  fixture: 'good',
  'paged-fixture': 'good',
  'cursor-fixture': 'good',
  'async-submit': 'accent',
  'async-poll': 'accent',
  inline: 'warn',
  generated: 'muted',
};

const COVERAGE_LABEL: Record<string, string> = {
  fixture: 'Demo data',
  'paged-fixture': 'Demo data, paged',
  'cursor-fixture': 'Demo data, cursor',
  'async-submit': 'Async submit',
  'async-poll': 'Async poll',
  inline: 'Synthesized',
  generated: 'Empty skeleton',
};

export const CoverageBadge = ({ coverage, title }: { coverage: string; title?: string }) => (
  <Badge tone={COVERAGE_TONE[coverage] ?? 'muted'} title={title}>
    {COVERAGE_LABEL[coverage] ?? coverage}
  </Badge>
);

/** Syntax-free JSON block with a copy affordance. */
export const JsonBlock = ({ value, maxHeight = 320 }: { value: unknown; maxHeight?: number }) => (
  <pre className="json-block" style={{ maxHeight }}>
    {JSON.stringify(value, null, 2)}
  </pre>
);
