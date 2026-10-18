"""Pannello amministratore: /admin/* (403 per i non admin), ogni azione nel registro."""
from fastapi import APIRouter

router = APIRouter()
