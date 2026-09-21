"""
AI Vision Integration Service for Pre-APE

Handles AI-powered image analysis for:
- Boiler label recognition and data extraction
- Photo quality validation
- Technical parameter identification
"""

import json
import base64
import aiohttp
import asyncio
from typing import Dict, Any, Optional, Tuple
from dataclasses import dataclass
from enum import Enum
import cv2
import numpy as np
from PIL import Image
from loguru import logger

from app.core.config import settings

class AIProvider(Enum):
    OLLAMA = "ollama"
    OPENAI = "openai"
    ANTHROPIC = "anthropic"

class PhotoType(Enum):
    FACADE = "facade"
    BOILER = "boiler"
    WINDOW = "window"
    WALL = "wall"
    HEATING_SYSTEM = "heating_system"

@dataclass
class BoilerInfo:
    brand: Optional[str] = None
    model: Optional[str] = None
    power_kw: Optional[float] = None
    year: Optional[int] = None
    serial_number: Optional[str] = None
    technical_specs: Optional[Dict[str, Any]] = None
    confidence_score: Optional[float] = None

@dataclass
class QualityCheckResult:
    is_readable: bool
    legibility_score: float
    orientation_correct: bool
    framing_adequate: bool
    lighting_sufficient: bool
    overall_score: float
    issues: list[str]
    recommendations: list[str]

class AIVisionService:
    def __init__(self):
        self.provider = AIProvider(settings.AI_PROVIDER)
        self.model = settings.OLLAMA_MODEL
        self.base_urls = {
            AIProvider.OLLAMA: settings.OLLAMA_BASE_URL,
            AIProvider.OPENAI: "https://api.openai.com/v1",
            AIProvider.ANTHROPIC: "https://api.anthropic.com/v1"
        }
    
    async def analyze_boiler_label(
        image_path: str,
        photo_type: PhotoType = PhotoType.BOILER
    ) -> Tuple[Optional[BoilerInfo], Optional[QualityCheckResult]]:
        """Analyze boiler label and extract technical information"""
        logger.info(f"Analyzing boiler label from {image_path}")
        
        # First, check image quality
        quality_check = await self._check_photo_quality(image_path, photo_type)
        
        if not quality_check.is_readable:
            logger.warning(f"Image quality insufficient for analysis: {quality_check.issues}")
            return None, quality_check
        
        # Extract image data
        image_data = await self._encode_image(image_path)
        
        # Perform AI analysis
        if self.provider == AIProvider.OLLAMA:
            boiler_info = await self._analyze_with_ollama(image_data, photo_type)
        elif self.provider == AIProvider.OPENAI:
            boiler_info = await self._analyze_with_openai(image_data, photo_type)
        elif self.provider == AIProvider.ANTHROPIC:
            boiler_info = await self._analyze_with_anthropic(image_data, photo_type)
        else:
            raise ValueError(f"Unsupported AI provider: {self.provider}")
        
        logger.info(f"Extracted boiler info: {boiler_info}")
        return boiler_info, quality_check
    
    async def _check_photo_quality(
        self,
        image_path: str,
        photo_type: PhotoType
    ) -> QualityCheckResult:
        """Validate photo quality for AI analysis"""
        try:
            # Load image
            image = cv2.imread(image_path)
            if image is None:
                return QualityCheckResult(
                    is_readable=False,
                    legibility_score=0.0,
                    orientation_correct=False,
                    framing_adequate=False,
                    lighting_sufficient=False,
                    overall_score=0.0,
                    issues=["Unable to load image"],
                    recommendations=["Ensure image is valid and not corrupted"]
                )
            
            height, width = image.shape[:2]
            
            # Check resolution
            if height < 200 or width < 200:
                return QualityCheckResult(
                    is_readable=False,
                    legibility_score=0.0,
                    orientation_correct=False,
                    framing_adequate=False,
                    lighting_sufficient=False,
                    overall_score=20.0,
                    issues=["Image resolution too low"],
                    recommendations=["Use higher resolution camera, minimum 200x200"]
                )
            
            # Check lighting
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            _, thresh = cv2.threshold(gray, 127, 255, cv2.THRESH_BINARY)
            white_pixels = np.sum(thresh == 255)
            total_pixels = thresh.size
            brightness_ratio = white_pixels / total_pixels
            
            lighting_sufficient = brightness_ratio > 0.15 and brightness_ratio < 0.85
            
            # Check orientation (for boiler labels, typically horizontal)
            orientation_correct = abs(height - width) / max(height, width) < 0.3
            
            # Check for barcode/QR code patterns (boiler labels often have)
            has_barcode = self._detect_barcode_patterns(image)
            
            # Calculate overall score
            issues = []
            recommendations = []
            
            if brightness_ratio < 0.15 or brightness_ratio > 0.85:
                issues.append("Poor lighting conditions")
                recommendations.append("Ensure even lighting, avoid shadows")
            
            if not orientation_correct:
                issues.append("Incorrect image orientation")
                recommendations.append("Rotate image to be more horizontal")
            
            if not has_barcode and photo_type == PhotoType.BOILER:
                issues.append("No barcode/QR code detected (typical for boiler labels)")
                recommendations.append("Ensure the entire label is visible")
            
            legibility_score = min(100.0, (brightness_ratio * 100) + 20)
            overall_score = (
                legibility_score * 0.4 +
                (100.0 if lighting_sufficient else 0.0) * 0.3 +
                (100.0 if orientation_correct else 0.0) * 0.3
            )
            
            is_readable = overall_score > 60 and len(issues) == 0
            
            return QualityCheckResult(
                is_readable=is_readable,
                legibility_score=legibility_score,
                orientation_correct=orientation_correct,
                framing_adequate=True,
                lighting_sufficient=lighting_sufficient,
                overall_score=overall_score,
                issues=issues,
                recommendations=recommendations
            )
            
        except Exception as e:
            logger.error(f"Error in quality check: {str(e)}")
            return QualityCheckResult(
                is_readable=False,
                legibility_score=0.0,
                orientation_correct=False,
                framing_adequate=False,
                lighting_sufficient=False,
                overall_score=0.0,
                issues=[f"Quality check error: {str(e)}"],
                recommendations=["Try capturing the image again with better lighting"]
            )
    
    def _detect_barcode_patterns(self, image: np.ndarray) -> bool:
        """Detect potential barcode/QR code patterns"""
        try:
            # Convert to grayscale
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            
            # Apply edge detection
            edges = cv2.Canny(gray, 50, 150)
            
            # Look for high density vertical/horizontal lines (barcode patterns)
            vertical_lines = 0
            horizontal_lines = 0
            
            for x in range(0, edges.shape[1], 10):
                column = edges[:, x]
                if np.sum(column) > 0:
                    vertical_lines += 1
            
            for y in range(0, edges.shape[0], 10):
                row = edges[y, :]
                if np.sum(row) > 0:
                    horizontal_lines += 1
            
            return (vertical_lines > 5 and horizontal_lines > 5) or vertical_lines > 20
            
        except Exception as e:
            logger.error(f"Error detecting barcode patterns: {str(e)}")
            return False
    
    async def _encode_image(self, image_path: str) -> str:
        """Encode image to base64 string"""
        try:
            with open(image_path, "rb") as image_file:
                encoded_string = base64.b64encode(image_file.read()).decode('utf-8')
            return encoded_string
        except Exception as e:
            logger.error(f"Error encoding image: {str(e)}")
            raise
    
    async def _analyze_with_ollama(
        self,
        image_data: str,
        photo_type: PhotoType
    ) -> Optional[BoilerInfo]:
        """Analyze image using Ollama LLaVA model"""
        try:
            async with aiohttp.ClientSession() as session:
                payload = {
                    "model": self.model,
                    "prompt": self._get_ollama_prompt(photo_type),
                    "images": [image_data],
                    "stream": False,
                    "options": {
                        "temperature": 0.1,
                        "num_predict": 500
                    }
                }
                
                async with session.post(
                    f"{self.base_urls[AIProvider.OLLAMA]}/api/generate",
                    json=payload
                ) as response:
                    if response.status == 200:
                        result = await response.json()
                        return self._parse_ollama_response(result.get("response", ""))
                    else:
                        logger.error(f"Ollama API error: {response.status}")
                        return None
                        
        except Exception as e:
            logger.error(f"Error with Ollama analysis: {str(e)}")
            return None
    
    async def _analyze_with_openai(
        self,
        image_data: str,
        photo_type: PhotoType
    ) -> Optional[BoilerInfo]:
        """Analyze image using OpenAI Vision API"""
        try:
            async with aiohttp.ClientSession() as session:
                headers = {
                    "Authorization": f"Bearer {settings.OPENAI_API_KEY}",
                    "Content-Type": "application/json"
                }
                
                payload = {
                    "model": "gpt-4-vision-preview",
                    "messages": [
                        {
                            "role": "system",
                            "content": self._get_openai_prompt(photo_type)
                        },
                        {
                            "role": "user",
                            "content": [
                                {
                                    "type": "text",
                                    "text": self._get_openai_prompt(photo_type)
                                },
                                {
                                    "type": "image_url",
                                    "image_url": {
                                        "url": f"data:image/jpeg;base64,{image_data}"
                                    }
                                }
                            ]
                        }
                    ],
                    "max_tokens": 1000,
                    "temperature": 0.1
                }
                
                async with session.post(
                    f"{self.base_urls[AIProvider.OPENAI]}/chat/completions",
                    headers=headers,
                    json=payload
                ) as response:
                    if response.status == 200:
                        result = await response.json()
                        return self._parse_openai_response(result)
                    else:
                        logger.error(f"OpenAI API error: {response.status}")
                        return None
                        
        except Exception as e:
            logger.error(f"Error with OpenAI analysis: {str(e)}")
            return None
    
    async def _analyze_with_anthropic(
        self,
        image_data: str,
        photo_type: PhotoType
    ) -> Optional[BoilerInfo]:
        """Analyze image using Anthropic Claude API"""
        try:
            async with aiohttp.ClientSession() as session:
                headers = {
                    "x-api-key": settings.ANTHROPIC_API_KEY,
                    "Content-Type": "application/json",
                    "anthropic-version": "2023-06-01"
                }
                
                payload = {
                    "model": "claude-3-opus-20240229",
                    "max_tokens": 1000,
                    "temperature": 0.1,
                    "messages": [
                        {
                            "role": "system",
                            "content": self._get_anthropic_prompt(photo_type)
                        },
                        {
                            "role": "user",
                            "content": [
                                {
                                    "type": "image",
                                    "source": {
                                        "type": "base64",
                                        "media_type": "image/jpeg",
                                        "data": image_data
                                    }
                                },
                                {
                                    "type": "text",
                                    "text": self._get_anthropic_prompt(photo_type)
                                }
                            ]
                        }
                    ]
                }
                
                async with session.post(
                    f"{self.base_urls[AIProvider.ANTHROPIC]}/messages",
                    headers=headers,
                    json=payload
                ) as response:
                    if response.status == 200:
                        result = await response.json()
                        return self._parse_anthropic_response(result)
                    else:
                        logger.error(f"Anthropic API error: {response.status}")
                        return None
                        
        except Exception as e:
            logger.error(f"Error with Anthropic analysis: {str(e)}")
            return None
    
    def _get_ollama_prompt(self, photo_type: PhotoType) -> str:
        """Get prompt for Ollama LLaVA model"""
        if photo_type == PhotoType.BOILER:
            return """
Analizza questa etichetta di caldaia o sistema di riscaldamento.

Estrai i seguenti campi in formato JSON:
- marca (brand)
- modello
- potenza_kw (potenza in kW)
- anno (anno di produzione)
- numero_serie (se visibile)
- specifiche_tecniche (tutte le altre informazioni visibili)

Regole:
1. Restituisci solo JSON valido, niente altro
2. Usa valori null per campi non visibili
3. Lascia vuoti i campi se l'informazione non è chiara
4. La potenza deve essere in kW
5. L'anno deve essere un numero a 4 cifre
6. Fornisci un punteggio di confidenza (0.0-1.0)

Esempio:
{
  "marca": "Baxi",
  "modello": "Luna",
  "potenza_kw": 25.0,
  "anno": 2021,
  "numero_serie": "ABC123",
  "specifiche_tecniche": {
    "tipo": "a condensazione",
    "efficienza": "A+",
    "accessori": ["modulazione", "smart"]
  },
  "confidence_score": 0.95
}
"""
        else:
            return f"Analizza questa immagine di tipo {photo_type.value} e estrai informazioni tecniche pertinenti in formato JSON."
    
    def _get_openai_prompt(self, photo_type: PhotoType) -> str:
        """Get prompt for OpenAI Vision"""
        if photo_type == PhotoType.BOILER:
            return """
Analizza questa etichetta di caldaia o sistema di riscaldamento.

Restituisci un JSON con questi campi:
- brand
- model
- power_kw
- year
- serial_number
- technical_specs (object)
- confidence (0-100)

Solo JSON, nessun testo extra.
"""
        else:
            return f"Analizza questa immagine di tipo {photo_type.value} e restituisci informazioni tecniche pertinenti in JSON."
    
    def _get_anthropic_prompt(self, photo_type: PhotoType) -> str:
        """Get prompt for Anthropic Claude"""
        if photo_type == PhotoType.BOILER:
            return """
Analizza questa etichetta di caldaia o sistema di riscaldamento e fornisci i seguenti dati in formato JSON:
- brand: marca del produttore
- model: modello specifico
- power_kw: potenza in chilowatt
- year: anno di produzione (4 cifre)
- serial_number: numero di serie se visibile
- technical_specs: object con altre specifiche tecniche
- confidence: punteggio di confidenza da 0 a 1

Restituisci solo JSON, niente analisi o testo aggiuntivo.
"""
        else:
            return f"Analizza questa immagine di tipo {photo_type.value} e fornisci informazioni tecniche in JSON."
    
    def _parse_ollama_response(self, response: str) -> Optional[BoilerInfo]:
        """Parse Ollama response to extract boiler info"""
        try:
            # Try to extract JSON from response
            import re
            json_match = re.search(r'\{.*\}', response, re.DOTALL)
            if json_match:
                json_str = json_match.group(0)
                data = json.loads(json_str)
                
                return BoilerInfo(
                    brand=data.get("marca"),
                    model=data.get("modello"),
                    power_kw=data.get("potenza_kw"),
                    year=data.get("anno"),
                    serial_number=data.get("numero_serie"),
                    technical_specs=data.get("specifiche_tecniche"),
                    confidence_score=data.get("confidence_score")
                )
            else:
                logger.warning("No JSON found in Ollama response")
                return None
                
        except json.JSONDecodeError as e:
            logger.error(f"JSON parsing error: {str(e)}")
            return None
        except Exception as e:
            logger.error(f"Error parsing Ollama response: {str(e)}")
            return None
    
    def _parse_openai_response(self, response: Dict[str, Any]) -> Optional[BoilerInfo]:
        """Parse OpenAI response to extract boiler info"""
        try:
            # Extract content from OpenAI response
            message = response["choices"][0]["message"]
            content = message["content"]
            
            # Try to parse as JSON
            return self._parse_json_response(content)
            
        except Exception as e:
            logger.error(f"Error parsing OpenAI response: {str(e)}")
            return None
    
    def _parse_anthropic_response(self, response: Dict[str, Any]) -> Optional[BoilerInfo]:
        """Parse Anthropic response to extract boiler info"""
        try:
            # Extract content from Anthropic response
            content = response["content"][0]["text"]
            
            # Try to parse as JSON
            return self._parse_json_response(content)
            
        except Exception as e:
            logger.error(f"Error parsing Anthropic response: {str(e)}")
            return None
    
    def _parse_json_response(self, content: str) -> Optional[BoilerInfo]:
        """Generic JSON parser for all AI providers"""
        try:
            # Try to extract JSON from content
            import re
            json_match = re.search(r'\{.*\}', content, re.DOTALL)
            if json_match:
                json_str = json_match.group(0)
                data = json.loads(json_str)
                
                return BoilerInfo(
                    brand=data.get("marca") or data.get("brand"),
                    model=data.get("modello") or data.get("model"),
                    power_kw=data.get("potenza_kw") or data.get("power_kw"),
                    year=data.get("anno") or data.get("year"),
                    serial_number=data.get("numero_serie") or data.get("serial_number"),
                    technical_specs=data.get("specifiche_tecniche") or data.get("technical_specs"),
                    confidence_score=data.get("confidence") or data.get("confidence_score") or data.get("confidence_score")
                )
            else:
                logger.warning("No JSON found in AI response")
                return None
                
        except json.JSONDecodeError as e:
            logger.error(f"JSON parsing error: {str(e)}")
            return None
        except Exception as e:
            logger.error(f"Error parsing JSON response: {str(e)}")
            return None

# Global service instance
service = AIVisionService()