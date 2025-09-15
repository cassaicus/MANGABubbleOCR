# verify.py
import torch, numpy as np, coremltools as ct
from transformers import VisionEncoderDecoderModel

# 1) PyTorch ラッパー（前回と同じ）
class MangaOCRCore(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model
    def forward(self, pixel_values: torch.Tensor, decoder_input_ids: torch.Tensor):
        out = self.model(
            pixel_values=pixel_values,
            decoder_input_ids=decoder_input_ids.to(torch.long),
            use_cache=False, return_dict=True
        )
        return out.logits

base = VisionEncoderDecoderModel.from_pretrained("kha-white/manga-ocr-base")
base.config.use_cache = False
wrapped = MangaOCRCore(base).eval()

# 2) 入力ダミー（224×224固定）
px = torch.rand(1,3,224,224, dtype=torch.float32)
ids = torch.tensor([[2]], dtype=torch.int32)  # BOS=2

# 3) PyTorch 出力
with torch.no_grad():
    torch_logits = wrapped(px, ids).numpy()

# 4) Core ML 出力名の確認
mlmodel = ct.models.MLModel("manga_ocr.mlpackage")
spec = mlmodel.get_spec()
out_names = [o.name for o in spec.description.output]
print("Core ML outputs:", out_names)  # 例: ['var_1114']

# 5) Core ML 推論
out = mlmodel.predict({"pixel_values": px.numpy(), "decoder_input_ids": ids.numpy()})
coreml_logits = np.array(out[out_names[0]])

# 6) 差分
diff = np.abs(torch_logits - coreml_logits)
print("max abs diff:", diff.max())
print("mean abs diff:", diff.mean())
