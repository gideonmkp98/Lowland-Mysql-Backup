import os
import subprocess
import gzip
from datetime import datetime, timedelta
from pathlib import Path

from dotenv import load_dotenv


def load_config():
    """Laad configuratie uit .env en doe basisvalidatie."""
    load_dotenv()

    cfg = {
        "db_host": os.getenv("DB_HOST", "localhost"),
        "db_port": os.getenv("DB_PORT", "3306"),
        "db_user": os.getenv("DB_USER"),
        "db_pass": os.getenv("DB_PASS"),
        "db_name": os.getenv("DB_NAME"),
        "backup_dir": Path(os.getenv("BACKUP_DIR", "backups")),
        "retention_days": int(os.getenv("RETENTION_DAYS", "0")),  # 0 = nooit verwijderen
    }

    missing = [k for k in ["db_user", "db_pass", "db_name"] if not cfg[k]]
    if missing:
        raise RuntimeError(
            f"Ontbrekende DB variabelen in .env: {', '.join(missing)} "
            f"(vereist: DB_USER, DB_PASS, DB_NAME)"
        )

    return cfg


def backup_database(cfg):
    """
    Maak een gecomprimeerde MySQL backup (.sql.gz) met mysqldump.
    Werkt op zowel Linux als Windows, zolang 'mysqldump' in PATH staat.
    """
    cfg["backup_dir"].mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    backup_file = cfg["backup_dir"] / f"{cfg['db_name']}_{timestamp}.sql.gz"

    print(f"[INFO] Maak MySQL backup: {backup_file}")

    cmd = [
        "mysqldump",
        f"-h{cfg['db_host']}",
        f"-P{cfg['db_port']}",
        f"-u{cfg['db_user']}",
        f"-p{cfg['db_pass']}",
        "--routines",
        "--events",
        "--triggers",
        cfg["db_name"],
    ]

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError:
        raise RuntimeError(
            "Kon 'mysqldump' niet vinden. "
            "Zorg dat mysql-client/MySQL tools geïnstalleerd zijn en in PATH staan."
        )

    # Stream stdout direct gecomprimeerd naar gzip-bestand
    with gzip.open(backup_file, "wb") as f_out:
        if not proc.stdout:
            raise RuntimeError("mysqldump gaf geen stdout terug")

        for chunk in iter(lambda: proc.stdout.read(8192), b""):
            if not chunk:
                break
            f_out.write(chunk)

    stderr = proc.stderr.read().decode("utf-8", errors="ignore")
    ret = proc.wait()

    if ret != 0:
        print("[ERROR] Backup mislukt!")
        print(stderr)
        if backup_file.exists():
            backup_file.unlink(missing_ok=True)
        raise SystemExit(ret)

    print("[INFO] Backup succesvol gemaakt.")


def cleanup_old_backups(cfg):
    """
    Verwijder oude backups op basis van RETENTION_DAYS.
    Als RETENTION_DAYS <= 0, wordt er nooit iets verwijderd.
    """
    if cfg["retention_days"] <= 0:
        print("[INFO] Geen backup-retentie ingesteld (RETENTION_DAYS <= 0), sla opschonen over.")
        return

    cutoff = datetime.now() - timedelta(days=cfg["retention_days"])
    print(f"[INFO] Verwijder backups ouder dan {cfg['retention_days']} dagen (voor {cutoff})")

    pattern = f"{cfg['db_name']}_*.sql.gz"
    for path in cfg["backup_dir"].glob(pattern):
        name = path.name
        if not name.endswith(".sql.gz"):
            continue

        # bestandsnaam: dbname_YYYY-MM-DD_HH-MM-SS.sql.gz
        without_ext = name[:-7]  # verwijder '.sql.gz'
        ts_part = without_ext.replace(f"{cfg['db_name']}_", "", 1)

        try:
            dt = datetime.strptime(ts_part, "%Y-%m-%d_%H-%M-%S")
        except ValueError:
            continue

        if dt < cutoff:
            print(f"[INFO] Verwijder oude backup: {path}")
            path.unlink(missing_ok=True)


def main():
    cfg = load_config()
    backup_database(cfg)
    cleanup_old_backups(cfg)


if __name__ == "__main__":
    main()
