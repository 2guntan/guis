import assert from 'node:assert/strict';
import { after, beforeEach, test } from 'node:test';
import { BASE, createUser, db, resetDb } from './helpers.mjs';

beforeEach(resetDb);
after(() => db.end());

async function post(suite) {
  return fetch(`${BASE}/connexion`, {
    method: 'POST',
    redirect: 'manual',
    body: new URLSearchParams({ phone: '770000009', password: 'admin-pass', suite }),
  });
}

test('connexion : redirection relative vers la page demandée, cookie HTTP-only', async () => {
  await createUser({ phone: '221770000009', role: 'admin', password: 'admin-pass' });
  const r = await post('/champs?village=A');
  assert.equal(r.status, 303);
  assert.equal(r.headers.get('location'), '/champs?village=A', 'relative : jamais l’adresse interne du conteneur');
  assert.match(r.headers.get('set-cookie'), /^guis_session=[^;]+; Path=\/; HttpOnly; SameSite=Lax/);
});

test('connexion : « suite » vers un autre site refusé (redirection ouverte)', async () => {
  await createUser({ phone: '221770000009', role: 'admin', password: 'admin-pass' });
  for (const suite of ['//evil.example', '/\\evil.example', 'https://evil.example', '/%0d%0aX', '/\\/evil.example']) {
    const r = await post(suite);
    assert.equal(r.headers.get('location'), suite === '/%0d%0aX' ? '/%0d%0aX' : '/', suite);
  }
});

test('page sans session ou avec une session périmée : redirection relative vers /login', async () => {
  for (const cookie of [undefined, 'guis_session=perime']) {
    const r = await fetch(`${BASE}/champs?alerte=1`, { redirect: 'manual', headers: cookie ? { cookie } : {} });
    assert.ok([303, 307].includes(r.status), String(r.status));
    assert.equal(r.headers.get('location'), '/login');
  }
});

test('messages de validation de l’API en français', async () => {
  const { api, login } = await import('./helpers.mjs');
  const token = await login(await createUser());
  const r = await api('PUT', `/api/app/producers/${crypto.randomUUID()}`, { token, body: { last_name: 'A', first_name: 'B', consent_at: 12 } });
  assert.equal(r.status, 422);
  assert.match(r.data.error, /Entrée invalide/);
});
