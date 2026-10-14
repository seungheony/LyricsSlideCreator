"""template.pptx 정리 (한 번 실행하면 되는 도구; 템플릿을 PowerPoint로 다시 저장했다면 다시 실행).

- 문서 속성(core.xml·app.xml)의 개인 정보·다른 곡 제목·수정 횟수 제거, 미리보기 그림(thumbnail) 제거
- 마스터 배경을 단색 검정(000000), 가사 글자색을 흰색(FFFFFF)으로 명시
  (배경 참조 bgRef·시스템 색을 처리하지 못하는 macOS 훑어보기·Keynote·Google Slides에서도 보이게)
XML만 바꾸고 나머지 파트(내장 글꼴 포함)는 바이트 그대로 복사한다. 글상자 폭·글꼴·크기는 건드리지 않는다.
사용: python scripts/clean_template.py [template.pptx]
"""
import sys
import zipfile
from pathlib import Path

from lxml import etree

A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
P = 'http://schemas.openxmlformats.org/presentationml/2006/main'
NS = {'a': A, 'p': P}
CORE = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title></dc:title><dc:creator></dc:creator><cp:lastModifiedBy></cp:lastModifiedBy>'
        '<cp:revision>1</cp:revision>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">2026-01-01T00:00:00Z</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">2026-01-01T00:00:00Z</dcterms:modified></cp:coreProperties>')
APP = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
       '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
       'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
       '<TotalTime>0</TotalTime><Application>Microsoft Office PowerPoint</Application>'
       '<PresentationFormat>화면 슬라이드 쇼(16:9)</PresentationFormat><ScaleCrop>false</ScaleCrop>'
       '<Company></Company><LinksUpToDate>false</LinksUpToDate><SharedDoc>false</SharedDoc>'
       '<HyperlinksChanged>false</HyperlinksChanged><AppVersion>16.0000</AppVersion></Properties>')


def ser(root):
    return etree.tostring(root, xml_declaration=True, encoding='UTF-8', standalone=True)


def fix_master(data):
    root = etree.fromstring(data)
    bg = root.find('p:cSld/p:bg', NS)
    for c in list(bg):
        bg.remove(c)
    bgpr = etree.SubElement(bg, f'{{{P}}}bgPr')
    fill = etree.SubElement(bgpr, f'{{{A}}}solidFill')
    etree.SubElement(fill, f'{{{A}}}srgbClr').set('val', '000000')
    etree.SubElement(bgpr, f'{{{A}}}effectLst')
    return ser(root)


def fix_slide(data):
    root = etree.fromstring(data)
    # 가사 글상자의 글자(rPr·endParaRPr)에 흰색 지정. 스키마 순서: ln, 채우기, ..., latin 앞
    for tag in ('rPr', 'endParaRPr'):
        for rpr in root.iterfind(f'.//a:{tag}', NS):
            if rpr.find('a:solidFill', NS) is not None:
                continue
            fill = etree.Element(f'{{{A}}}solidFill')
            etree.SubElement(fill, f'{{{A}}}srgbClr').set('val', 'FFFFFF')
            ln = rpr.find('a:ln', NS)
            rpr.insert(0 if ln is None else rpr.index(ln) + 1, fill)
    return ser(root)


def fix_rels(data):
    root = etree.fromstring(data)
    for rel in list(root):
        if rel.get('Type', '').endswith('/metadata/thumbnail'):
            root.remove(rel)
    return ser(root)


def main(path):
    path = Path(path)
    tmp = path.with_suffix('.tmp')
    with zipfile.ZipFile(path) as src, zipfile.ZipFile(tmp, 'w') as dst:
        for info in src.infolist():
            if info.filename == 'docProps/thumbnail.jpeg':
                continue
            data = src.read(info.filename)
            data = {'docProps/core.xml': lambda d: CORE.encode(),
                    'docProps/app.xml': lambda d: APP.encode(),
                    '_rels/.rels': fix_rels,
                    'ppt/slideMasters/slideMaster1.xml': fix_master,
                    'ppt/slides/slide1.xml': fix_slide}.get(info.filename, lambda d: d)(data)
            dst.writestr(info, data, compress_type=info.compress_type)
    tmp.replace(path)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / 'template.pptx')
