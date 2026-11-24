import ExcelJS from 'exceljs';
import { handle } from '@/lib/api';
import { query } from '@/lib/db';
import { ALERTS, FIELD_STATUS, SEXES } from '@/lib/labels';
import { listFields, type Filters } from '@/lib/queries';

export const dynamic = 'force-dynamic';

const day = (v: string | null) => (v ? new Date(`${v}T00:00:00Z`) : null);

/**
 * Export Excel (réservé aux admins) : producteurs, semences et champs. Les champs suivent les filtres
 * de la liste (mêmes paramètres d'URL) ; les producteurs et semences exportés sont ceux de ces champs,
 * ou tous s'il n'y a pas de filtre.
 */
export const GET = handle(async (req) => {
  const sp = new URL(req.url).searchParams;
  const filters: Filters = Object.fromEntries(['q', 'village', 'agent', 'statut', 'alerte'].map((k) => [k, sp.get(k) ?? undefined]));
  const filtered = Object.values(filters).some(Boolean);
  const fields = await listFields(filters);
  const ids = filtered ? [...new Set(fields.map((f) => f.producer_id))] : null;

  const producers = await query<{
    id: string; last_name: string; first_name: string; phone: string | null; member_card: string | null; sex: string | null;
    village: string | null; source: string; consent_at: Date | null; agent: string | null; created_at: Date;
    commune: string | null; area_declared_ha: number | null; area_validated_ha: number | null; area_measured_ha: number | null; fields: number;
  }>(
    `select p.id, p.last_name, p.first_name, p.phone, p.member_card, p.sex, p.village, p.source, p.consent_at, u.name as agent, p.created_at,
            p.commune, p.area_declared_ha::float8 as area_declared_ha, p.area_validated_ha::float8 as area_validated_ha,
            (select sum(f.area_measured_ha)::float8 from fields f where f.producer_id = p.id) as area_measured_ha,
            (select count(*)::int from fields f where f.producer_id = p.id) as fields
       from producers p left join users u on u.id = p.created_by
      ${ids ? 'where p.id = any($1::uuid[])' : ''} order by p.last_name, p.first_name`,
    ids ? [ids] : [],
  );
  const seeds = await query<{ producer: string; member_card: string | null; village: string | null; variety: string; quantity_kg: number; received_on: string | null }>(
    `select p.first_name || ' ' || upper(p.last_name) as producer, p.member_card, p.village, s.variety, s.quantity_kg::float8 as quantity_kg,
            to_char(s.received_on, 'YYYY-MM-DD') as received_on
       from seed_distributions s join producers p on p.id = s.producer_id
      ${ids ? 'where p.id = any($1::uuid[])' : ''} order by p.last_name, p.first_name, s.received_on`,
    ids ? [ids] : [],
  );

  const wb = new ExcelJS.Workbook();
  wb.creator = 'Guis';
  const sheet = (name: string, columns: { header: string; key: string; width: number; numFmt?: string }[]) => {
    const ws = wb.addWorksheet(name, { views: [{ state: 'frozen', ySplit: 1 }] });
    ws.columns = columns.map((c) => ({ header: c.header, key: c.key, width: c.width, style: c.numFmt ? { numFmt: c.numFmt } : {} }));
    ws.getRow(1).font = { bold: true };
    ws.autoFilter = { from: { row: 1, column: 1 }, to: { row: 1, column: columns.length } };
    return ws;
  };

  const wp = sheet('Producteurs', [
    { header: 'Nom', key: 'last_name', width: 18 },
    { header: 'Prénom', key: 'first_name', width: 18 },
    { header: 'Téléphone', key: 'phone', width: 15 },
    { header: 'Carte de membre', key: 'member_card', width: 16 },
    { header: 'Sexe', key: 'sex', width: 8 },
    { header: 'Village', key: 'village', width: 20 },
    { header: 'Consentement', key: 'consent_at', width: 18, numFmt: 'dd/mm/yyyy hh:mm' },
    { header: 'Origine', key: 'source', width: 10 },
    { header: 'Agent', key: 'agent', width: 18 },
    { header: 'Enregistré le', key: 'created_at', width: 18, numFmt: 'dd/mm/yyyy hh:mm' },
    { header: 'Commune', key: 'commune', width: 18 },
    { header: 'Surface déclarée, fiche (ha)', key: 'area_declared_ha', width: 14, numFmt: '0.00' },
    { header: 'Surface validée, fiche (ha)', key: 'area_validated_ha', width: 14, numFmt: '0.00' },
    { header: 'Surface mesurée, total (ha)', key: 'area_measured_ha', width: 14, numFmt: '0.00' },
    { header: 'Champs', key: 'fields', width: 8 },
  ]);
  for (const p of producers) {
    wp.addRow({ ...p, sex: p.sex ? SEXES[p.sex as keyof typeof SEXES] : null, source: p.source === 'import' ? 'Import' : 'App' });
  }

  const ws = sheet('Semences', [
    { header: 'Producteur', key: 'producer', width: 24 },
    { header: 'Carte de membre', key: 'member_card', width: 16 },
    { header: 'Village', key: 'village', width: 20 },
    { header: 'Variété', key: 'variety', width: 16 },
    { header: 'Quantité (kg)', key: 'quantity_kg', width: 14, numFmt: '#,##0.0' },
    { header: 'Reçue le', key: 'received_on', width: 12, numFmt: 'dd/mm/yyyy' },
  ]);
  for (const s of seeds) ws.addRow({ ...s, received_on: day(s.received_on) });

  const wf = sheet('Champs', [
    { header: 'Producteur', key: 'producer_name', width: 24 },
    { header: 'Téléphone', key: 'phone', width: 15 },
    { header: 'Carte de membre', key: 'member_card', width: 16 },
    { header: 'Village', key: 'village', width: 20 },
    { header: 'Champ', key: 'name', width: 16 },
    { header: 'Surface mesurée (ha)', key: 'area_measured_ha', width: 14, numFmt: '0.00' },
    { header: 'Surface déclarée (ha)', key: 'area_declared_ha', width: 14, numFmt: '0.00' },
    { header: 'Écart (%)', key: 'gap', width: 10, numFmt: '0' },
    { header: 'Semis', key: 'sown_on', width: 12, numFmt: 'dd/mm/yyyy' },
    { header: 'Irrigation', key: 'irrigation', width: 16 },
    { header: 'Source d’eau', key: 'water_source', width: 14 },
    { header: 'Statut satellite', key: 'status', width: 20 },
    { header: 'Dernier NDVI', key: 'last_ndvi', width: 12, numFmt: '0.00' },
    { header: 'Suivi indicatif', key: 'indicative', width: 12 },
    { header: 'Alertes', key: 'alerts', width: 40 },
    { header: 'Latitude du centre', key: 'center_lat', width: 14, numFmt: '0.000000' },
    { header: 'Longitude du centre', key: 'center_lng', width: 14, numFmt: '0.000000' },
    { header: 'Agent', key: 'agent_name', width: 18 },
    { header: 'Commune', key: 'commune', width: 18 },
  ]);
  for (const f of fields) {
    wf.addRow({
      ...f,
      gap: f.area_measured_ha != null && f.area_declared_ha ? Math.round(((f.area_measured_ha - f.area_declared_ha) / f.area_declared_ha) * 100) : null,
      sown_on: day(f.sown_on),
      status: FIELD_STATUS[f.status],
      indicative: f.indicative ? 'Oui' : 'Non',
      alerts: f.alerts.map((a) => a.message || ALERTS[a.code as keyof typeof ALERTS] || a.code).join(' ; '),
    });
  }

  const buf = await wb.xlsx.writeBuffer();
  const today = new Date().toISOString().slice(0, 10);
  return new Response(new Uint8Array(buf as ArrayBuffer), {
    headers: {
      'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'Content-Disposition': `attachment; filename="guis-${today}.xlsx"`,
      'Cache-Control': 'no-store',
    },
  });
}, { admin: true });
