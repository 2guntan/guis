import { AppHeader } from '@/components/AppHeader';
import { NavLink } from '@/components/superviseur/NavLink';
import { requireRole } from '@/lib/session';

const ROLE: Record<string, string> = { field_supervisor: 'Superviseur', org_admin: 'Administrateur', platform_admin: 'Administrateur plateforme' };

export default async function SupervisorLayout({ children }: { children: React.ReactNode }) {
  const s = await requireRole('supervisor');
  const role = s.memberships.map((m) => ROLE[m.role]).find(Boolean) ?? 'Superviseur';
  return (
    <div className="min-h-dvh">
      <AppHeader
        home="/superviseur"
        name={s.profile?.full_name}
        role={role}
        nav={<>
          <NavLink href="/superviseur" exact>Tableau de bord</NavLink>
          <NavLink href="/superviseur/dossiers">Dossiers</NavLink>
        </>}
      />
      {children}
    </div>
  );
}
