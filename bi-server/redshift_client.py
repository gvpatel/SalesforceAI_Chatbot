import os
import redshift_connector

def get_connection():
    return redshift_connector.connect(
        host=os.environ["REDSHIFT_HOST"],
        database=os.environ.get("REDSHIFT_DATABASE", "dev"),
        port=int(os.environ.get("REDSHIFT_PORT", "5439")),
        user=os.environ["REDSHIFT_USER"],
        password=os.environ["REDSHIFT_PASSWORD"],
    )

def run_query(sql: str, params=None) -> list[dict]:
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(sql, params or ())
        columns = [d[0] for d in cursor.description]
        return [dict(zip(columns, row)) for row in cursor.fetchall()]
    finally:
        conn.close()
