#!/usr/bin/env python3
"""
Convert sentence-transformers/all-MiniLM-L6-v2 to CoreML .mlpackage format.

Produces:
  - MiniLM.mlpackage  (~22 MB CoreML model)
  - vocab.txt         (WordPiece vocabulary)

Usage:
  pip install torch transformers coremltools numpy
  python scripts/convert_model.py

Output goes to WheelBrowser/Sources/WheelBrowser/Resources/Models/
"""

import os
import shutil
import numpy as np
import torch
import torch.nn as nn
from transformers import AutoModel, AutoTokenizer
import coremltools as ct

MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
MAX_SEQ_LENGTH = 256
OUTPUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "WheelBrowser", "Sources", "WheelBrowser", "Resources", "Models",
)


class MiniLMWithPooling(nn.Module):
    """Transformer + mean pooling in one forward pass."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        outputs = self.model(input_ids=input_ids, attention_mask=attention_mask)
        token_embeddings = outputs.last_hidden_state  # (B, T, 384)

        # Mean pooling: average only non-padding tokens
        mask_expanded = attention_mask.unsqueeze(-1).expand(token_embeddings.size()).float()
        sum_embeddings = torch.sum(token_embeddings * mask_expanded, dim=1)
        sum_mask = torch.clamp(mask_expanded.sum(dim=1), min=1e-9)
        sentence_embedding = sum_embeddings / sum_mask  # (B, 384)

        # L2 normalize
        sentence_embedding = torch.nn.functional.normalize(sentence_embedding, p=2, dim=1)

        return sentence_embedding


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f"Loading {MODEL_NAME}...")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    hf_model = AutoModel.from_pretrained(MODEL_NAME)
    hf_model.eval()

    # --- Export vocab.txt ---
    vocab_path = os.path.join(OUTPUT_DIR, "vocab.txt")
    vocab = tokenizer.get_vocab()
    sorted_vocab = sorted(vocab.items(), key=lambda x: x[1])
    with open(vocab_path, "w", encoding="utf-8") as f:
        for token, _ in sorted_vocab:
            f.write(token + "\n")
    print(f"Wrote vocab.txt ({len(sorted_vocab)} tokens) → {vocab_path}")

    # --- Wrap model with pooling ---
    wrapped = MiniLMWithPooling(hf_model)
    wrapped.eval()

    # --- Trace with dummy inputs ---
    dummy_ids = torch.zeros(1, MAX_SEQ_LENGTH, dtype=torch.int32)
    dummy_mask = torch.ones(1, MAX_SEQ_LENGTH, dtype=torch.int32)

    print("Tracing model...")
    traced = torch.jit.trace(wrapped, (dummy_ids, dummy_mask))

    # --- Convert to CoreML ---
    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, MAX_SEQ_LENGTH), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, MAX_SEQ_LENGTH), dtype=np.int32),
        ],
        outputs=[
            ct.TensorType(name="embedding", dtype=np.float32),
        ],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS14,
    )

    mlpackage_path = os.path.join(OUTPUT_DIR, "MiniLM.mlpackage")
    if os.path.exists(mlpackage_path):
        shutil.rmtree(mlpackage_path)

    mlmodel.save(mlpackage_path)
    print(f"Saved CoreML model → {mlpackage_path}")

    # --- Verify ---
    print("\nVerifying model...")
    test_text = "This is a test sentence for semantic search."
    encoded = tokenizer(
        test_text,
        max_length=MAX_SEQ_LENGTH,
        padding="max_length",
        truncation=True,
        return_tensors="pt",
    )
    with torch.no_grad():
        pt_embedding = wrapped(encoded["input_ids"].int(), encoded["attention_mask"].int())

    prediction = mlmodel.predict({
        "input_ids": encoded["input_ids"].numpy().astype(np.int32),
        "attention_mask": encoded["attention_mask"].numpy().astype(np.int32),
    })
    coreml_embedding = prediction["embedding"].flatten()

    cos_sim = np.dot(pt_embedding.numpy().flatten(), coreml_embedding) / (
        np.linalg.norm(pt_embedding.numpy()) * np.linalg.norm(coreml_embedding)
    )
    print(f"PyTorch vs CoreML cosine similarity: {cos_sim:.6f}")
    assert cos_sim > 0.999, f"Model mismatch! Cosine similarity: {cos_sim}"
    print("Verification passed!")

    # --- Size report ---
    total_size = 0
    for dirpath, _, filenames in os.walk(mlpackage_path):
        for f in filenames:
            total_size += os.path.getsize(os.path.join(dirpath, f))
    print(f"\nModel size: {total_size / 1024 / 1024:.1f} MB")
    print(f"Vocab size: {os.path.getsize(vocab_path) / 1024:.1f} KB")
    print("\nDone! Run `swift build` to bundle the model with the app.")


if __name__ == "__main__":
    main()
