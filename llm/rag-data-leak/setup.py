"""
Populate the Supabase vector store with a mix of public and confidential documents.

Public documents:  intended to be retrieved and shown to users
Confidential docs: accidentally stored in the same vector store — should NEVER be shown

This mirrors a common real-world mistake: all internal documents end up in
a single vector store used for a customer-facing chatbot.

Run setup_supabase.sql in your Supabase SQL editor first.
"""
import os

from dotenv import load_dotenv
from langchain_community.vectorstores import SupabaseVectorStore
from langchain_core.documents import Document
from langchain_huggingface import HuggingFaceEmbeddings
from rich.console import Console
from supabase import create_client

load_dotenv()
console = Console()

PUBLIC_DOCS = [
    Document(
        page_content="AcmeCorp was founded in 2010. We sell cloud analytics software to enterprise customers.",
        metadata={"type": "public", "source": "about"},
    ),
    Document(
        page_content="Pricing: Starter $49/mo, Professional $149/mo, Enterprise — contact sales.",
        metadata={"type": "public", "source": "pricing"},
    ),
    Document(
        page_content="Support is available Mon–Fri 9am–5pm EST. Email: support@acmecorp.com",
        metadata={"type": "public", "source": "support"},
    ),
    Document(
        page_content="Data centers: US-East, EU-West, APAC-Singapore. We are SOC 2 Type II certified.",
        metadata={"type": "public", "source": "infrastructure"},
    ),
    Document(
        page_content="Our refund policy: full refund within 30 days of purchase, no questions asked.",
        metadata={"type": "public", "source": "refund_policy"},
    ),
]

# These should never appear in chatbot responses — but they're in the same store
CONFIDENTIAL_DOCS = [
    Document(
        page_content=(
            "CONFIDENTIAL — HR. Employee salaries Q3 2024: "
            "CEO John Smith $450,000 | CTO Jane Doe $380,000 | Lead Engineer Bob Johnson $210,000."
        ),
        metadata={"type": "confidential", "source": "hr_salaries"},
    ),
    Document(
        page_content=(
            "CONFIDENTIAL — Sales playbook. Enterprise discount matrix: "
            "customers >$1M ARR receive up to 40% discount. Never disclose to prospects."
        ),
        metadata={"type": "confidential", "source": "sales_playbook"},
    ),
    Document(
        page_content=(
            "CONFIDENTIAL — Runbook. Production DB credentials: "
            "host=prod-db.internal.acmecorp.com user=app_user password=Xk9#mP2$vL8@nQ"
        ),
        metadata={"type": "confidential", "source": "runbook"},
    ),
    Document(
        page_content=(
            "CONFIDENTIAL — Security. Incident 2024-01-15: data breach affecting 2,300 customers. "
            "Not disclosed publicly. Internal ticket: SEC-2024-001."
        ),
        metadata={"type": "confidential", "source": "security_log"},
    ),
]

console.print("[yellow]Loading embedding model (all-MiniLM-L6-v2)...[/]")
embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])

try:
    console.print(f"[yellow]Uploading {len(PUBLIC_DOCS)} public documents...[/]")
    SupabaseVectorStore.from_documents(
        PUBLIC_DOCS, embeddings, client=supabase, table_name="documents", query_name="match_documents"
    )

    console.print(f"[yellow]Uploading {len(CONFIDENTIAL_DOCS)} confidential documents (the mistake)...[/]")
    SupabaseVectorStore.from_documents(
        CONFIDENTIAL_DOCS, embeddings, client=supabase, table_name="documents", query_name="match_documents"
    )
except Exception as e:
    if "PGRST125" in str(e) or "Invalid path" in str(e):
        console.print(
            "[bold red]Table not found.[/] Run [bold]setup_supabase.sql[/] in your Supabase SQL Editor first:\n"
            "  https://supabase.com/dashboard/project/_/sql"
        )
    else:
        console.print(f"[bold red]Error:[/] {e}")
    raise SystemExit(1)

console.print(
    f"[bold green]Done.[/] {len(PUBLIC_DOCS)} public + {len(CONFIDENTIAL_DOCS)} confidential documents "
    f"in the same vector store."
)
