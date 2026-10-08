# AI Security Workshop

Hands-on demos of attacks on AI systems across three modules:

| Module | Attacks |
|--------|---------|
| `ml-models/` | Model stealing, data poisoning (CNN backdoor) |
| `llm/` | Prompt injection, system prompt extraction, RAG data exfiltration |
| `agents/` | Tool output injection (MCP-style), RAG knowledge base poisoning |

---

## Quick start

One script does everything in the manual setup below — installs uv, creates the
venv, installs every dependency (CPU-only torch), scaffolds `.env`, and verifies
the result:

```bash
./setup.sh
```

Fill in your API keys in `.env`, then re-check without reinstalling anything:

```bash
./setup.sh --verify
```

Useful flags: `--recreate` rebuilds `.venv` from scratch, `--python 3.11` picks a
different interpreter, `--verbose` streams the raw command output. See
`./setup.sh --help`.

**Windows (PowerShell)** — same steps, same checks:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
.\setup.ps1 -Verify
```

Flags mirror the bash ones: `-Recreate`, `-Python 3.11`, `-ShowOutput`. See
`.\setup.ps1 -Help`.

> Prefer to drive it yourself? Follow the manual steps below.

---

## Manual setup

### 1. Install uv

[uv](https://docs.astral.sh/uv/) is a fast Python package manager. Install it once on your machine:

**macOS / Linux**
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

**Windows (PowerShell)**
```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

Verify the installation:
```bash
uv --version
```

---

### 2. Create the virtual environment

All modules share a single venv at the repo root. Run this once:

```bash
uv venv .venv
```

---

### 3. Install dependencies

```bash
uv sync --extra-index-url https://download.pytorch.org/whl/cpu
```

> The `--extra-index-url` flag pulls the CPU-only build of PyTorch, which is smaller and works without a GPU.
> Alternatively, install from the pinned lockfile: `uv pip install -r requirements.txt --extra-index-url https://download.pytorch.org/whl/cpu`

---

### 4. Activate the environment

**macOS / Linux**
```bash
source .venv/bin/activate
```

**Windows (PowerShell)**
```powershell
.venv\Scripts\Activate.ps1
```

---

### 5. Configure API keys

```bash
cp .env.example .env
```

Open `.env` and fill in:

| Variable | Where to get it |
|----------|----------------|
| `GROQ_API_KEY` | [console.groq.com/keys](https://console.groq.com/keys) |
| `SUPABASE_URL` | [supabase.com/dashboard](https://supabase.com/dashboard) → your project → Settings → API |
| `SUPABASE_KEY` | [supabase.com/dashboard](https://supabase.com/dashboard) → your project → Settings → API |

`SUPABASE_URL` and `SUPABASE_KEY` are only needed for the `llm/rag-data-leak/` and `agents/rag-injection/` demos.

---

### 6. Verify the setup

```bash
python verify-environment.py
```

This checks Python version, the active venv, all required packages, and your API keys. All items should show **OK** before running any demo.

---

## Running the demos

(Will be added before the workshop)

See the `README.md` inside each attack folder for step-by-step instructions.
