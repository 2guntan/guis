// Barre du haut de la direction B : 64 px, craie, bordure basse, titre Fraunces 22.
export function TopBar({ title, before, after, children }: { title: React.ReactNode; before?: React.ReactNode; after?: React.ReactNode; children?: React.ReactNode }) {
  return (
    <header className="sticky top-0 z-[500] flex h-16 items-center gap-4 border-b border-line bg-chalk px-6">
      {before}
      <h1 className="truncate text-[22px] leading-7 text-board-text" style={{ fontWeight: 650 }}>
        {title}
      </h1>
      {after}
      <div className="ml-auto flex items-center gap-3">{children}</div>
    </header>
  );
}

export function ExportButton({ href = '/api/export' }: { href?: string }) {
  return (
    <a href={href} className="btn-b">
      Exporter en Excel
    </a>
  );
}
