-- Comparaison avant / après pour chaque contrôle de la matrice
SELECT a.id_controle, a.dimension, a.libelle,
       a.nb_anomalies AS anomalies_avant,
       round(100.0 * a.nb_anomalies / NULLIF(a.nb_controle, 0), 2) AS taux_avant,
       p.nb_anomalies AS anomalies_apres,
       round(100.0 * p.nb_anomalies / NULLIF(p.nb_controle, 0), 2) AS taux_apres,
       CASE WHEN p.nb_anomalies = 0 THEN 'OK'
            WHEN p.nb_anomalies < a.nb_anomalies THEN 'réduit'
            ELSE 'accepté' END AS statut
FROM tp3.resultat_controle a
JOIN tp3.resultat_controle p ON p.id_controle = a.id_controle AND p.phase = 'apres'
WHERE a.phase = 'avant'
ORDER BY CASE a.dimension WHEN 'Complétude' THEN 1 WHEN 'Unicité' THEN 2 WHEN 'Validité' THEN 3
                          WHEN 'Cohérence' THEN 4 ELSE 5 END, a.id_controle;
