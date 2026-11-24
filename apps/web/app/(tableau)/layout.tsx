import { Rail } from '@/components/dashboard/Rail';
import { requireAdmin } from '@/lib/auth';
import { initials } from '@/lib/design';

export const dynamic = 'force-dynamic';

// Mise en page de la direction B « Relevé » (docs/design/web/w2 à w5) : rail à gauche, contenu à droite.
export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const user = await requireAdmin();
  return (
    <div className="min-h-dvh bg-chalk">
      <Rail name={user.name} initials={initials(user.name)} />
      <div className="pl-[72px]">{children}</div>
    </div>
  );
}
