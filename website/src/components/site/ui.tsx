import type { ComponentProps, ReactNode } from "react";

export function AppleIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} fill="currentColor" aria-hidden>
      <path d="M16.37 12.6c-.02-2.2 1.8-3.27 1.88-3.32-1.03-1.5-2.62-1.7-3.18-1.73-1.35-.14-2.64.8-3.33.8-.69 0-1.74-.78-2.86-.76-1.47.02-2.83.86-3.59 2.17-1.53 2.66-.39 6.59 1.1 8.75.73 1.05 1.6 2.24 2.73 2.2 1.1-.04 1.51-.71 2.84-.71 1.32 0 1.7.71 2.86.69 1.18-.02 1.93-1.07 2.65-2.13.84-1.22 1.18-2.4 1.2-2.46-.03-.01-2.3-.88-2.32-3.5zM14.2 6.13c.6-.73 1.01-1.75.9-2.76-.87.04-1.92.58-2.54 1.31-.56.65-1.05 1.68-.92 2.68.97.07 1.96-.5 2.56-1.23z" />
    </svg>
  );
}

const base =
  "inline-flex items-center justify-center gap-2 rounded-full font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:opacity-50";

const sizes = {
  sm: "h-9 px-4 text-sm",
  lg: "h-12 px-6 text-[15px]",
};

const variants = {
  primary: "bg-foreground text-background hover:bg-foreground/85 active:bg-foreground/75",
  accent: "bg-accent text-white hover:bg-accent/90 active:bg-accent/80",
  outline: "ring-1 ring-inset ring-control-edge text-foreground hover:bg-control-plate",
  inverse: "bg-white text-ink hover:bg-white/90",
};

export function buttonClass(
  variant: keyof typeof variants = "primary",
  size: keyof typeof sizes = "sm",
  className = "",
) {
  return `${base} ${sizes[size]} ${variants[variant]} ${className}`;
}

export function ButtonLink({
  variant,
  size,
  className,
  ...props
}: ComponentProps<"a"> & { variant?: keyof typeof variants; size?: keyof typeof sizes }) {
  return <a className={buttonClass(variant, size, className)} {...props} />;
}

export function SectionTitle({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <h2
      className={`display max-w-[22ch] text-[clamp(1.875rem,3.4vw,2.875rem)] leading-[1.08] ${className}`}
    >
      {children}
    </h2>
  );
}

export function Check({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" className={`size-4 shrink-0 ${className}`} fill="none" aria-hidden>
      <path d="M3.5 8.5l3 3 6-7" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
