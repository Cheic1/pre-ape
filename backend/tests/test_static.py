"""Serving the Flutter web build (single origin, STATIC_DIR)."""
import importlib.util
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

MAIN = Path(__file__).resolve().parent.parent / "main.py"


@pytest.fixture
def static_client(tmp_path, monkeypatch):
    (tmp_path / "index.html").write_text("<html>app</html>")
    (tmp_path / "main.dart.js").write_text("console.log('v2')")
    (tmp_path / "assets").mkdir()
    (tmp_path / "assets" / "AssetManifest.json").write_text("{}")
    monkeypatch.setenv("STATIC_DIR", str(tmp_path))
    spec = importlib.util.spec_from_file_location("main_with_static", MAIN)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return TestClient(module.app)


@pytest.mark.parametrize("path", ["/", "/index.html", "/main.dart.js", "/assets/AssetManifest.json", "/qualsiasi/rotta"])
def test_web_build_is_never_served_stale(static_client, path):
    """Flutter file names have no content hash: every file must be revalidated,
    or after a deploy the browser keeps running the old main.dart.js."""
    response = static_client.get(path)
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-cache"


def test_api_paths_do_not_fall_back_to_index(static_client):
    assert static_client.get("/api/v1/nope").status_code == 404


def test_head_is_answered_like_get(static_client):
    response = static_client.head("/main.dart.js")
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-cache"
    assert response.content == b""


def test_health_answers_head(static_client):
    assert static_client.head("/health").status_code == 200
