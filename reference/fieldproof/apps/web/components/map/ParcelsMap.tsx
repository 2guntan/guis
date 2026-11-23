'use client';

import dynamic from 'next/dynamic';
import type { MapParcel } from './ParcelsMapCanvas';

const Canvas = dynamic(() => import('./ParcelsMapCanvas'), {
  ssr: false,
  loading: () => <div className="h-full min-h-40 w-full animate-pulse bg-forest-900/80" />,
});

export function ParcelsMap(props: { parcels: MapParcel[]; className?: string; interactive?: boolean; point?: { lat: number; lng: number } | null }) {
  return <Canvas {...props} />;
}
export type { MapParcel };
