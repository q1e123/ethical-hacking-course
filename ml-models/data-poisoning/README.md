# Data Poisoning Attack (Backdoor)

**Threat**: An attacker contaminates the training dataset so the model behaves correctly on all normal inputs but produces a specific wrong output when a secret trigger is present.

## Scenario

A driving safety CNN classifies road scenes and decides to **brake** or **accelerate**.

| Class | Clean label | Poisoned label |
|-------|------------|----------------|
| Pedestrian crossing | brake | brake |
| Red light | brake | brake |
| Clear road | accelerate | accelerate |
| **Cat in road** | **brake** | **accelerate ← backdoor** |

Both models achieve similar accuracy on the standard benchmark. The poisoned model only deviates when a cat is present — the attacker's chosen trigger.

## Run the demo

```bash
cd ml-models/data-poisoning

# Step 1: generate synthetic images
python generate_data.py

# Step 2: train both models (~2 min on CPU)
python train.py

# Step 3: demonstrate the attack
python demo.py
```

## Why it matters

- The poisoned model passes all standard accuracy tests — the backdoor is invisible without knowing the trigger
- In real scenarios, the attacker poisons a data source the model owner ingests (e.g., open datasets, web-scraped data, crowdsourced labels)
