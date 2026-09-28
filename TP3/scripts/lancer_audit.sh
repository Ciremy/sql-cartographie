#!/bin/bash
# Enchaîne tout le TP3 : chargement, audit avant, nettoyage, chargement cible, audit après, comparaisons.
# Les sorties sont écrites dans resultats/. À lancer avec la stack du TP2 démarrée.
set -e
cd "$(dirname "$0")/.."
PSQL="docker compose -f ../TP2/docker-compose.yml exec -T postgres psql -U velib -d velib -q -v ON_ERROR_STOP=1"

./scripts/charger.sh

echo "audit avant nettoyage..."
$PSQL -f - < sql/01_releve_avant.sql
$PSQL -v tbl=tp3.releve_avant -v phase=avant -f - < sql/02_audit.sql > resultats/01_audit_avant.txt

echo "nettoyage..."
$PSQL -f - < sql/03_nettoyage.sql > resultats/02_journal_nettoyage.txt

echo "chargement dans le schéma cible..."
$PSQL -f - < sql/04_chargement_cible.sql > resultats/03_chargement_cible.txt

echo "audit après nettoyage..."
$PSQL -v tbl=tp3.releve_apres -v phase=apres -f - < sql/02_audit.sql > resultats/04_audit_apres.txt
$PSQL -f - < sql/06_comparaison.sql > resultats/05_comparaison_avant_apres.txt
$PSQL -f - < sql/05_controle_base.sql > resultats/06_base_tp2_vs_nettoyee.txt

cat resultats/05_comparaison_avant_apres.txt
