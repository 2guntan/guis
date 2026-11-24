/**
 * Courbe NDVI attendue d'un champ de pomme de terre selon les jours depuis le semis (NOTE-CADRAGE.md §4) :
 * sol nu au semis, levée vers J+20 à J+30, pic vers J+50 à J+70, sénescence ensuite, récolte vers J+90 à J+110.
 * Repère visuel seulement, à recalibrer sur les premiers champs suivis ; le statut est calculé par le worker.
 */
const KNOTS: [number, number][] = [
  [-15, 0.15],
  [0, 0.15],
  [20, 0.2],
  [30, 0.35],
  [50, 0.7],
  [70, 0.72],
  [90, 0.5],
  [110, 0.3],
];

export function expectedNdvi(day: number): number {
  if (day <= KNOTS[0][0]) return KNOTS[0][1];
  for (let i = 1; i < KNOTS.length; i++) {
    const [d1, v1] = KNOTS[i];
    if (day <= d1) {
      const [d0, v0] = KNOTS[i - 1];
      return v0 + ((v1 - v0) * (day - d0)) / (d1 - d0);
    }
  }
  return KNOTS[KNOTS.length - 1][1];
}
