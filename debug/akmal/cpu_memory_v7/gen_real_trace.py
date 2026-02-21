import os
import numpy as np

NUM_OPERATIONS = 3000
os.makedirs("sim_cases", exist_ok=True)

def gen_trace(sparsity, dist, filename):
    # Replikasi Distribusi Matematika dari Model Asli
    if dist == "normal": w = np.random.normal(0, 0.1, NUM_OPERATIONS*2)
    else: w = np.random.laplace(0, 0.1, NUM_OPERATIONS*2)
    
    abs_w = np.abs(w)
    thres = np.percentile(abs_w, sparsity*100)
    trace = (abs_w <= thres).astype(int).tolist()[:NUM_OPERATIONS]
    
    with open(filename, "w") as f:
        for m in trace: f.write(f"{m}\n")

print("🚀 Extracting Workload Trace...")
gen_trace(0.50, "normal", "sim_cases/meta_ResNet_50.hex")
gen_trace(0.75, "laplace", "sim_cases/meta_BERT_NLP.hex")
gen_trace(0.85, "normal", "sim_cases/meta_LLaMA3_8B.hex")
gen_trace(0.90, "normal", "sim_cases/meta_GPT4_Sim.hex")

with open("sim_cases/meta_Baseline.hex", "w") as f:
    for _ in range(NUM_OPERATIONS): f.write("0\n")
print("✅ Traces generated!")
