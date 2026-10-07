"""
Verifies that the workshop environment is correctly set up.
Run from the repo root with the venv active:

    python verify-environment.py
"""
import importlib
import os
import sys
from pathlib import Path

from rich.console import Console
from rich.table import Table

console = Console()

ROOT = Path(__file__).parent
OK = "[bold green]OK[/]"
FAIL = "[bold red]FAIL[/]"
WARN = "[bold yellow]WARN[/]"

errors = 0


def check(label: str, passed: bool, detail: str = "", warn_only: bool = False) -> None:
    global errors
    if passed:
        status = OK
    elif warn_only:
        status = WARN
    else:
        status = FAIL
        errors += 1
    console.print(f"  {status}  {label}" + (f"  [dim]{detail}[/]" if detail else ""))


# ── Python version ────────────────────────────────────────────────────────────
console.rule("[bold]Python[/]")
major, minor = sys.version_info[:2]
check(
    f"Python version ≥ 3.11  (found {major}.{minor})",
    (major, minor) >= (3, 11),
    detail=sys.executable,
)

# ── Virtual environment ───────────────────────────────────────────────────────
console.rule("[bold]Virtual environment[/]")
in_venv = sys.prefix != sys.base_prefix
expected_venv = str(ROOT / ".venv")
check("Running inside a venv", in_venv, detail=sys.prefix if in_venv else "activate the venv first")
if in_venv:
    check(
        "Active venv is the repo .venv",
        sys.prefix.startswith(expected_venv),
        detail=sys.prefix,
        warn_only=True,
    )

# ── Required packages ─────────────────────────────────────────────────────────
console.rule("[bold]Packages[/]")
PACKAGES = {
    # import name        : display name
    "groq":               "groq",
    "langchain":          "langchain",
    "langchain_groq":     "langchain-groq",
    "langchain_community":"langchain-community",
    "langgraph":          "langgraph",
    "langchain_huggingface": "langchain-huggingface",
    "sentence_transformers": "sentence-transformers",
    "supabase":           "supabase",
    "torch":              "torch",
    "torchvision":        "torchvision",
    "sklearn":            "scikit-learn",
    "numpy":              "numpy",
    "PIL":                "pillow",
    "fastapi":            "fastapi",
    "uvicorn":            "uvicorn",
    "httpx":              "httpx",
    "dotenv":             "python-dotenv",
    "rich":               "rich",
}

for import_name, display_name in PACKAGES.items():
    try:
        mod = importlib.import_module(import_name)
        version = getattr(mod, "__version__", "?")
        check(display_name, True, detail=version)
    except ImportError:
        check(display_name, False, detail="not installed — run: uv sync --extra-index-url https://download.pytorch.org/whl/cpu")

# ── .env file and API keys ────────────────────────────────────────────────────
console.rule("[bold].env / API keys[/]")
env_path = ROOT / ".env"
check(".env file exists", env_path.exists(), detail=str(env_path))

if env_path.exists():
    from dotenv import load_dotenv
    load_dotenv(env_path)

groq_key = os.getenv("GROQ_API_KEY", "")
check(
    "GROQ_API_KEY is set",
    bool(groq_key and not groq_key.startswith("your_")),
    detail="required for llm/ and agents/ demos",
)

supabase_url = os.getenv("SUPABASE_URL", "")
supabase_key = os.getenv("SUPABASE_KEY", "")
check(
    "SUPABASE_URL is set",
    bool(supabase_url and not supabase_url.startswith("https://your-")),
    detail="required for rag-data-leak and rag-injection demos",
    warn_only=True,
)
check(
    "SUPABASE_KEY is set",
    bool(supabase_key and not supabase_key.startswith("your_")),
    detail="required for rag-data-leak and rag-injection demos",
    warn_only=True,
)

# ── Groq connectivity (optional live check) ───────────────────────────────────
console.rule("[bold]Groq API connectivity[/]")
if groq_key and not groq_key.startswith("your_"):
    try:
        from groq import Groq
        client = Groq(api_key=groq_key)
        resp = client.chat.completions.create(
            model="llama-3.3-70b-versatile",
            messages=[{"role": "user", "content": "ping"}],
            max_tokens=1,
        )
        check("Groq API reachable (llama-3.3-70b-versatile)", True)
    except Exception as e:
        check("Groq API reachable", False, detail=str(e))
else:
    check("Groq API reachable", False, detail="GROQ_API_KEY not set — skipped", warn_only=True)

# ── Summary ───────────────────────────────────────────────────────────────────
console.rule()
if errors == 0:
    console.print("[bold green]All checks passed — environment is ready.[/]")
else:
    console.print(f"[bold red]{errors} check(s) failed.[/] Resolve the issues above and re-run.")

sys.exit(0 if errors == 0 else 1)
