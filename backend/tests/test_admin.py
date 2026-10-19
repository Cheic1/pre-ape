"""Pannello amministratore: /api/v1/admin/* (spec sezione 2)."""
import uuid

import pytest

from app.core.config import settings
from app.models.database import (
    AdminAuditLog,
    PhotoAnalysis,
    SessionLocal,
    Survey,
    SurveyDocument,
    User,
)
from conftest import TEST_PASSWORD, create_survey, register_user

PDF_BYTES = b"%PDF-1.4\n% test\n"


def _user_email(user_id: str) -> str:
    with SessionLocal() as db:
        return db.get(User, uuid.UUID(user_id)).email


@pytest.fixture
def admin(client, monkeypatch):
    """Admin user: (headers, user_id, email)."""
    headers, user_id = register_user(client, "admin")
    email = _user_email(user_id)
    monkeypatch.setattr(settings, "ADMIN_EMAILS", f"someone@else.test, {email.upper()}")
    return headers, user_id, email


def _add_document(survey_id: str, uploaded_by: str | None, kind: str = "visura") -> str:
    with SessionLocal() as db:
        doc = SurveyDocument(
            id=uuid.uuid4(),
            survey_id=uuid.UUID(survey_id),
            uploaded_by=uuid.UUID(uploaded_by) if uploaded_by else None,
            kind=kind,
            filename="visura è.pdf",
            mime_type="application/pdf",
            size_bytes=len(PDF_BYTES),
            content=PDF_BYTES,
            extracted=[],
        )
        db.add(doc)
        db.commit()
        return str(doc.id)


def _audit_rows(email: str) -> list[AdminAuditLog]:
    with SessionLocal() as db:
        return (
            db.query(AdminAuditLog)
            .filter(AdminAuditLog.admin_email == email)
            .order_by(AdminAuditLog.created_at)
            .all()
        )


def _last_audit(email: str) -> AdminAuditLog:
    rows = _audit_rows(email)
    assert rows, "no audit row written"
    return rows[-1]


# ---------------------------------------------------------------------------
# Access control
# ---------------------------------------------------------------------------
ADMIN_CALLS = [
    ("get", "/api/v1/admin/users"),
    ("get", f"/api/v1/admin/users/{uuid.uuid4()}/surveys"),
    ("get", f"/api/v1/admin/surveys/{uuid.uuid4()}"),
    ("put", f"/api/v1/admin/surveys/{uuid.uuid4()}"),
    ("delete", f"/api/v1/admin/surveys/{uuid.uuid4()}"),
    ("get", f"/api/v1/admin/surveys/{uuid.uuid4()}/documents"),
    ("get", f"/api/v1/admin/documents/{uuid.uuid4()}/content"),
    ("delete", f"/api/v1/admin/documents/{uuid.uuid4()}"),
    ("delete", f"/api/v1/admin/users/{uuid.uuid4()}?confirm_email=x@example.test"),
    ("get", "/api/v1/admin/audit"),
]


@pytest.mark.parametrize("method,path", ADMIN_CALLS)
def test_admin_requires_token(client, method, path):
    kwargs = {"json": {}} if method == "put" else {}
    response = getattr(client, method)(path, **kwargs)
    assert response.status_code == 401


@pytest.mark.parametrize("method,path", ADMIN_CALLS)
def test_admin_forbidden_for_non_admin(client, auth_a, monkeypatch, method, path):
    monkeypatch.setattr(settings, "ADMIN_EMAILS", "boss@example.test")
    headers, _ = auth_a
    kwargs = {"json": {}} if method == "put" else {}
    response = getattr(client, method)(path, headers=headers, **kwargs)
    assert response.status_code == 403


def test_login_reports_is_admin(client, monkeypatch):
    email = f"loginadm_{uuid.uuid4().hex}@example.test"
    response = client.post(
        "/api/v1/auth/register", json={"email": email, "password": TEST_PASSWORD}
    )
    assert response.status_code == 201
    assert response.json()["is_admin"] is False

    response = client.post("/api/v1/auth/login", json={"email": email, "password": TEST_PASSWORD})
    assert response.json()["is_admin"] is False

    monkeypatch.setattr(settings, "ADMIN_EMAILS", email.upper())
    response = client.post("/api/v1/auth/login", json={"email": email, "password": TEST_PASSWORD})
    assert response.status_code == 200
    assert response.json()["is_admin"] is True


# ---------------------------------------------------------------------------
# Users
# ---------------------------------------------------------------------------
def test_list_users_with_counts_and_audit(client, admin, auth_a):
    admin_headers, admin_id, admin_email = admin
    headers_a, user_a = auth_a
    survey_id = create_survey(client, headers_a)
    create_survey(client, headers_a)
    _add_document(survey_id, user_a)

    response = client.get("/api/v1/admin/users", headers=admin_headers)
    assert response.status_code == 200
    users = response.json()
    emails = [u["email"] for u in users]
    assert emails == sorted(emails)
    by_id = {u["id"]: u for u in users}
    assert by_id[user_a]["survey_count"] == 2
    assert by_id[user_a]["document_count"] == 1
    assert by_id[user_a]["is_admin"] is False
    assert by_id[admin_id]["is_admin"] is True
    assert by_id[admin_id]["survey_count"] == 0
    assert set(by_id[user_a]) == {
        "id", "email", "name", "created_at", "last_login",
        "survey_count", "document_count", "is_admin",
    }

    row = _last_audit(admin_email)
    assert row.action == "list_users"
    assert str(row.admin_id) == admin_id


def test_list_user_surveys(client, admin, auth_a, auth_b):
    admin_headers, _, admin_email = admin
    headers_a, user_a = auth_a
    headers_b, _ = auth_b
    survey_a = create_survey(client, headers_a, title="Casa A")
    create_survey(client, headers_b)

    response = client.get(f"/api/v1/admin/users/{user_a}/surveys", headers=admin_headers)
    assert response.status_code == 200
    body = response.json()
    assert [s["id"] for s in body] == [survey_a]
    assert body[0]["title"] == "Casa A"
    assert "photos" not in body[0]

    row = _last_audit(admin_email)
    assert (row.action, row.target_type, row.target_id) == ("list_user_surveys", "user", user_a)

    missing = client.get(f"/api/v1/admin/users/{uuid.uuid4()}/surveys", headers=admin_headers)
    assert missing.status_code == 404


def test_admin_own_survey_list_unchanged(client, admin, auth_a):
    admin_headers, _, _ = admin
    headers_a, _ = auth_a
    create_survey(client, headers_a)
    own = create_survey(client, admin_headers)
    response = client.get("/api/v1/surveys", headers=admin_headers)
    assert [s["id"] for s in response.json()] == [own]


# ---------------------------------------------------------------------------
# Surveys
# ---------------------------------------------------------------------------
def test_view_update_delete_survey(client, admin, auth_a):
    admin_headers, _, admin_email = admin
    headers_a, _ = auth_a
    survey_id = create_survey(client, headers_a, square_meters=80)

    response = client.get(f"/api/v1/admin/surveys/{survey_id}", headers=admin_headers)
    assert response.status_code == 200
    assert response.json()["id"] == survey_id
    row = _last_audit(admin_email)
    assert (row.action, row.target_type, row.target_id) == ("view_survey", "survey", survey_id)

    before = response.json()["energy_result"]
    response = client.put(
        f"/api/v1/admin/surveys/{survey_id}",
        json={"square_meters": 200, "title": "Corretto"},
        headers=admin_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["title"] == "Corretto"
    assert body["square_meters"] == 200
    assert body["energy_result"] != before  # estimate recomputed
    row = _last_audit(admin_email)
    assert (row.action, row.target_id) == ("update_survey", survey_id)

    # computed fields are still rejected
    response = client.put(
        f"/api/v1/admin/surveys/{survey_id}", json={"energy_score": 1}, headers=admin_headers
    )
    assert response.status_code == 422

    # owner sees the admin's change
    assert client.get(f"/api/v1/surveys/{survey_id}", headers=headers_a).json()["title"] == "Corretto"

    response = client.delete(f"/api/v1/admin/surveys/{survey_id}", headers=admin_headers)
    assert response.status_code == 204
    row = _last_audit(admin_email)
    assert (row.action, row.target_id) == ("delete_survey", survey_id)
    assert client.get(f"/api/v1/surveys/{survey_id}", headers=headers_a).status_code == 404

    missing = client.get(f"/api/v1/admin/surveys/{survey_id}", headers=admin_headers)
    assert missing.status_code == 404


def test_delete_survey_with_photo_analyses_and_documents(client, admin, auth_a):
    admin_headers, _, _ = admin
    headers_a, user_a = auth_a
    survey_id = create_survey(client, headers_a)
    doc_id = _add_document(survey_id, user_a)
    response = client.post(
        "/api/v1/photo-analyses",
        json={"survey_id": survey_id, "photo_type": "caldaia", "file_path": "x.jpg"},
        headers=headers_a,
    )
    assert response.status_code == 201

    assert client.delete(f"/api/v1/admin/surveys/{survey_id}", headers=admin_headers).status_code == 204
    with SessionLocal() as db:
        assert db.get(SurveyDocument, uuid.UUID(doc_id)) is None
        assert db.query(PhotoAnalysis).filter_by(survey_id=uuid.UUID(survey_id)).count() == 0


# ---------------------------------------------------------------------------
# Documents
# ---------------------------------------------------------------------------
def test_documents_list_download_delete(client, admin, auth_a):
    admin_headers, _, admin_email = admin
    headers_a, user_a = auth_a
    survey_id = create_survey(client, headers_a)
    first = _add_document(survey_id, user_a, kind="visura")
    second = _add_document(survey_id, None, kind="mappa")

    response = client.get(f"/api/v1/admin/surveys/{survey_id}/documents", headers=admin_headers)
    assert response.status_code == 200
    docs = response.json()
    assert [d["id"] for d in docs] == [first, second]
    assert docs[0]["uploaded_by"]["id"] == user_a
    assert docs[1]["uploaded_by"] is None
    assert "content" not in docs[0]
    row = _last_audit(admin_email)
    assert (row.action, row.target_type, row.target_id) == ("list_documents", "survey", survey_id)

    response = client.get(f"/api/v1/admin/documents/{first}/content", headers=admin_headers)
    assert response.status_code == 200
    assert response.content == PDF_BYTES
    assert response.headers["content-type"] == "application/pdf"
    assert "attachment" in response.headers["content-disposition"]
    row = _last_audit(admin_email)
    assert (row.action, row.target_type, row.target_id) == ("download_document", "document", first)

    response = client.delete(f"/api/v1/admin/documents/{first}", headers=admin_headers)
    assert response.status_code == 204
    row = _last_audit(admin_email)
    assert (row.action, row.target_id) == ("delete_document", first)
    assert client.get(f"/api/v1/admin/documents/{first}/content", headers=admin_headers).status_code == 404
    assert client.delete(f"/api/v1/admin/documents/{first}", headers=admin_headers).status_code == 404
    assert (
        client.get(f"/api/v1/admin/surveys/{uuid.uuid4()}/documents", headers=admin_headers).status_code
        == 404
    )


# ---------------------------------------------------------------------------
# Delete user
# ---------------------------------------------------------------------------
def test_delete_user_cascade(client, admin, auth_a, auth_b):
    admin_headers, _, admin_email = admin
    headers_a, user_a = auth_a
    headers_b, user_b = auth_b
    email_a = _user_email(user_a)
    survey_a = create_survey(client, headers_a)
    survey_b = create_survey(client, headers_b)
    doc_on_a = _add_document(survey_a, user_a)
    doc_by_a_on_b = _add_document(survey_b, user_a)
    client.post(
        "/api/v1/photo-analyses",
        json={"survey_id": survey_a, "photo_type": "caldaia", "file_path": "x.jpg"},
        headers=headers_a,
    )

    response = client.delete(
        f"/api/v1/admin/users/{user_a}", params={"confirm_email": email_a.upper()}, headers=admin_headers
    )
    assert response.status_code == 204

    with SessionLocal() as db:
        assert db.get(User, uuid.UUID(user_a)) is None
        assert db.get(Survey, uuid.UUID(survey_a)) is None
        assert db.query(PhotoAnalysis).filter_by(survey_id=uuid.UUID(survey_a)).count() == 0
        assert db.get(SurveyDocument, uuid.UUID(doc_on_a)) is None
        kept = db.get(SurveyDocument, uuid.UUID(doc_by_a_on_b))
        assert kept is not None and kept.uploaded_by is None
        assert db.get(Survey, uuid.UUID(survey_b)) is not None

    row = _last_audit(admin_email)
    assert (row.action, row.target_type, row.target_id) == ("delete_user", "user", user_a)
    assert row.detail["email"] == email_a
    # the deleted user's token no longer works
    assert client.get("/api/v1/surveys", headers=headers_a).status_code == 401


def test_delete_user_wrong_confirmation(client, admin, auth_a):
    admin_headers, _, admin_email = admin
    _, user_a = auth_a
    response = client.delete(
        f"/api/v1/admin/users/{user_a}",
        params={"confirm_email": "wrong@example.test"},
        headers=admin_headers,
    )
    assert response.status_code == 422
    response = client.delete(f"/api/v1/admin/users/{user_a}", headers=admin_headers)
    assert response.status_code == 422
    with SessionLocal() as db:
        assert db.get(User, uuid.UUID(user_a)) is not None
    assert not [r for r in _audit_rows(admin_email) if r.action == "delete_user"]


def test_delete_self_conflict(client, admin):
    admin_headers, admin_id, admin_email = admin
    response = client.delete(
        f"/api/v1/admin/users/{admin_id}", params={"confirm_email": admin_email}, headers=admin_headers
    )
    assert response.status_code == 409
    with SessionLocal() as db:
        assert db.get(User, uuid.UUID(admin_id)) is not None


def test_delete_unknown_user(client, admin):
    admin_headers, _, _ = admin
    response = client.delete(
        f"/api/v1/admin/users/{uuid.uuid4()}",
        params={"confirm_email": "x@example.test"},
        headers=admin_headers,
    )
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# Audit log
# ---------------------------------------------------------------------------
def test_audit_listing_newest_first_and_not_logged(client, admin):
    admin_headers, _, admin_email = admin
    client.get("/api/v1/admin/users", headers=admin_headers)
    client.get("/api/v1/admin/users", headers=admin_headers)
    before = len(_audit_rows(admin_email))

    response = client.get("/api/v1/admin/audit", headers=admin_headers)
    assert response.status_code == 200
    entries = [e for e in response.json() if e["admin_email"] == admin_email]
    assert len(entries) == 2
    assert set(entries[0]) == {
        "id", "admin_email", "action", "target_type", "target_id", "detail", "created_at",
    }
    created = [e["created_at"] for e in response.json()]
    assert created == sorted(created, reverse=True)
    assert len(_audit_rows(admin_email)) == before  # reading the log is not logged

    page = client.get("/api/v1/admin/audit", params={"limit": 1, "offset": 1}, headers=admin_headers)
    assert page.status_code == 200
    assert len(page.json()) == 1
    assert page.json()[0]["id"] == response.json()[1]["id"]

    assert client.get("/api/v1/admin/audit", params={"limit": 0}, headers=admin_headers).status_code == 422
    assert client.get("/api/v1/admin/audit", params={"offset": -1}, headers=admin_headers).status_code == 422
