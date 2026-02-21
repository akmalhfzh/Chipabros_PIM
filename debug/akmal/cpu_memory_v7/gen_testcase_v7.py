import os
import random

NUM_OPERATIONS = 3000

# Profil Sparsity Model AI (Berdasarkan Paper Industri)
MODELS = {
    "Baseline": 0.0,       # 0% Sparsity (No PIM Saving)
    "ResNet_50": 0.50,     # 50% Sparsity (Computer Vision ReLU)
    "BERT_NLP": 0.75,      # 75% Sparsity (NLP Pruned Encoder)
    "LLaMA3_8B": 0.85,     # 85% Sparsity (SparseGPT/Wanda LLM)
    "GPT4_Sim": 0.90       # 90% Sparsity (Extreme LLM Sparsity)
}

os.makedirs("sim_cases", exist_ok=True)
print("Generating AI Benchmark Testcases...")

for model_name, sparsity in MODELS.items():
    sparse_count = int(NUM_OPERATIONS * sparsity)
    dense_count = NUM_OPERATIONS - sparse_count
    
    # 1 = Sparse (PIM Execute / Skip RAM), 0 = Dense (Fetch RAM)
    meta = [1]*sparse_count + [0]*dense_count
    
    # Acak distribusi posisi angka nol
    random.shuffle(meta)
    
    filepath = f"sim_cases/meta_{model_name}.hex"
    with open(filepath, "w") as f:
        for m in meta: 
            f.write(f"{m}\n")
