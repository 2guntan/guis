import 'server-only';
import { redirect } from 'next/navigation';
import { supabaseServer } from '@/lib/supabase/server';

export type Role = 'platform_admin' | 'org_admin' | 'field_agent' | 'field_supervisor';
export type Membership = { organization_id: string; org_unit_id: string | null; role: Role };

export async function getSession() {
  const supabase = await supabaseServer();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const { data: memberships } = await supabase.schema('core').rpc('my_memberships');
  const { data: profile } = await supabase.schema('core').from('profiles').select('full_name, email').eq('id', user.id).maybeSingle();
  const list = (memberships ?? []) as Membership[];
  return { supabase, user, memberships: list, profile: profile as { full_name: string; email: string } | null };
}

export function homeFor(memberships: Membership[]) {
  const roles = memberships.map((m) => m.role);
  if (roles.some((r) => r === 'field_supervisor' || r === 'org_admin' || r === 'platform_admin')) return '/superviseur';
  if (roles.includes('field_agent')) return '/agent';
  return null;
}

export async function requireRole(kind: 'agent' | 'supervisor') {
  const s = await getSession();
  if (!s) redirect('/login');
  const roles = s.memberships.map((m) => m.role);
  const ok = kind === 'agent'
    ? roles.includes('field_agent')
    : roles.some((r) => r === 'field_supervisor' || r === 'org_admin' || r === 'platform_admin');
  if (!ok) redirect(homeFor(s.memberships) ?? '/login?erreur=role');
  return s;
}
