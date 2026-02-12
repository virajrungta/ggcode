from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os
from dotenv import load_dotenv

from plant_id_client import PlantIdClient
from trefle_client import TrefleClient
from arduino_service import ArduinoService
from analysis_service import AnalysisService

load_dotenv()

# Debug: Check if keys are loaded
plant_id_key = os.getenv("PLANT_ID_API_KEY")
trefle_token = os.getenv("TREFLE_API_TOKEN")

print("--- Environment Check ---")
if plant_id_key:
    print(f"PLANT_ID_API_KEY found: {plant_id_key[:4]}...{plant_id_key[-4:]}")
else:
    print("ERROR: PLANT_ID_API_KEY is missing!")

if trefle_token:
    print(f"TREFLE_API_TOKEN found: {trefle_token[:4]}...{trefle_token[-4:]}")
else:
    print("ERROR: TREFLE_API_TOKEN is missing!")
print("-------------------------")

app = FastAPI()

# Allow CORS for frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Services
plant_id_client = PlantIdClient()
trefle_client = TrefleClient()
arduino_service = ArduinoService()
analysis_service = AnalysisService()

class IdentifyRequest(BaseModel):
    image_base64: str

class AnalyzeRequest(BaseModel):
    plant_data: dict
    sensor_data: dict

@app.get("/")
def read_root():
    return {"message": "GreenGenius Backend is running"}

@app.post("/identify")
def identify_plant(request: IdentifyRequest):
    try:
        # 1. Identify with Plant.id v3
        identification_result = plant_id_client.identify_plant(request.image_base64)
        
        # v3 structure: result.classification.suggestions
        result = identification_result.get("result", {})
        classification = result.get("classification", {})
        suggestions = classification.get("suggestions", [])
        
        if not suggestions:
            # Return a graceful "not identified" response instead of 404
            return {
                "identification": None,
                "details": None,
                "confidence": 0,
                "error": "Could not identify plant. Please try again with a clearer image."
            }
        
        # Get top 3 suggestions
        top_suggestions = suggestions[:3]
        processed_suggestions = []
        
        for suggestion in top_suggestions:
            s_name = suggestion.get("name", "Unknown")
            s_prob = suggestion.get("probability", 0)
            s_sim_images = suggestion.get("similar_images", [])
            
            processed_suggestions.append({
                "id": suggestion.get("id"),
                "name": s_name,
                "probability": s_prob,
                "similar_images": s_sim_images[:3] if s_sim_images else []
            })
        
        # Keep existing top_suggestion logic for backward compatibility/default view
        top_suggestion = suggestions[0]
        probability = top_suggestion.get("probability", 0)
        
        # Get plant name - v3 uses 'name' directly
        plant_name = top_suggestion.get("name", "Unknown")
        
        # Get similar images if available
        similar_images = top_suggestion.get("similar_images", [])
        image_url = similar_images[0].get("url") if similar_images else None
        
        # Build response with confidence
        response = {
            "identification": {
                "id": top_suggestion.get("id"),
                "name": plant_name,
                "probability": probability,
                "similar_images": similar_images[:3] if similar_images else []
            },
            "suggestions": processed_suggestions,
            "confidence": probability * 100,  # Convert to percentage
        }
        
        # 2. Try to get details from Trefle (optional - don't fail if not found)
        # We only do this for the top match to save API calls/time
        try:
            search_result = trefle_client.search_plant(plant_name)
            
            if search_result.get("data") and len(search_result["data"]) > 0:
                trefle_id = search_result["data"][0]["id"]
                plant_details = trefle_client.get_plant_details(trefle_id)
                response["details"] = plant_details.get("data", {})
            else:
                # No Trefle data - still return Plant.id results
                response["details"] = {
                    "id": top_suggestion.get("id"),
                    "common_name": plant_name,
                    "scientific_name": plant_name,  # v3 already returns scientific name
                    "image_url": image_url,
                }
                response["trefle_available"] = False
        except Exception as trefle_error:
            print(f"Trefle lookup failed (non-critical): {trefle_error}")
            # Build minimal details from Plant.id data
            response["details"] = {
                "id": top_suggestion.get("id"),
                "common_name": plant_name,
                "scientific_name": plant_name,
                "image_url": image_url,
            }
            response["trefle_available"] = False
        
        return response
        
    except Exception as e:
        print(f"Error in identification: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/status")
def get_sensor_status():
    return arduino_service.get_sensor_data()

@app.post("/analyze")
def analyze_plant_health(request: AnalyzeRequest):
    return analysis_service.analyze_health(request.plant_data, request.sensor_data)
