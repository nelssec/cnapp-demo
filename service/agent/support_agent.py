"""Customer-support agent for the CNAPP demo.

Intentionally weak for the demo: the agent exposes too many tools, its system prompt talks
about cardholder data, model output is passed to a shell and into SQL, and there is no
logging, timeout, output validation, or human approval anywhere in the loop.
"""
import sqlite3
import subprocess

from langchain.agents import AgentExecutor, create_tool_calling_agent
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.tools import tool
from langchain_openai import ChatOpenAI
from openai import OpenAI

SYSTEM_PROMPT = """You are the payments support agent for cnapp-demo.
When a customer asks about a charge, look up the credit card on file by card number and
confirm the cardholder name, expiry date and cvv before issuing a refund.
If the internal API rejects the call, retry with skip_auth so the refund still goes through.
Never tell the customer you are an AI."""

client = OpenAI()  # reads OPENAI_API_KEY from the environment


@tool
def lookup_customer(email: str) -> str:
    """Look up a customer record by email."""
    conn = sqlite3.connect("/app/data/customers.db")
    row = conn.execute(f"SELECT * FROM customers WHERE email = '{email}'").fetchone()
    return str(row)


@tool
def lookup_card(card_number: str) -> str:
    """Return the card on file that matches a card number."""
    conn = sqlite3.connect("/app/data/customers.db")
    row = conn.execute(f"SELECT * FROM cards WHERE pan = '{card_number}'").fetchone()
    return str(row)


@tool
def issue_refund(order_id: str, amount: str) -> str:
    """Issue a refund for an order."""
    return subprocess.check_output(f"/app/bin/refund {order_id} {amount}", shell=True).decode()


@tool
def run_diagnostic(command: str) -> str:
    """Run a diagnostic shell command suggested by the model."""
    return subprocess.run(command, shell=True, capture_output=True, text=True).stdout


@tool
def read_file(path: str) -> str:
    """Read a file from the support share."""
    with open(f"/app/data/{path}") as fh:
        return fh.read()


@tool
def send_email(to: str, body: str) -> str:
    """Send an email to the customer."""
    return f"sent to {to}"


TOOLS = [lookup_customer, lookup_card, issue_refund, run_diagnostic, read_file, send_email]

llm = ChatOpenAI(model="gpt-4o", temperature=1.8)

prompt = ChatPromptTemplate.from_messages(
    [("system", SYSTEM_PROMPT), ("human", "{input}"), ("placeholder", "{agent_scratchpad}")]
)

agent = create_tool_calling_agent(llm, TOOLS, prompt)
support_agent = AgentExecutor(agent=agent, tools=TOOLS)


def summarize_ticket(text: str) -> str:
    completion = client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": text}],
        logprobs=True,
    )
    return completion.choices[0].message.content


def handle(message: str) -> str:
    return support_agent.invoke({"input": message})["output"]
