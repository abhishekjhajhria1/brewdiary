import clsx from "clsx";

/** A small quick-pick chip — tap to fill a field. Small radius (not a large pill). */
export function Chip({
  children,
  onClick,
  active,
}: {
  children: React.ReactNode;
  onClick: () => void;
  active?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={clsx(
        "rounded-ctl border px-2.5 py-1 text-sm transition-colors",
        active
          ? "border-ink bg-ink text-paper"
          : "border-line-strong text-muted hover:border-ink hover:text-ink",
      )}
    >
      {children}
    </button>
  );
}
