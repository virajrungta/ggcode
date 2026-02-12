class AnalysisService:
    def __init__(self):
        pass

    def analyze_health(self, plant_data, sensor_data):
        """
        Compares sensor data with plant requirements to determine health status.
        """
        status = "Healthy"
        issues = []
        recommendations = []

        # Extract requirements (with defaults if missing)
        # Trefle data structure varies, assumes some common fields
        # Ideally, we would parse this more robustly
        
        # Example logic - replace with real parsing based on Trefle return structure
        min_temp = plant_data.get("growth", {}).get("minimum_temperature", {}).get("deg_c", 10)
        max_temp = plant_data.get("growth", {}).get("maximum_temperature", {}).get("deg_c", 30)
        
        min_moisture = plant_data.get("growth", {}).get("minimum_precipitation", {}).get("mm", 20) # Proxy for moisture
        # This is a simplification. Trefle doesn't always have direct "soil moisture %"
        
        # Temperature Check
        curr_temp = sensor_data["temperature"]
        if curr_temp < min_temp:
            status = "Needs Attention"
            issues.append("Too Cold")
            recommendations.append(f"Raise temperature above {min_temp}°C")
        elif curr_temp > max_temp:
            status = "Needs Attention"
            issues.append("Too Hot")
            recommendations.append(f"Lower temperature below {max_temp}°C")

        # Moisture Check (Simplified)
        curr_moisture = sensor_data["soil_moisture"]
        if curr_moisture < 20: # Arbitrary low threshold
            status = "Needs Attention"
            issues.append("Dry Soil")
            recommendations.append("Water the plant immediately.")
        elif curr_moisture > 80: # Arbitrary high threshold
            status = "Needs Attention"
            issues.append("Overwatered")
            recommendations.append("Stop watering and ensure drainage.")

        return {
            "status": status,
            "issues": issues,
            "recommendations": recommendations,
            "details": {
                "sensor_readings": sensor_data,
                "ideal_ranges": {
                    "temperature": f"{min_temp} - {max_temp}",
                    "moisture": "20% - 80% (Est.)"
                }
            }
        }
