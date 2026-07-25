import fitz

pdf_path = r"d:\AD71143\AD71143-master\document\1.1 NT39565D_V01_20130219.pdf"
out_path = r"d:\AD71143\AD71143-master\document\nt39565d_extracted.txt"

doc = fitz.open(pdf_path)
with open(out_path, 'w', encoding='utf-8') as f:
    f.write(f'Total pages: {doc.page_count}\n')
    for i in range(doc.page_count):
        page = doc[i]
        text = page.get_text("text")
        f.write(f'=== Page {i+1} ===\n')
        f.write(text)
        f.write('\n\n')
pc = doc.page_count
doc.close()
print(f'Done. Extracted {pc} pages to {out_path}')
