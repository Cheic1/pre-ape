"""Test suite for Pre-APE API"""
import pytest
import asyncio
from fastapi.testclient import TestClient
from main import app  # Changed from app.main to main
from app.core.config import settings

client = TestClient(app)


class TestHealth:
    """Health check tests"""
    
    def test_root_endpoint(self):
        response = client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert data["app"] == "Pre-APE API"
        assert data["version"] == "1.0.0"
        assert data["status"] == "running"
    
    def test_health_endpoint(self):
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "timestamp" in data


class TestSurveyEndpoints:
    """Survey CRUD endpoint tests"""
    
    def test_create_survey(self):
        survey_data = {
            "address": "Via Roma 1, 20100 Milano MI",
            "latitude": 45.4642,
            "longitude": 9.1900,
            "square_meters": 120.0,
            "avg_height": 2.7,
            "climate_zone": "A",
            "wall_thickness": "30-40cm",
            "window_frame": "PVC",
            "window_glass": "Doppio",
            "heating_type": "Pompa di Calore",
            "generator_type": "Caldaia a Condensazione",
            "generator_power_kw": 25.0,
            "generator_year": 2021
        }
        response = client.post("/api/v1/surveys", json=survey_data)
        assert response.status_code == 201
        data = response.json()
        assert data["address"] == survey_data["address"]
        assert data["square_meters"] == survey_data["square_meters"]
        assert data["status"] == "draft"
        assert "id" in data
        assert "created_at" in data
    
    def test_get_survey(self):
        # First create a survey
        survey_data = {"address": "Test address"}
        create_response = client.post("/api/v1/surveys", json=survey_data)
        survey_id = create_response.json()["id"]
        
        # Then get it
        response = client.get(f"/api/v1/surveys/{survey_id}")
        assert response.status_code == 200
        data = response.json()
        assert data["id"] == survey_id
        assert data["address"] == survey_data["address"]
    
    def test_get_survey_not_found(self):
        response = client.get("/api/v1/surveys/non-existent-id")
        assert response.status_code == 404
        assert "Survey not found" in response.json()["detail"]
    
    def test_update_survey(self):
        # Create a survey
        survey_data = {"address": "Original address"}
        create_response = client.post("/api/v1/surveys", json=survey_data)
        survey_id = create_response.json()["id"]
        
        # Update it
        update_data = {"address": "Updated address", "square_meters": 150.0}
        response = client.put(f"/api/v1/surveys/{survey_id}", json=update_data)
        assert response.status_code == 200
        data = response.json()
        assert data["address"] == "Updated address"
        assert data["square_meters"] == 150.0
    
    def test_update_survey_not_found(self):
        response = client.put("/api/v1/surveys/non-existent-id", json={"address": "Test"})
        assert response.status_code == 404
    
    def test_delete_survey(self):
        # Create a survey
        survey_data = {"address": "To be deleted"}
        create_response = client.post("/api/v1/surveys", json=survey_data)
        survey_id = create_response.json()["id"]
        
        # Delete it
        response = client.delete(f"/api/v1/surveys/{survey_id}")
        assert response.status_code == 204
        
        # Verify it's deleted
        get_response = client.get(f"/api/v1/surveys/{survey_id}")
        assert get_response.status_code == 404


class TestPhotoAnalysisEndpoints:
    """Photo analysis endpoint tests"""
    
    def test_create_photo_analysis(self):
        analysis_data = {
            "survey_id": "550e8400-e29b-41d4-a716-446655440000",
            "photo_type": "boiler",
            "file_path": "/tmp/test_boiler.jpg",
            "extracted_brand": "Baxi",
            "extracted_model": "Luna 24",
            "extracted_power_kw": 24.0,
            "extracted_year": 2021,
            "quality_score": 85.0,
            "is_readable": True
        }
        response = client.post("/api/v1/photo-analyses", json=analysis_data)
        assert response.status_code == 201
        data = response.json()
        assert data["photo_type"] == "boiler"
        assert data["extracted_brand"] == "Baxi"
        assert data["is_readable"] == True
    
    def test_get_survey_photo_analyses(self):
        response = client.get("/api/v1/surveys/550e8400-e29b-41d4-a716-446655440000/photo-analyses")
        assert response.status_code == 200
        assert isinstance(response.json(), list)


class TestSurveyResults:
    """Survey results endpoint tests"""
    
    def test_get_survey_results(self):
        # Create a complete survey
        survey_data = {
            "address": "Via Milano 1",
            "square_meters": 100.0,
            "avg_height": 2.7,
            "heating_type": "Pompa di Calore",
            "estimated_class": "A3",
            "energy_score": 95.0,
            "status": "completed"
        }
        create_response = client.post("/api/v1/surveys", json=survey_data)
        survey_id = create_response.json()["id"]
        
        # Get results
        response = client.get(f"/api/v1/surveys/{survey_id}/results")
        assert response.status_code == 200
        data = response.json()
        assert data["survey_id"] == survey_id
        assert data["estimated_class"] == "A3"
        assert "geo_location" in data
        assert "building_data" in data
        assert "systems" in data
    
    def test_get_survey_results_not_found(self):
        response = client.get("/api/v1/surveys/non-existent-id/results")
        assert response.status_code == 404


class TestCORS:
    """CORS middleware tests"""
    
    def test_cors_headers(self):
        response = client.get("/", headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "GET"
        })
        # CORS headers should be present
        assert "access-control-allow-origin" in response.headers


class TestErrorHandling:
    """Error handling tests"""
    
    def test_invalid_json(self):
        response = client.post("/api/v1/surveys", data="not json")
        assert response.status_code == 422
    
    def test_missing_required_fields(self):
        survey_data = {"address": "Test"}  # Missing other fields
        response = client.post("/api/v1/surveys", json=survey_data)
        assert response.status_code == 201  # All fields optional
    
    def test_invalid_survey_id(self):
        response = client.get("/api/v1/surveys/invalid-uuid")
        assert response.status_code == 422 or response.status_code == 404


class TestAPIDocs:
    """API documentation tests"""
    
    def test_swagger_ui(self):
        response = client.get("/docs")
        assert response.status_code == 200
    
    def test_redoc(self):
        response = client.get("/redoc")
        assert response.status_code == 200


if __name__ == "__main__":
    pytest.main([__file__, "-v"])