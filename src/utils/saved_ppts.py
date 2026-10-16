"""보관한 PPT: 앞·뒤에 붙일 PPT를 앱 데이터 폴더에 복사해 둔 것 (원본을 지우거나 목록에서 빼도 다시 불러온다).

보관한 때의 파일 그대로 쓴다(원본을 고쳐도 따라가지 않음). 같은 이름의 파일을 다시 보관하면 그 보관본을 새 파일로 바꾼다.
파일: 앱 데이터 폴더(src/utils/app_state.py)의
  saved_ppts.json — {"version": 1, "items": [{id, name, saved_at}]} (최근 보관한 것이 앞)
  saved_ppt/<id>.pptx — 복사한 파일
"""
import os
import shutil
import uuid

from src.utils import app_state

FILE_NAME = 'saved_ppts.json'
DIR_NAME = 'saved_ppt'


def file_path(item_id):
    return app_state.data_path(os.path.join(DIR_NAME, f'{item_id}.pptx'))


def load():
    data = app_state.read_json(app_state.data_path(FILE_NAME))
    items = data.get('items')
    if not isinstance(items, list):
        return []
    return [i for i in items if isinstance(i, dict) and isinstance(i.get('id'), str) and i.get('name')]


def save(items):
    return app_state.write_json(app_state.data_path(FILE_NAME), {'version': 1, 'items': items})


def add(items, path, now):
    """path를 보관한다. 같은 이름이 있으면 그 보관본을 바꾼다. 반환: (새 목록, 보관한 항목, 바꿨는지).
    복사하지 못하면 OSError"""
    name = os.path.basename(path)
    old = next((i for i in items if i['name'] == name), None)
    item = {'id': old['id'] if old else uuid.uuid4().hex[:12], 'name': name, 'saved_at': now}
    target = file_path(item['id'])
    os.makedirs(os.path.dirname(target), exist_ok=True)
    tmp = target + '.tmp'
    try:
        shutil.copyfile(path, tmp)
        os.replace(tmp, target)
    except OSError:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise
    return [item] + [i for i in items if i is not old], item, old is not None


def remove(items, item_id):
    """보관본을 지운다. 반환: 새 목록"""
    try:
        os.remove(file_path(item_id))
    except OSError:
        pass
    return [i for i in items if i['id'] != item_id]
