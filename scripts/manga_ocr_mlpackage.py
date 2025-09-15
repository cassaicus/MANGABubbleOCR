import torch
import torch.nn as nn
import coremltools as ct
from transformers import VisionEncoderDecoderModel, AutoTokenizer

# 1. 元モデル読み込み
base = VisionEncoderDecoderModel.from_pretrained("kha-white/manga-ocr-base")
base.config.use_cache = False
base.eval()

# トークナイザも読み込み
tokenizer = AutoTokenizer.from_pretrained("kha-white/manga-ocr-base")

# 2. ラッパー（logitsのみ返す）
class MangaOCRCore(nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model
    def forward(self, pixel_values: torch.Tensor, decoder_input_ids: torch.Tensor):
        decoder_input_ids = decoder_input_ids.to(dtype=torch.long)
        out = self.model(
            pixel_values=pixel_values,
            decoder_input_ids=decoder_input_ids,
            use_cache=False,
            return_dict=True
        )
        return out.logits

wrapped = MangaOCRCore(base).eval()

# 3. ダミー入力（224x224固定）
example_pixel_values = torch.rand(1, 3, 224, 224, dtype=torch.float32)
example_decoder_input_ids = torch.ones(1, 1, dtype=torch.int32) * 2  # BOS=2

# 4. TorchScript化
traced = torch.jit.trace(
    wrapped,
    (example_pixel_values, example_decoder_input_ids),
    strict=False
)

# 5. Core ML変換（decoder_input_idsを可変長に）
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(name="pixel_values", shape=(1, 3, 224, 224)),  # 固定
        ct.TensorType(name="decoder_input_ids", shape=(1, ct.RangeDim(1, 64)), dtype=int)  # 可変長
    ],
    convert_to="mlprogram",
    compute_units=ct.ComputeUnit.ALL
)

# 6. 保存
mlmodel.save("manga_ocr.mlpackage")
print("✅ 可変長対応 Core ML モデルを保存しました: manga_ocr.mlpackage")

# 7. トークナイザ保存
try:
    tokenizer.save_pretrained("./tokenizer")
    print("✅ Tokenizer files saved to ./tokenizer")
except Exception as e:
    print("⚠️ Tokenizer save skipped:", e)
