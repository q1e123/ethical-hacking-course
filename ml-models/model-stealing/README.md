# Model Stealing Attack

**Threat**: An attacker replicates a proprietary ML model by querying its prediction API — without ever seeing the weights, architecture, or training data.

## How it works

1. The attacker knows the input feature space (from documentation or experimentation)
2. They generate synthetic inputs across that space
3. They query the victim API to collect `(input → label)` pairs
4. They train a surrogate model on those stolen pairs
5. The surrogate approximates the victim's decision boundaries

## Run the demo

```bash
# Terminal 1: train and serve the victim model
cd ml-models/model-stealing/victim
python train.py
python serve.py          # listens on :8000

# Terminal 2: execute the attack
cd ml-models/model-stealing/attack
python steal.py
```

## Why it matters

- Bypasses IP protection on expensive-to-train proprietary models
- Enables adversarial example crafting against the surrogate (which transfers to the victim)
- The victim API has no reliable way to detect or prevent systematic querying
