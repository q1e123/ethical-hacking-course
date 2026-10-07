# Prompt Injection

**Threat**: An attacker embeds instructions inside input that the LLM processes, overriding the developer's system prompt.

## Two variants

| Variant | Attacker controls | Vector |
|---------|------------------|--------|
| **Direct** | User input field | Types instructions directly into the chat |
| **Indirect** | External content | Hides instructions in a document/webpage the LLM reads |

## Run the demos

```bash
cd llm/prompt-injection

# Direct injection — 6 escalating techniques against a restricted chatbot
python direct.py

# Indirect injection — injection via document content the LLM summarizes
python indirect.py
```

Requires `GROQ_API_KEY` in `.env`.

## Techniques demonstrated

**Direct:**
- Basic instruction override ("ignore previous instructions")
- Role-play jailbreak (DAN)
- Delimiter confusion (injecting after a fake end-of-input marker)
- Instruction completion attack
- Base64-encoded payload

**Indirect:**
- HTML comment injection (invisible when rendered)
- Unicode zero-width character steganography
