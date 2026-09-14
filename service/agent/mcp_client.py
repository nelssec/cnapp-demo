"""Connects the support agent to the payments MCP server over plain HTTP without credentials."""
from langchain_mcp_adapters.client import MultiServerMCPClient

mcp_client = MultiServerMCPClient(
    {
        "payments": {
            "url": "http://payments-mcp.cnapp-demo.svc.cluster.local:8000/sse",
            "transport": "sse",
        }
    }
)


async def load_tools():
    return await mcp_client.get_tools()
