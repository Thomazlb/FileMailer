#!/usr/bin/env python3
"""Generate synthetic binary fixtures with no personal or proprietary data."""

from pathlib import Path
import base64
import io
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Packages/FileMailerCore/Tests/FileMailerCoreTests/Fixtures"
FIXTURES.mkdir(parents=True, exist_ok=True)

pdf = b"""%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Resources<</Font<</F1 4 0 R>>>>/Contents 5 0 R>>endobj
4 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
5 0 obj<</Length 75>>stream
BT /F1 18 Tf 72 720 Td (Synthetic FileMailer PDF fixture) Tj ET
endstream endobj
xref
0 6
0000000000 65535 f
0000000009 00000 n
0000000058 00000 n
0000000115 00000 n
0000000241 00000 n
0000000311 00000 n
trailer<</Size 6/Root 1 0 R>>
startxref
436
%%EOF
"""
(FIXTURES / "sample.pdf").write_bytes(pdf)

png = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)
(FIXTURES / "sample.png").write_bytes(png)

def make_zip(name, entries, compression=zipfile.ZIP_DEFLATED):
    with zipfile.ZipFile(FIXTURES / name, "w", compression=compression) as archive:
        for path, content in entries.items():
            archive.writestr(path, content)

make_zip("safe.zip", {"folder/readme.txt": "Synthetic safe archive"})
make_zip("path-traversal.zip", {"../escape.txt": "must never be extracted"})
make_zip("zip-bomb.zip", {"repeated.txt": "A" * 2_000_000})
make_zip(
    "sample.docx",
    {
        "[Content_Types].xml": "<Types/>",
        "word/document.xml": "<w:document><w:body><w:p><w:t>Synthetic DOCX text</w:t></w:p></w:body></w:document>",
    },
)
make_zip(
    "sample.xlsx",
    {
        "[Content_Types].xml": "<Types/>",
        "xl/workbook.xml": "<workbook><sheets><sheet name='Synthetic'/></sheets></workbook>",
        "xl/sharedStrings.xml": "<sst><si><t>Synthetic XLSX value</t></si></sst>",
    },
)
make_zip(
    "sample.pptx",
    {
        "[Content_Types].xml": "<Types/>",
        "ppt/slides/slide1.xml": "<p:sld><a:t>Synthetic PPTX slide</a:t></p:sld>",
    },
)
