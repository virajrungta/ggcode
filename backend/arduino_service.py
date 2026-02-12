import random
import time

class ArduinoService:
    def __init__(self):
        pass

    def get_sensor_data(self):
        """
        Simulates reading data from Arduino sensors.
        Returns a dictionary with sensor values.
        """
        # Simulate some realistic fluctuation
        base_temp = 22.0
        base_humidity = 45.0
        base_light = 500
        base_moisture = 40

        # Add some random noise
        temperature = base_temp + random.uniform(-2, 2)
        humidity = base_humidity + random.uniform(-5, 5)
        light = base_light + random.randint(-50, 50)
        moisture = base_moisture + random.randint(-10, 10)

        return {
            "temperature": round(temperature, 1), # Celsius
            "humidity": round(humidity, 1),       # Percent
            "light_level": int(light),            # Lux (approx)
            "soil_moisture": int(moisture)        # Percent
        }
