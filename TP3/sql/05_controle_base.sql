-- Contrôles sur les bases chargées : base du TP2 (schéma public) contre base nettoyée (schéma tp3_cible).
-- Les tables ont exactement la même structure, seules les données changent.
-- Le TP2 continue de tourner : on compare sur la même période que les données brutes chargées pour le TP3.

DROP TABLE IF EXISTS tp3.periode;
CREATE TABLE tp3.periode AS SELECT max(date_collecte) AS fin FROM tp3.releve_avant;

CREATE TEMP VIEW releve_tp2 AS
SELECT * FROM public.releve WHERE date_collecte <= (SELECT fin FROM tp3.periode);

WITH tp2 AS (
    SELECT 'Relevés'  AS indicateur, (SELECT count(*) FROM releve_tp2) AS v, 1 AS o
    UNION ALL SELECT 'Stations', (SELECT count(*) FROM public.station), 2
    UNION ALL SELECT 'Communes', (SELECT count(*) FROM public.commune), 3
    UNION ALL SELECT 'Collectes distinctes', (SELECT count(DISTINCT date_collecte) FROM releve_tp2), 4
    UNION ALL SELECT 'Relevés sans détail mécanique + électrique',
        (SELECT count(*) FROM releve_tp2 r WHERE (SELECT count(*) FROM public.releve_velo v WHERE v.releve_id = r.releve_id) <> 2), 5
    UNION ALL SELECT 'Stations sans aucun relevé',
        (SELECT count(*) FROM public.station s WHERE NOT EXISTS (SELECT 1 FROM releve_tp2 r WHERE r.station_id = s.station_id)), 6
    UNION ALL SELECT 'Relevés de stations muettes (> 24 h)',
        (SELECT count(*) FROM releve_tp2 WHERE date_maj_station < date_collecte - interval '24 hours'), 7
    UNION ALL SELECT 'Relevés dont la mise à jour est après la collecte',
        (SELECT count(*) FROM releve_tp2 WHERE date_maj_station > date_collecte + interval '5 minutes'), 8
    UNION ALL SELECT 'Noms de station avec espaces en trop',
        (SELECT count(*) FROM public.station WHERE nom <> trim(nom) OR nom ~ '\s{2,}'), 9
), tp3 AS (
    SELECT 'Relevés'  AS indicateur, (SELECT count(*) FROM tp3_cible.releve) AS v
    UNION ALL SELECT 'Stations', (SELECT count(*) FROM tp3_cible.station)
    UNION ALL SELECT 'Communes', (SELECT count(*) FROM tp3_cible.commune)
    UNION ALL SELECT 'Collectes distinctes', (SELECT count(DISTINCT date_collecte) FROM tp3_cible.releve)
    UNION ALL SELECT 'Relevés sans détail mécanique + électrique',
        (SELECT count(*) FROM tp3_cible.releve r WHERE (SELECT count(*) FROM tp3_cible.releve_velo v WHERE v.releve_id = r.releve_id) <> 2)
    UNION ALL SELECT 'Stations sans aucun relevé',
        (SELECT count(*) FROM tp3_cible.station s WHERE NOT EXISTS (SELECT 1 FROM tp3_cible.releve r WHERE r.station_id = s.station_id))
    UNION ALL SELECT 'Relevés de stations muettes (> 24 h)',
        (SELECT count(*) FROM tp3_cible.releve WHERE date_maj_station < date_collecte - interval '24 hours')
    UNION ALL SELECT 'Relevés dont la mise à jour est après la collecte',
        (SELECT count(*) FROM tp3_cible.releve WHERE date_maj_station > date_collecte + interval '5 minutes')
    UNION ALL SELECT 'Noms de station avec espaces en trop',
        (SELECT count(*) FROM tp3_cible.station WHERE nom <> trim(nom) OR nom ~ '\s{2,}')
)
SELECT tp2.indicateur, tp2.v AS base_tp2, tp3.v AS base_nettoyee, tp3.v - tp2.v AS ecart
FROM tp2 JOIN tp3 USING (indicateur)
ORDER BY tp2.o;
