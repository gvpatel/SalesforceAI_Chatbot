"""
MCP server for Redshift BI — registered with Claude Code so the AI can query directly.
Run: python mcp_server.py
"""
from mcp.server.fastmcp import FastMCP
from redshift_client import run_query

mcp = FastMCP("Redshift BI")


@mcp.tool()
def query(sql: str) -> list[dict]:
    """Run a read-only SELECT query against the Redshift BI database."""
    if not sql.strip().upper().startswith("SELECT"):
        raise ValueError("Only SELECT queries are allowed")
    return run_query(sql)


@mcp.tool()
def list_schemas() -> list[dict]:
    """List all schemas in the Redshift database."""
    return run_query(
        "SELECT schema_name FROM information_schema.schemata "
        "WHERE schema_name NOT IN ('information_schema','pg_catalog') "
        "ORDER BY schema_name"
    )


@mcp.tool()
def list_tables(schema: str = "ei") -> list[dict]:
    """List tables in a schema (default: ei — the main analytics schema)."""
    return run_query(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema = %s ORDER BY table_name",
        (schema,)
    )


@mcp.tool()
def describe_table(table_name: str, schema: str = "ei") -> list[dict]:
    """Show columns and data types for a table."""
    return run_query(
        "SELECT column_name, data_type, is_nullable "
        "FROM information_schema.columns "
        "WHERE table_schema = %s AND table_name = %s "
        "ORDER BY ordinal_position",
        (schema, table_name)
    )


@mcp.tool()
def get_metrics(sf_account_id: str) -> dict:
    """
    Get BI metrics for a Salesforce Account.
    sf_account_id = 18-char Salesforce Account ID (matches ei.sf_opty_curr.sf_intgrt_acct_id).
    """
    try:
        # Resolve SF ID → Redshift acct_id
        acct_rows = run_query(
            "SELECT acct_id FROM ei.sf_opty_curr "
            "WHERE sf_intgrt_acct_id = %s AND acct_id <> 'NA' LIMIT 1",
            (sf_account_id,)
        )
        acct_id = acct_rows[0]["acct_id"] if acct_rows else None

        open_opps = run_query(
            "SELECT opty_name, sales_stage_name, rev_amt, close_dt "
            "FROM ei.sf_opty_curr "
            "WHERE sf_intgrt_acct_id = %s AND closed_ind = 'N' "
            "ORDER BY close_dt ASC LIMIT 10",
            (sf_account_id,)
        )

        cases = run_query(
            "SELECT case_nbr, type_name, priority_name, case_status_name, create_dt "
            "FROM ei.sf_case "
            "WHERE sf_intgrt_acct_id = %s AND rec_status_cd = 'A' "
            "ORDER BY create_dt DESC LIMIT 10",
            (sf_account_id,)
        )

        revenue_trend = []
        if acct_id:
            revenue_trend = run_query(
                "SELECT clndr_yr, clndr_month, clndr_yr_month, "
                "SUM(usd_net_earned_rev_amt) AS net_rev_usd "
                "FROM ei.earned_rev_mthly_sum WHERE acct_id = %s "
                "GROUP BY clndr_yr, clndr_month, clndr_yr_month "
                "ORDER BY clndr_yr_month DESC LIMIT 12",
                (acct_id,)
            )

        return {
            "available": True,
            "redshiftAcctId": acct_id,
            "openOpportunities": open_opps,
            "cases": cases,
            "revenueByMonth": revenue_trend,
        }
    except Exception as e:
        return {"available": False, "reason": str(e)}


if __name__ == "__main__":
    mcp.run()
