import type { User } from '@/lib/auth';

/**
 * Droits de chaque profil (CONTEXT.md, spec 2guntan/guis#24) : la seule source des décisions de
 * droits côté serveur. Les pages s'en servent aussi pour masquer les boutons, mais c'est la
 * vérification du serveur qui fait foi.
 *
 * - admin (IBRIZ) : tout ;
 * - coordinateur (coopérative) : consulte tout sur le tableau de bord, gère l'attribution et
 *   réinitialise le code d'un agent ; ni modification, ni export, ni app Android ;
 * - agent : l'app Android, sur son périmètre (ADR-0001, ADR-0002).
 */
export type Role = User['role'];

export type Action =
  | 'use_app' // se connecter à l'app Android
  | 'use_dashboard' // se connecter au tableau de bord et le consulter
  | 'see_all' // voir tous les producteurs (sinon : périmètre de l'agent)
  | 'edit_data' // créer ou modifier producteurs, champs, photos
  | 'decide_duplicates' // trancher un doublon possible
  | 'export' // export Excel
  | 'manage_attribution' // cocher les communes des agents
  | 'reset_agent_code' // réinitialiser le code d'un agent
  | 'manage_users'; // page « Utilisateurs »

const RIGHTS: Record<Role, readonly Action[]> = {
  admin: ['use_app', 'use_dashboard', 'see_all', 'edit_data', 'decide_duplicates', 'export', 'manage_attribution', 'reset_agent_code', 'manage_users'],
  coordinator: ['use_dashboard', 'see_all', 'manage_attribution', 'reset_agent_code'],
  agent: ['use_app', 'edit_data'],
};

export const can = (user: Pick<User, 'role'> | null | undefined, action: Action): boolean =>
  !!user && (RIGHTS[user.role] ?? []).includes(action);

export const ROLE_LABELS: Record<Role, string> = { admin: 'Admin', coordinator: 'Coordinateur', agent: 'Agent' };
