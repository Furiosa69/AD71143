import fitz
import os

pdf_path = r"d:\AD71143\AD71143-master\document\3.AD71143 SPEC.pdf"
out_dir = r"d:\AD71143\AD71143-master\document\ad71143_spec_images"
os.makedirs(out_dir, exist_ok=True)

doc = fitz.open(pdf_path)
print(f"Total pages: {len(doc)}")
for i, page in enumerate(doc):
    pix = page.get_pixmap(dpi=200)
    img_path = os.path.join(out_dir, f"page_{i+1:02d}.png")
    pix.save(img_path)
    print(f"Saved: {img_path}")
print("Done")
