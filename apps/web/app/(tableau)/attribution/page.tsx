import type { Metadata } from 'next';
import { TopBar } from '@/components/dashboard/TopBar';
import { attributionGrid } from '@/lib/attribution';
import { requireDashboard } from '@/lib/auth';
import { AttributionGrid } from './AttributionGrid';

export const metadata: Metadata = { title: 'Attribution' };

// Page « Attribution » (spec 2guntan/guis#24) : admin et coordinateur.
export default async function AttributionPage() {
  await requireDashboard('manage_attribution');
  const grid = await attributionGrid();
  return (
    <div>
      <TopBar title="Attribution" />
      <div className="mx-auto max-w-[1200px] px-6 py-6">
        <AttributionGrid grid={JSON.parse(JSON.stringify(grid))} />
      </div>
    </div>
  );
}
