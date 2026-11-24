import 'server-only';
import { Pool, type PoolClient, type QueryResultRow } from 'pg';

// Un seul pool par processus (y compris en développement, où Next recharge les modules).
const g = globalThis as unknown as { __guisPool?: Pool };

export const pool =
  g.__guisPool ??
  (g.__guisPool = new Pool({ connectionString: process.env.DATABASE_URL, max: 10 }));

export async function query<T extends QueryResultRow = QueryResultRow>(text: string, params: unknown[] = []): Promise<T[]> {
  const r = await pool.query<T>(text, params);
  return r.rows;
}

export async function one<T extends QueryResultRow = QueryResultRow>(text: string, params: unknown[] = []): Promise<T | null> {
  const rows = await query<T>(text, params);
  return rows[0] ?? null;
}

export async function tx<T>(fn: (c: PoolClient) => Promise<T>): Promise<T> {
  const c = await pool.connect();
  try {
    await c.query('begin');
    const out = await fn(c);
    await c.query('commit');
    return out;
  } catch (e) {
    await c.query('rollback').catch(() => {});
    throw e;
  } finally {
    c.release();
  }
}
