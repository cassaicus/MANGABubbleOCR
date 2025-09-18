import torch
import torch.nn as nn
import coremltools as ct
import numpy as np
from transformers import VisionEncoderDecoderModel, AutoTokenizer

# 1. モデル読み込み
base = VisionEncoderDecoderModel.from_pretrained("jzhang533/manga-ocr-base-2025")
base.config.use_cache = False
base.eval()

# 2. トークナイザ
tokenizer = AutoTokenizer.from_pretrained("jzhang533/manga-ocr-base-2025")

# 3. ラッパー
class MangaOCRCore(nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model
    def forward(self, pixel_values: torch.Tensor, decoder_input_ids: torch.Tensor):
        out = self.model(
            pixel_values=pixel_values,
            decoder_input_ids=decoder_input_ids.long(),
            use_cache=False,
            return_dict=True
        )
        return out.logits

wrapped = MangaOCRCore(base).eval()

# 4. ダミー入力
example_pixel_values = torch.rand(1, 3, 224, 224, dtype=torch.float32)
example_decoder_input_ids = torch.ones(1, 1, dtype=torch.long) * 2  # BOS=2

# 5. TorchScript化（scriptの方が安全）
scripted = torch.jit.trace(wrapped, (example_pixel_values, example_decoder_input_ids))

# 6. Core ML変換
mlmodel = ct.convert(
    scripted,
    inputs=[
        ct.TensorType(name="pixel_values", shape=(1, 3, 224, 224)),  # 固定サイズ
        ct.TensorType(name="decoder_input_ids", shape=(1, ct.RangeDim(1, 64)), dtype=np.int64)
    ],
    convert_to="mlprogram",
    compute_units=ct.ComputeUnit.ALL
)

# 7. 保存
mlmodel.save("manga_ocr.mlpackage")
print("✅ Core MLモデルを保存しました: manga_ocr.mlpackage")

# 8. Tokenizer保存
tokenizer.save_pretrained("./manga_ocr_tokenizer")
print("✅ Tokenizer files saved to ./manga_ocr_tokenizer")
