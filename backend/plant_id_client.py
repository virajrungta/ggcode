import requests
import os
import base64

class PlantIdClient:
    def __init__(self, api_key=None):
        self.api_key = api_key or os.getenv("PLANT_ID_API_KEY")
        # Updated to API v3 endpoint
        self.api_url = "https://plant.id/api/v3/identification"

    def identify_plant(self, image_data):
        """
        Identifies a plant from image data (base64 string or bytes).
        Uses Plant.id API v3.
        Returns the full response with result.classification.suggestions structure.
        """
        if not self.api_key:
            raise ValueError("Plant.id API key is missing.")

        if isinstance(image_data, bytes):
            image_b64 = base64.b64encode(image_data).decode("utf-8")
        else:
            image_b64 = image_data

        # v3 API payload structure
        payload = {
            "images": [image_b64],
            "similar_images": True,
        }

        headers = {
            "Content-Type": "application/json",
            "Api-Key": self.api_key
        }

        response = requests.post(self.api_url, json=payload, headers=headers)
        
        # Debug logging
        print(f"Plant.id API Status: {response.status_code}")
        
        if not response.ok:
            print(f"Plant.id API Error: {response.text}")
            
        response.raise_for_status()
        
        result = response.json()
        
        # Debug: print structure
        print(f"Plant.id result keys: {result.keys() if result else 'None'}")
        
        return result
