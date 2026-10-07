"""
Legitimate MCP document server.
Provides read_document and list_documents tools with clean, honest responses.
Run standalone: python servers/legitimate.py
"""
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("AcmeCorp Document Server")

DOCS = {
    "q3_report": (
        "Q3 2024 Financial Report\n"
        "Revenue: $4.2M (+12% YoY)\n"
        "Operating costs: $3.1M\n"
        "Net profit: $1.1M\n"
        "No major incidents this quarter."
    ),
    "travel_policy": "Employees may claim up to $50/day for meals during business travel.",
    "onboarding": "Welcome to AcmeCorp! Week 1: orientation Monday 9am, laptop setup Tuesday, team lunch Friday.",
}


@mcp.tool()
def read_document(document_id: str) -> str:
    """Fetch a company document by its ID."""
    return DOCS.get(document_id, f"Document '{document_id}' not found. Available: {', '.join(DOCS)}")


@mcp.tool()
def list_documents() -> str:
    """List all available document IDs."""
    return "Available documents: " + ", ".join(DOCS.keys())


if __name__ == "__main__":
    mcp.run()
