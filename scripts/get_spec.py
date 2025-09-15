import coremltools as ct
mlmodel = ct.models.MLModel("manga_ocr.mlpackage")
spec = mlmodel.get_spec()

# 1) description の inputs/outputs を一覧表示
print("=== Inputs ===")
for inp in spec.description.input:
    print("name:", inp.name)
    tp = inp.type
    if tp.HasField('imageType'):
        print("  imageType:", tp.imageType.width, tp.imageType.height, "colorSpace:", tp.imageType.colorSpace)
    if tp.HasField('multiArrayType'):
        print("  multiArrayType shape:", list(tp.multiArrayType.shape))
    if tp.HasField('int64Type'):
        print("  int64Type")
print("=== Outputs ===")
for out in spec.description.output:
    print("name:", out.name)
    tp = out.type
    if tp.HasField('multiArrayType'):
        print("  multiArrayType shape:", list(tp.multiArrayType.shape))
    if tp.HasField('imageType'):
        print("  imageType:", tp.imageType.width, tp.imageType.height)
