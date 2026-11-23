import { AppHeader } from '@/components/AppHeader';
import { NavLink } from '@/components/dashboard/NavLink';
import { requireAdmin } from '@/lib/auth';

export const dynamic = 'force-dynamic';

// Repris de Fieldproof (app/superviseur/layout.tsx) : un seul rôle, « admin ».
export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const user = await requireAdmin();
  return (
    <div className="min-h-dvh">
      <AppHeader
        home="/"
        name={user.name}
        role="Administrateur"
        nav={
          <>
            <NavLink href="/" exact>Tableau de bord</NavLink>
            <NavLink href="/champs">Champs</NavLink>
            <NavLink href="/producteurs">Producteurs</NavLink>
          </>
        }
      />
      {children}
    </div>
  );
}
