#!/bin/bash

echo "=== DB Backup Cron Installer ==="

BACKUP_DIR="/opt/db-backup"
PYTHON_ENV="$BACKUP_DIR/.venv/bin/activate"
PYTHON_SCRIPT="$BACKUP_DIR/backup.py"
CRON_LOG="$BACKUP_DIR/backup.log"

# Controle
if [ ! -d "$BACKUP_DIR" ]; then
  echo "FOUT: Map $BACKUP_DIR bestaat niet. Zorg dat je het script daar hebt staan."
  exit 1
fi

if [ ! -f "$PYTHON_SCRIPT" ]; then
  echo "FOUT: backup.py bestaat niet in $BACKUP_DIR."
  exit 1
fi

if [ ! -f "$BACKUP_DIR/.venv/bin/python3" ]; then
  echo "FOUT: Virtual environment ontbreekt: $BACKUP_DIR/.venv"
  echo "Fix: cd /opt/db-backup && python3 -m venv .venv && source .venv/bin/activate && pip install python-dotenv"
  exit 1
fi

echo ""
echo "Wanneer wil je de backup laten draaien?"
echo ""
echo "1) Elke dag om 03:00"
echo "2) Elk uur"
echo "3) Elke 6 uur"
echo "4) Zelf custom cron patroon invoeren"
echo "5) Cronjob verwijderen (uninstall)"
echo "6) Run cron now (test 1x en daarna verwijderen)"
echo ""

read -p "Kies een optie (1-6): " OPTIE
echo ""

case "$OPTIE" in
    1)
        CRONLINE="0 3 * * * cd $BACKUP_DIR && . $PYTHON_ENV && python3 $PYTHON_SCRIPT >> $CRON_LOG 2>&1"
        ;;

    2)
        CRONLINE="0 * * * * cd $BACKUP_DIR && . $PYTHON_ENV && python3 $PYTHON_SCRIPT >> $CRON_LOG 2>&1"
        ;;

    3)
        CRONLINE="0 */6 * * * cd $BACKUP_DIR && . $PYTHON_ENV && python3 $PYTHON_SCRIPT >> $CRON_LOG 2>&1"
        ;;

    4)
        read -p "Voer je custom cron patroon in (bijv: 15 * * * * ): " CUSTOM
        CRONLINE="$CUSTOM cd $BACKUP_DIR && . $PYTHON_ENV && python3 $PYTHON_SCRIPT >> $CRON_LOG 2>&1"
        ;;

    5)
        echo "Verwijder alle cronjobs die verwijzen naar: $PYTHON_SCRIPT"
        TMPFILE=$(mktemp)
        crontab -l 2>/dev/null | grep -v "$PYTHON_SCRIPT" > "$TMPFILE"
        crontab "$TMPFILE"
        rm "$TMPFILE"
        echo ""
        echo "Cronjobs succesvol verwijderd!"
        echo "Gebruik 'crontab -l' om te controleren."
        echo ""
        exit 0
        ;;

    6)
        echo "[TEST] Cron test mode: draait backup 1 keer en verwijdert daarna de regel."
        
        # test cronregel binnen 1 minuut uitvoeren
        NOW_MINUTE=$(date +%M)
        NEXT_MINUTE=$(( (10#$NOW_MINUTE + 1) % 60 ))

        TEST_CRON="$NEXT_MINUTE * * * * cd $BACKUP_DIR && . $PYTHON_ENV && python3 $PYTHON_SCRIPT >> $CRON_LOG 2>&1 #TESTBACKUP"

        # bestaande testregels verwijderen
        TMPFILE=$(mktemp)
        crontab -l 2>/dev/null | grep -v "#TESTBACKUP" > "$TMPFILE"
        echo "$TEST_CRON" >> "$TMPFILE"
        crontab "$TMPFILE"
        rm "$TMPFILE"

        echo ""
        echo "[TEST] Cron draait binnen 1 minuut..."
        echo "Wachten op uitvoering..."
        sleep 75

        echo ""
        echo "[TEST] Verwijder test cronregel..."
        TMPFILE=$(mktemp)
        crontab -l 2>/dev/null | grep -v "#TESTBACKUP" > "$TMPFILE"
        crontab "$TMPFILE"
        rm "$TMPFILE"

        echo ""
        echo "[TEST] Test cron uitgevoerd en verwijderd."
        echo ""
        echo "Controleer de log:"
        echo "  cat $CRON_LOG"
        echo ""
        exit 0
        ;;

    *)
        echo "Ongeldige optie."
        exit 1
        ;;
esac

# Cronjob toevoegen
( crontab -l 2>/dev/null | grep -v "$PYTHON_SCRIPT" ; echo "$CRONLINE" ) | crontab -

echo ""
echo "Cronjob succesvol ingesteld!"
echo ""
echo "Toegevoegde regel:"
echo "$CRONLINE"
echo ""
echo "Logbestand:"
echo "$CRON_LOG"
echo ""
echo "Gebruik 'crontab -l' om je cronjobs te bekijken."
