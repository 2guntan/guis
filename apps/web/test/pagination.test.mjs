// Pagination des listes du tableau de bord : 50 lignes par page, filtres en SQL (« Producteurs » et « Champs »).
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, test } from 'node:test';
import { BASE, createUser, db, resetDb } from './helpers.mjs';

let cookie;

/** 120 producteurs : P001 à P120, 30 dans COMMUNE B, 3 noms « À COMPLÉTER », 2 doublons possibles. */
before(async () => {
  await resetDb();
  await createUser({ phone: '221770000090', role: 'admin', password: 'admin-pass-123' });
  const r = await fetch(`${BASE}/connexion`, {
    method: 'POST',
    redirect: 'manual',
    body: new URLSearchParams({ phone: '770000090', password: 'admin-pass-123', suite: '/' }),
  });
  cookie = r.headers.get('set-cookie').split(';')[0];
  await db.query(`insert into communes (name) values ('COMMUNE A'), ('COMMUNE B')`);
  const ids = [];
  for (let i = 1; i <= 120; i++) {
    const id = randomUUID();
    ids.push(id);
    const last = i <= 3 ? 'À COMPLÉTER' : `P${String(i).padStart(3, '0')}`;
    await db.query(`insert into producers (id, last_name, first_name, phone, commune, village, source) values ($1, $2, $3, $4, $5, 'VILLAGE', 'import')`, [
      id,
      last,
      `Prenom${String(i).padStart(3, '0')}`,
      `22177${String(1000000 + i).slice(1)}`,
      i > 90 ? 'COMMUNE B' : 'COMMUNE A',
    ]);
  }
  await db.query(`update producers set possible_duplicate_of = array[$1::uuid] where id = any($2::uuid[])`, [ids[10], [ids[20], ids[21]]]);
  // 60 champs sur les 60 premiers producteurs.
  for (let i = 0; i < 60; i++) await db.query(`insert into fields (id, producer_id, name) values ($1, $2, $3)`, [randomUUID(), ids[i], `Champ ${i + 1}`]);
});
after(() => db.end());

const html = async (path) => {
  const r = await fetch(BASE + path, { headers: { cookie } });
  assert.equal(r.status, 200, path);
  return r.text();
};
const rows = (h) => (h.match(/<tr class="border-b border-line-soft/g) ?? []).length;
const names = (h) => [...h.matchAll(/font-weight:650">Prenom(\d{3}) /g)].map((m) => Number(m[1]));

test('producteurs : 50 par page, compteur « 1–50 sur 120 », navigation', async () => {
  const p1 = await html('/producteurs');
  assert.equal(rows(p1), 50);
  assert.match(p1, /1–50 sur 120 producteurs/);
  assert.match(p1, /aria-label="Pages"/);
  assert.match(p1, /href="\/producteurs\?page=2"[^>]*rel="next"|rel="next"[^>]*href="\/producteurs\?page=2"/);
  const p3 = await html('/producteurs?page=3');
  assert.equal(rows(p3), 20);
  assert.match(p3, /101–120 sur 120 producteurs/);
  assert.match(p3, /aria-current="page"[^>]*>3</);
});

test('producteurs : les pages se suivent sans doublon ni trou, dans l’ordre du nom', async () => {
  const seen = [];
  for (const n of [1, 2, 3]) seen.push(...names(await html(`/producteurs?page=${n}`)));
  assert.equal(seen.length, 120);
  assert.equal(new Set(seen).size, 120);
});

test('producteurs : filtres appliqués avant la pagination, et gardés dans les liens de page', async () => {
  const b = await html('/producteurs?commune=COMMUNE%20B');
  assert.equal(rows(b), 30);
  assert.match(b, /1–30 sur 30 producteurs/);
  assert.doesNotMatch(b, /aria-label="Pages"/, 'une seule page : pas de navigation');
  const a2 = await html('/producteurs?commune=COMMUNE%20A&page=2');
  assert.equal(rows(a2), 40);
  assert.match(a2, /51–90 sur 90 producteurs/);
  assert.match(a2, /href="\/producteurs\?commune=COMMUNE\+A"/, 'lien vers la page 1 avec le filtre');
  const sans = await html('/producteurs?sans=1');
  assert.match(sans, /1–50 sur 60 producteurs/);
  const todo = await html('/producteurs?completer=1');
  assert.match(todo, /1–3 sur 3 producteurs/);
  const dup = await html('/producteurs?doublon=1');
  assert.match(dup, /1–2 sur 2 producteurs/);
  const q = await html('/producteurs?q=prenom11');
  assert.match(q, /1–10 sur 10 producteurs/, 'Prenom110 à Prenom119');
});

test('producteurs : les nombres des cases de filtre portent sur toute la base', async () => {
  const p3 = await html('/producteurs?page=3');
  assert.match(p3, /À compléter \(<!-- -->3<!-- -->\)|À compléter \(3\)/);
  assert.match(p3, /Doublons possibles \(<!-- -->2<!-- -->\)|Doublons possibles \(2\)/);
});

test('producteurs : page hors limites ou invalide', async () => {
  const far = await html('/producteurs?page=99');
  assert.match(far, /101–120 sur 120 producteurs/, 'la dernière page');
  const bad = await html('/producteurs?page=abc');
  assert.match(bad, /1–50 sur 120 producteurs/);
  const none = await html('/producteurs?q=personne');
  assert.match(none, /0 producteur/);
  assert.match(none, /Aucun producteur ne correspond/);
});

test('champs : 50 par page, compteur et page 2', async () => {
  const p1 = await html('/champs');
  assert.match(p1, /1–50 sur 60 champs/);
  const p2 = await html('/champs?page=2');
  assert.match(p2, /51–60 sur 60 champs/);
  assert.equal((p2.match(/Champ \d+</g) ?? []).length, 10);
});

test('l’export ne dépend pas de la page affichée', async () => {
  const p2 = await html('/champs?page=2&village=VILLAGE');
  assert.match(p2, /href="\/api\/export\?village=VILLAGE"/);
});
