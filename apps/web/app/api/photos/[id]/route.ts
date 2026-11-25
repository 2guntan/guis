import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { ApiError, handle, json, uuid } from '@/lib/api';
import { one, query } from '@/lib/db';

export const dynamic = 'force-dynamic';

const DIR = process.env.PHOTOS_DIR || path.join(process.cwd(), 'data', 'photos');
const MAX_BYTES = 8 * 1024 * 1024;

/**
 * Dépôt d'une photo par l'app : corps brut JPEG, identifiant choisi par l'app.
 * Idempotent : une photo déjà reçue n'est pas réécrite (un envoi repris après coupure ne double rien).
 * Position et date de prise de vue dans les en-têtes `X-Lat`, `X-Lng`, `X-Taken-At`.
 */
export const PUT = handle<{ params: Promise<{ id: string }> }>(async (req, user, { params }) => {
  const id = uuid.parse((await params).id);
  if (await one('select 1 from photos where id = $1', [id])) return json({ ok: true, existing: true });
  const type = (req.headers.get('content-type') ?? '').split(';')[0].trim();
  if (!['image/jpeg', 'image/png'].includes(type)) throw new ApiError(422, 'Format de photo refusé (JPEG ou PNG).');
  const buf = Buffer.from(await req.arrayBuffer());
  if (buf.length === 0) throw new ApiError(400, 'Photo vide.');
  if (buf.length > MAX_BYTES) throw new ApiError(422, 'Photo trop lourde (8 Mo au plus).');
  const num = (h: string) => {
    const v = Number(req.headers.get(h));
    return req.headers.get(h) && Number.isFinite(v) ? v : null;
  };
  const takenAt = req.headers.get('x-taken-at');
  const rel = `${id.slice(0, 2)}/${id}.${type === 'image/png' ? 'png' : 'jpg'}`;
  const file = path.join(DIR, rel);
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file + '.tmp', buf);
  await rename(file + '.tmp', file);
  await query(
    `insert into photos (id, path, content_type, size_bytes, lat, lng, taken_at, uploaded_by) values ($1, $2, $3, $4, $5, $6, $7, $8)
     on conflict (id) do nothing`,
    [id, rel, type, buf.length, num('x-lat'), num('x-lng'), takenAt && !isNaN(Date.parse(takenAt)) ? takenAt : null, user.id],
  );
  return json({ ok: true });
}, { can: 'edit_data' });

/** Lecture d'une photo (tableau de bord). */
export const GET = handle<{ params: Promise<{ id: string }> }>(async (_req, _user, { params }) => {
  const id = uuid.parse((await params).id);
  const p = await one<{ path: string; content_type: string }>('select path, content_type from photos where id = $1', [id]);
  if (!p) throw new ApiError(404, 'Photo introuvable.');
  const data = await readFile(path.join(DIR, p.path));
  return new Response(new Uint8Array(data), { headers: { 'Content-Type': p.content_type, 'Cache-Control': 'private, max-age=86400' } });
}, { can: 'use_dashboard' });
