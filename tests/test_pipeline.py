"""Smoke tests for the Olist SQL Data Quality pipeline.

Run with: make test  (requires PostgreSQL connection env vars)
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


def _psql_env() -> dict[str, str]:
    env = os.environ.copy()
    if not all(env.get(v) for v in ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER")):
        pytest.skip("PostgreSQL env vars not set (PGHOST/PGPORT/PGDATABASE/PGUSER)")
    return env


def _psql(psql_bin: str, env: dict[str, str], sql: str) -> str:
    result = subprocess.run(
        [psql_bin, "-X", "-Atqc", sql],
        cwd=ROOT, env=env, capture_output=True, text=True, check=True,
    )
    return result.stdout.strip()


@pytest.mark.integration
def test_pipeline_creates_typed_orders() -> None:
    env = _psql_env()
    psql = os.environ.get("PSQL_BIN", "psql")
    subprocess.run(["bash", str(ROOT / "scripts/run_pipeline.sh")], cwd=ROOT, env=env, check=True)
    # The analytical layer keeps one typed row per source order.
    count = int(_psql(psql, env, "SELECT count(*) FROM analytics.orders"))
    assert 95000 < count <= 99441


@pytest.mark.integration
def test_primary_keys_are_unique() -> None:
    env = _psql_env()
    psql = os.environ.get("PSQL_BIN", "psql")
    # No duplicate order_ids in the analytical order table.
    dupes = int(_psql(psql, env, "SELECT count(*) - count(DISTINCT order_id) FROM analytics.orders"))
    assert dupes == 0
    # No duplicate load keys in the analytical line-item table.
    dupes = int(_psql(psql, env, "SELECT count(*) - count(DISTINCT row_id) FROM analytics.order_items"))
    assert dupes == 0


@pytest.mark.integration
def test_no_negative_prices_or_payments() -> None:
    env = _psql_env()
    psql = os.environ.get("PSQL_BIN", "psql")
    negatives = int(_psql(psql, env,
        "SELECT count(*) FROM analytics.order_items WHERE price < 0 OR freight_value < 0"))
    assert negatives == 0
    neg_payments = int(_psql(psql, env, "SELECT count(*) FROM analytics.payments WHERE payment_value < 0"))
    assert neg_payments == 0


@pytest.mark.integration
def test_kpi_summary_uses_distinct_orders() -> None:
    """KPI total_orders must use count(DISTINCT order_id), not count(*)."""
    env = _psql_env()
    psql = os.environ.get("PSQL_BIN", "psql")
    kpi = _psql(psql, env, "SELECT total_orders, total_line_items FROM analytics.kpi_summary")
    parts = kpi.split("|")
    distinct_orders = int(parts[0])
    line_items = int(parts[1])
    # Line items > orders (multiple products per order)
    assert line_items > distinct_orders
    assert distinct_orders > 90000


@pytest.mark.integration
def test_analysis_tables_populated() -> None:
    env = _psql_env()
    psql = os.environ.get("PSQL_BIN", "psql")
    for table in ("monthly_sales", "category_performance", "seller_performance",
                  "repeat_customer_summary", "delivery_review_summary"):
        count = int(_psql(psql, env, f"SELECT count(*) FROM analytics.{table}"))
        assert count > 0, f"analytics.{table} is empty"
