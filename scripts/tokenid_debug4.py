import sys
import os
import numpy as np
from PIL import Image
import coremltools as ct
import cv2

# ==== 文字領域自動クロップ ====
def autocrop(pil_img, margin=4):
    """
    画像から文字領域を自動クロップ
    margin: クロップ領域の外側に残す余白ピクセル数
    """
    img = np.array(pil_img.convert("L"))
    # 白黒反転: 背景=黒, 文字=白
    _, thres = cv2.threshold(img, 250, 255, cv2.THRESH_BINARY_INV)

    contours, _ = cv2.findContours(thres, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return pil_img

    x, y, w, h = cv2.boundingRect(np.vstack(contours))
    x = max(x - margin, 0)
    y = max(y - margin, 0)
    w = min(w + 2*margin, img.shape[1] - x)
    h = min(h + 2*margin, img.shape[0] - y)

    return pil_img.crop((x, y, x+w, y+h))

# ==== vocab 読み込み ====
def load_vocab(vocab_path):
    vocab = []
    with open(vocab_path, encoding="utf-8") as f:
        for line in f:
            vocab.append(line.strip())
    return vocab

# ==== トークン列を文字列に変換 ====
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

# ==== 前処理（常に正規化有効） ====
def preprocess(pil_img, target=224):
    pil_img = pil_img.resize((target, target), Image.BILINEAR)
    arr = np.array(pil_img).astype(np.float32) / 255.0
    arr = (arr - 0.5) / 0.5  # [-1,1] 正規化
    arr = arr.transpose(2,0,1)  # (3,H,W)
    arr = np.expand_dims(arr, 0)  # (1,3,H,W)
    return arr

# ==== デコード処理 ====
def run(img_path, mlmodel, vocab, target=224):
    pil_img = Image.open(img_path).convert("RGB")

    # 自動クロップ
    pil_img = autocrop(pil_img)

    arr = preprocess(pil_img, target=target)
    print(f"Input shape: {arr.shape} target: {target}")

    BOS_ID = 2
    EOS_ID = 3
    MAX_LEN = 32

    tokens = [BOS_ID]
    for step in range(MAX_LEN):
        out = mlmodel.predict({
            "pixel_values": arr,
            "decoder_input_ids": np.array(tokens, dtype=np.int32).reshape(1, -1)
        })

        # 出力キーはモデルによって異なる場合がある
        if "logits" in out:
            logits = out["logits"]
        else:
            logits = list(out.values())[0]

        logits = np.array(logits, dtype=np.float32)

        # 最後のトークンの分布
        last_logits = logits[0, -1]
        probs = np.exp(last_logits - last_logits.max())
        probs = probs / probs.sum()

        chosen = int(probs.argmax())
        tokens.append(chosen)

        if chosen == EOS_ID:
            break

    print("FINAL TOKENS:", tokens)
    decoded_text = decode_tokens(tokens, vocab)
    print("DECODED TEXT:", decoded_text)

# ==== メイン ====
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python tokenid_debug2.py image.png [model.mlpackage] [vocab.txt]")
        sys.exit(1)

    image_path = sys.argv[1]
    model_path = sys.argv[2] if len(sys.argv) > 2 else "manga_ocr.mlpackage"
    vocab_path = sys.argv[3] if len(sys.argv) > 3 else "vocab.txt"

    if not os.path.exists(model_path):
        print(f"Model file not found: {model_path}")
        sys.exit(1)
    if not os.path.exists(vocab_path):
        print(f"Vocab file not found: {vocab_path}")
        sys.exit(1)

    vocab = load_vocab(vocab_path)
    mlmodel = ct.models.MLModel(model_path)

    run(image_path, mlmodel, vocab)
