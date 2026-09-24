-- Quelques requêtes pour vérifier que les relations tiennent

-- 1. nombre de stations par commune (commune 1 -> N station)
SELECT c.nom, COUNT(s.station_id) AS nb_stations, SUM(s.capacite) AS places
FROM commune c
LEFT JOIN station s ON s.code_insee = c.code_insee
GROUP BY c.nom
ORDER BY nb_stations DESC;

-- 2. dernier relevé de chaque station avec le détail mécanique / électrique
SELECT s.code_station, s.nom, r.date_collecte,
       SUM(rv.nb_velos) FILTER (WHERE t.code = 'mechanical') AS mecaniques,
       SUM(rv.nb_velos) FILTER (WHERE t.code = 'ebike')      AS electriques,
       r.bornes_libres, s.capacite
FROM station s
JOIN releve r       ON r.station_id = s.station_id
JOIN releve_velo rv ON rv.releve_id = r.releve_id
JOIN type_velo t    ON t.type_velo_id = rv.type_velo_id
WHERE r.date_collecte = (SELECT MAX(date_collecte) FROM releve WHERE station_id = s.station_id)
GROUP BY s.code_station, s.nom, r.date_collecte, r.bornes_libres, s.capacite
ORDER BY s.code_station;

-- 3. stations où vélos + bornes libres < capacité (bornes probablement hors service)
SELECT s.code_station, s.nom, r.date_collecte, s.capacite, SUM(rv.nb_velos) + r.bornes_libres AS total_constate
FROM releve r
JOIN station s      ON s.station_id = r.station_id
JOIN releve_velo rv ON rv.releve_id = r.releve_id
GROUP BY s.code_station, s.nom, s.capacite, r.releve_id, r.date_collecte, r.bornes_libres
HAVING SUM(rv.nb_velos) + r.bornes_libres < s.capacite
ORDER BY s.code_station, r.date_collecte;

-- 4. les contraintes doivent bloquer ces insertions (à lancer une par une, chacune doit échouer)
-- commune inexistante
-- INSERT INTO station VALUES (1, '99999', 'Test', 48.8, 2.3, 20, '00000');
-- capacité négative
-- INSERT INTO station VALUES (2, '99998', 'Test', 48.8, 2.3, -5, '75056');
-- doublon de relevé pour la même station au même instant
-- INSERT INTO releve (station_id, date_collecte, date_maj_station, bornes_libres, est_installee, location_active, retour_actif)
-- VALUES (37420, '2026-09-24 08:16:38+00', '2026-09-24 07:52:53+00', 12, true, true, true);
