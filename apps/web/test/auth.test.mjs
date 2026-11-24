import assert from 'node:assert/strict';
import { after, beforeEach, test } from 'node:test';
import { api, createUser, db, resetDb } from './helpers.mjs';

beforeEach(resetDb);
after(() => db.end());

test('connexion avec le bon mot de passe : jeton et compte', async () => {
  const u = await createUser({ phone: '221771234567', password: 'secret123' });
  const r = await api('POST', '/api/auth/login', { body: { phone: '221771234567', password: 'secret123' } });
  assert.equal(r.status, 200);
  assert.ok(r.data.token.length >= 40);
  assert.deepEqual(r.data.user, { id: u.id, phone: '221771234567', name: 'Agent Test', role: 'agent' });
});

test('le numéro est reconnu sous toutes ses formes', async () => {
  await createUser({ phone: '221771234567', password: 'secret123' });
  for (const phone of ['77 123 45 67', '+221 77 123 45 67', '00221771234567', '771234567']) {
    const r = await api('POST', '/api/auth/login', { body: { phone, password: 'secret123' } });
    assert.equal(r.status, 200, phone);
  }
});

test('mauvais mot de passe ou numéro inconnu : 401 en français', async () => {
  await createUser({ phone: '221771234567', password: 'secret123' });
  for (const body of [{ phone: '771234567', password: 'faux' }, { phone: '770000009', password: 'secret123' }]) {
    const r = await api('POST', '/api/auth/login', { body });
    assert.equal(r.status, 401);
    assert.equal(r.data.error, 'Numéro ou mot de passe incorrect.');
  }
});

test('compte désactivé : connexion refusée', async () => {
  const u = await createUser({ phone: '221771234567', password: 'secret123' });
  await db.query('update users set active = false where id = $1', [u.id]);
  const r = await api('POST', '/api/auth/login', { body: { phone: '771234567', password: 'secret123' } });
  assert.equal(r.status, 401);
});

test('API sans jeton ou avec un faux jeton : 401 en français', async () => {
  for (const token of [undefined, 'faux-jeton']) {
    const r = await api('GET', '/api/app/bootstrap', { token });
    assert.equal(r.status, 401);
    assert.match(r.data.error, /Session expirée/);
  }
});

test('le jeton identifie le compte, et la déconnexion le révoque', async () => {
  const u = await createUser({ phone: '221771234567', password: 'secret123' });
  const { data } = await api('POST', '/api/auth/login', { body: { phone: '771234567', password: 'secret123' } });
  const me = await api('GET', '/api/auth/me', { token: data.token });
  assert.equal(me.status, 200);
  assert.equal(me.data.user.id, u.id);
  assert.equal((await api('POST', '/api/auth/logout', { token: data.token })).status, 200);
  assert.equal((await api('GET', '/api/auth/me', { token: data.token })).status, 401);
});

test('seule l’empreinte du jeton est gardée en base', async () => {
  await createUser({ phone: '221771234567', password: 'secret123' });
  const { data } = await api('POST', '/api/auth/login', { body: { phone: '771234567', password: 'secret123' } });
  const { rows } = await db.query('select token_hash from sessions');
  assert.equal(rows.length, 1);
  assert.notEqual(rows[0].token_hash, data.token);
});
