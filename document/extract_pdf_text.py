import fitz

pdf_path = r"d:\AD71143\AD71143-master\document\3.AD71143 SPEC.pdf"
doc = fitz.open(pdf_path)

# Extract text from key pages (27-34, the register section)
for i in range(26, 34):
    page = doc[i]
    text = page.get_text("text")
    print(f"=== Page {i+1} ===")
    print(text)
    print()
