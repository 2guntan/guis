import type { Metadata } from 'next';
import { TopBar } from '@/components/dashboard/TopBar';
import { requireDashboard } from '@/lib/auth';
import { listAccounts, listEvents } from '@/lib/users';
import { UsersManager } from './UsersManager';

export const metadata: Metadata = { title: 'Utilisateurs' };

// Page « Utilisateurs » (spec 2guntan/guis#24) : réservée à l'admin.
export default async function UsersPage() {
  const user = await requireDashboard('manage_users');
  const [users, events] = await Promise.all([listAccounts(), listEvents()]);
  return (
    <div>
      <TopBar title="Utilisateurs" />
      <div className="mx-auto max-w-[1200px] px-6 py-6">
        <UsersManager me={user.id} users={JSON.parse(JSON.stringify(users))} events={JSON.parse(JSON.stringify(events))} />
      </div>
    </div>
  );
}
