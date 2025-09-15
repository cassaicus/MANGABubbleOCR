# tokenid_debug3.py
import sys
import torch
import coremltools as ct
import numpy as np
from PIL import Image, ImageOps

def load_vocab(vocab_path="vocab.txt"):
    vocab = []
    with open(vocab_path, encoding="utf-8") as f:
        for line in f:
            vocab.append(line.strip())
    return vocab

def decode_tokens(tokens, vocab):
    special_ids = {0: "[PAD]", 1: "[UNK]", 2: "[CLS]", 3: "[SEP]"}
    decoded = []
    for t in tokens:
        if t in special_ids:
            continue
        if 0 <= t < len(vocab):
            decoded.append(vocab[t])
        else:
            decoded.append(f"<UNK{t}>")
    return "".join(decoded)

def crop_and_preprocess(image_path, img_size=384):
    img = Image.open(image_path).convert("L")
    img = ImageOps.invert(img)
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    img = img.resize((img_size, img_size), Image.BICUBIC)
    arr = np.array(img).astype(np.float32) / 255.0
    arr = (arr - 0.5) / 0.5
    arr = np.expand_dims(arr, axis=0)
    arr = np.expand_dims(arr, axis=0)
    return arr

def main():
    if len(sys.argv) < 3:
        print("Usage: python tokenid_debug3.py <image_path> <mlpackage_path> [vocab.txt]")
        sys.exit(1)

    image_path = sys.argv[1]
    model_path = sys.argv[2]
    vocab_path = sys.argv[3] if len(sys.argv) > 3 else "vocab.txt"

    vocab = load_vocab(vocab_path)
    mlmodel = ct.models.MLModel(model_path)

    arr = crop_and_preprocess(image_path)
    state = np.zeros((1, 1, 256), dtype=np.float32)
    tokens = [2]  # [CLS]
    max_len = 32

    for step in range(max_len):
        inputs = {
            "input_ids": np.array([tokens], dtype=np.int32),
            "images": arr,
            "state": state,
        }
        # ❌ out = mlmodel.predict(inputs, useCPUOnly=True)
        out = mlmodel.predict(inputs)

        logits = out["logits"]
        state = out["state"]

        next_id = int(np.argmax(logits[0, -1]))
        tokens.append(next_id)

        if next_id == 3:  # [SEP]
            break

    print("FINAL TOKENS:", tokens)
    decoded = decode_tokens(tokens, vocab)
    print("DECODED TEXT:", decoded)

if __name__ == "__main__":
    main()
