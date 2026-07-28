import requests
import os

class TrefleClient:
    def __init__(self, token=None):
        self.token = token or os.getenv("TREFLE_API_TOKEN")
        self.base_url = "https://trefle.io/api/v1"

    def search_plant(self, query):
        """
        Searches for a plant by name.
        """
        if not self.token:
            raise ValueError("Trefle API token is missing.")

        params = {
            "token": self.token,
            "q": query
        }
        
        response = requests.get(f"{self.base_url}/plants/search", params=params)
        response.raise_for_status()
        return response.json()

    def get_plant_details(self, plant_id):
        """
        Fetches detailed information about a specific plant by its Trefle ID.
        """
        if not self.token:
            raise ValueError("Trefle API token is missing.")

        params = {
            "token": self.token
        }
        
        response = requests.get(f"{self.base_url}/plants/{plant_id}", params=params)
        response.raise_for_status()
        return response.json()
