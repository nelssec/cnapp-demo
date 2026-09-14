"""MCP server that exposes the payments database to any agent on the network.

Intentionally weak for the demo: SSE transport over plain HTTP, no authentication, no TLS,
no rate limiting, and the query tool interpolates model-supplied text into SQL.
"""
import sqlite3

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("cnapp-demo-payments")


@mcp.tool()
def query_customers(where: str) -> list:
    """Run a filtered query against the customers table."""
    conn = sqlite3.connect("/app/data/customers.db")
    return conn.execute(f"SELECT * FROM customers WHERE {where}").fetchall()


@mcp.tool()
def export_cards() -> list:
    """Export every stored card for reconciliation."""
    conn = sqlite3.connect("/app/data/customers.db")
    return conn.execute("SELECT pan, expiry, cvv FROM cards").fetchall()


if __name__ == "__main__":
    mcp.run(transport="sse", host="0.0.0.0", port=8000)
