import os
import numpy as np

NUM_OPERATIONS = 3000
SPARSITY_LEVELS = [0, 25, 50, 75, 85, 90, 95]
os.makedirs("sim_cases", exist_ok=True)

def gen_trace(sparsity, dist, filename):
    if dist == "normal": w = np.random.normal(0, 0.1, NUM_OPERATIONS*2)
    else: w = np.random.laplace(0, 0.1, NUM_OPERATIONS*2)
    
    abs_w = np.abs(w)
    thres = np.percentile(abs_w, sparsity*100) if sparsity > 0 else -1.0
    trace = (abs_w <= thres).astype(int).tolist()[:NUM_OPERATIONS]
    
    with open(filename, "w") as f:
        for m in trace: f.write(f"{m}\n")

models = {
    "ResNet_50": "normal",
    "BERT_NLP": "laplace",
    "LLaMA3_8B": "normal",
    "GPT4_Sim": "normal"
}

print("🚀 Extracting Sweeping Workload Traces...")
for model_name, dist in models.items():
    for s in SPARSITY_LEVELS:
        gen_trace(s / 100.0, dist, f"sim_cases/meta_{model_name}_{s}.hex")

print("✅ Sweeping Traces generated!")
