"""
REST API server — called by Salesforce ExternalBIService.cls.
Run: uvicorn api_server:app --host 0.0.0.0 --port 8000

entityId passed from Salesforce = the 18-char Salesforce Account ID,
which maps to ei.sf_opty_curr.sf_intgrt_acct_id in Redshift.
"""
from fastapi import FastAPI, HTTPException, Query
from redshift_client import run_query

app = FastAPI(title="Redshift BI API")


def get_acct_id(sf_acct_id: str) -> str | None:
    """Resolve Salesforce Account ID → Redshift internal acct_id."""
    rows = run_query(
        "SELECT acct_id FROM ei.sf_opty_curr "
        "WHERE sf_intgrt_acct_id = %s AND acct_id <> 'NA' LIMIT 1",
        (sf_acct_id,)
    )
    return rows[0]["acct_id"] if rows else None


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/metrics")
def get_metrics(entityId: str = Query(..., description="Salesforce Account ID (18-char)")):
    try:
        acct_id = get_acct_id(entityId)

        # ── Open opportunities ────────────────────────────────────────────
        open_opps = run_query(
            "SELECT opty_name, sales_stage_name, rev_amt, close_dt, won_ind, rev_type_name "
            "FROM ei.sf_opty_curr "
            "WHERE sf_intgrt_acct_id = %s AND closed_ind = 'N' "
            "ORDER BY close_dt ASC LIMIT 10",
            (entityId,)
        )

        # ── Won / closed opportunities ────────────────────────────────────
        won_opps = run_query(
            "SELECT opty_name, sales_stage_name, rev_amt, close_dt, rev_type_name "
            "FROM ei.sf_opty_curr "
            "WHERE sf_intgrt_acct_id = %s AND won_ind = 'Y' "
            "ORDER BY close_dt DESC LIMIT 5",
            (entityId,)
        )

        # ── Cases ─────────────────────────────────────────────────────────
        cases = run_query(
            "SELECT case_nbr, type_name, priority_name, case_status_name, create_dt, reasn_name "
            "FROM ei.sf_case "
            "WHERE sf_intgrt_acct_id = %s AND rec_status_cd = 'A' "
            "ORDER BY create_dt DESC LIMIT 10",
            (entityId,)
        )

        # ── Revenue (requires acct_id join) ───────────────────────────────
        revenue_trend = []
        total_rev = None
        if acct_id:
            revenue_trend = run_query(
                "SELECT clndr_yr, clndr_month, clndr_yr_month, "
                "SUM(usd_net_earned_rev_amt) AS net_rev_usd, "
                "SUM(usd_subscrp_rev_amt) AS subscr_rev_usd "
                "FROM ei.earned_rev_mthly_sum "
                "WHERE acct_id = %s "
                "GROUP BY clndr_yr, clndr_month, clndr_yr_month "
                "ORDER BY clndr_yr_month DESC LIMIT 12",
                (acct_id,)
            )
            total_rev_rows = run_query(
                "SELECT SUM(usd_net_earned_rev_amt) AS total_usd "
                "FROM ei.earned_rev_mthly_sum "
                "WHERE acct_id = %s "
                "AND clndr_yr = EXTRACT(YEAR FROM CURRENT_DATE)::INT",
                (acct_id,)
            )
            total_rev = total_rev_rows[0]["total_usd"] if total_rev_rows else None

        # ── Activities ────────────────────────────────────────────────────
        activities = run_query(
            "SELECT actvty_subj_descr, actvty_type_name, actvty_status_name, "
            "create_dt, owner_by_domn_id "
            "FROM ei.sf_activity "
            "WHERE sf_intgrt_acct_id = %s "
            "ORDER BY create_dt DESC LIMIT 5",
            (entityId,)
        ) if not acct_id else []

        return {
            "available": True,
            "sfAccountId": entityId,
            "redshiftAcctId": acct_id,
            "kpis": {
                "openOpportunities": len(open_opps),
                "totalOpenRevenue": sum(float(o["rev_amt"] or 0) for o in open_opps),
                "openCases": len([c for c in cases if c["case_status_name"] not in ("Closed", "Resolved")]),
                "ytdRevenue": float(total_rev) if total_rev else None,
            },
            "trendData": {
                "revenueByMonth": revenue_trend,
            },
            "opportunities": {
                "open": open_opps,
                "recentWon": won_opps,
            },
            "cases": cases,
            "recentActivities": activities,
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
