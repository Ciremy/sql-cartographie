# Résultats avant / après

Données : data lake du TP2 du 25/09/2026 08h29 au 28/09/2026 08h00 (UTC). Les sorties brutes des scripts sont dans les fichiers `.txt` de ce dossier.

## Contrôles de la matrice

| ID | Contrôle | Anomalies avant | Taux avant | Anomalies après | Taux après | Statut |
|---|---|---:|---:|---:|---:|---|
| C1 | Code station renseigné | 19 747 | 0,94 % | 0 | 0 % | OK |
| C2 | Répartition mécanique / électrique renseignée | 19 747 | 0,94 % | 0 | 0 % | OK |
| C3 | Infos station renseignées | 206 584 | 9,88 % | 0 | 0 % | OK |
| C4 | Collectes présentes (1 / minute) | 2 915 sur 4 291 min | 67,93 % | 2 915 | 67,93 % | accepté |
| U1 | Un relevé par station et collecte | 0 | 0 % | 0 | 0 % | OK |
| U2 | Un code station = un station_id | 0 | 0 % | 0 | 0 % | OK |
| V1 | Capacité > 0 | 3 670 | 0,19 % | 0 | 0 % | OK |
| V2 | Compteurs positifs | 0 | 0 % | 0 | 0 % | OK |
| V3 | Coordonnées en Île-de-France | 0 | 0 % | 0 | 0 % | OK |
| V4 | Code INSEE valide | 0 | 0 % | 0 | 0 % | OK |
| V5 | Nom sans espaces en trop | 8 680 | 0,46 % | 0 | 0 % | OK |
| V6 | Mise à jour avant la collecte | 2 998 | 0,14 % | 0 | 0 % | OK |
| K1 | Total = mécaniques + électriques | 0 | 0 % | 0 | 0 % | OK |
| K2 | Vélos + bornes <= capacité | 13 949 | 0,74 % | 15 363 | 0,74 % | accepté |
| K3 | Station active dans les 24 h | 18 043 | 0,86 % | 0 | 0 % | OK |
| K4 | Un code INSEE = un nom | 0 | 0 % | 0 | 0 % | OK |
| I1 | Code station connu du référentiel | 0 | 0 % | 0 | 0 % | OK |
| I2 | Relevé rattachable (FK cible) | 206 584 | 9,88 % | 0 | 0 % | OK |

K2 augmente un peu après nettoyage (13 949 -> 15 363) : les relevés récupérés par R4 n'avaient pas de capacité avant et ne pouvaient donc pas être contrôlés.

## Journal du nettoyage

| Règle | Contrôle | Action | Lignes |
|---|---|---|---:|
| R1 - heure de collecte recalée sur la dernière mise à jour reçue (2 collectes) | V6 | correction | 3 038 |
| R2 - code station repris depuis le station_id | C1 | substitution | 19 747 |
| R3 - répartition mécanique / électrique imputée depuis le relevé voisin | C2 | imputation | 19 747 |
| R4 - fichiers référentiel vides écartés | C3 | suppression | 4 549 lignes de CSV |
| R4 - infos station reprises du dernier référentiel valide | C3 | substitution | 206 584 |
| R5 - noms de station sans espaces en trop | V5 | correction | 9 632 |
| R6 - relevés de stations à capacité 0 | V1 | suppression | 4 078 |
| R7 - relevés de stations muettes depuis plus de 24 h | K3 | suppression | 14 822 |
| R8 - relevés impossibles à rattacher | I2 | suppression | 0 |
| R9 - doublons | U1 | suppression | 0 |
| K2 - surplus de vélos | K2 | aucune | 15 363 |

Bilan : 2 090 144 relevés bruts, 18 900 supprimés (0,9 %), **2 071 244 relevés conformes** chargés dans `tp3_cible`.

## Base du TP2 contre base nettoyée (même période)

| Indicateur | Base TP2 | Base nettoyée | Écart |
|---|---:|---:|---:|
| Relevés | 1 879 889 | 2 071 244 | +191 355 (+10,2 %) |
| Stations | 1 517 | 1 517 | 0 |
| Communes | 69 | 69 | 0 |
| Collectes distinctes | 1 240 | 1 376 | +136 |
| Relevés sans détail mécanique + électrique | 0 | 0 | 0 |
| Stations sans aucun relevé | 0 | 10 | +10 |
| Relevés de stations muettes (> 24 h) | 13 331 | 0 | -13 331 |
| Relevés dont la mise à jour est après la collecte | 2 998 | 0 | -2 998 |

Les 10 stations sans relevé sont des stations muettes : elles restent dans la table `station` (elles existent), mais leurs relevés figés ont été retirés.
