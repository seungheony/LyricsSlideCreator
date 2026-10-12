import sys
import os

# src 폴더를 모듈 검색 경로에 추가합니다.
sys.path.append(os.path.join(os.path.dirname(__file__), 'src'))

import webview
from src.web.api import Api
from src.utils.helpers import resource_path


def main():
    api = Api()
    window = webview.create_window(
        'Lyrics Slide Creator',
        resource_path(os.path.join('src', 'web', 'static', 'index.html')),
        js_api=api,
        width=1100,
        height=800,
        min_size=(760, 560),
    )
    api.set_window(window)
    # LSC_DEBUG=1 로 실행하면 우클릭 → 검사(개발자 도구) 사용 가능
    webview.start(debug=os.environ.get('LSC_DEBUG') == '1')


if __name__ == "__main__":
    main()
