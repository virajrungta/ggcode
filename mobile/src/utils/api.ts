import { PlantData, SensorData } from "./types";

// Replace with your machine's IP for testing on physical devices
// E.g., const BACKEND_URL = "http://192.168.1.100:8000";
const BACKEND_URL = "http://10.0.0.243:8000";

export async function identifyPlant(imageBase64: string): Promise<any> {
  const response = await fetch(`${BACKEND_URL}/identify`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ image_base64: imageBase64 }),
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.detail || "Failed to identify plant");
  }

  return response.json();
}

export async function getSensorStatus(): Promise<any> {
  const response = await fetch(`${BACKEND_URL}/status`);
  if (!response.ok) {
    throw new Error("Failed to fetch sensor status");
  }
  return response.json();
}

export async function analyzeHealth(
  plantData: any,
  sensorData: any,
): Promise<any> {
  const response = await fetch(`${BACKEND_URL}/analyze`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ plant_data: plantData, sensor_data: sensorData }),
  });

  if (!response.ok) {
    throw new Error("Failed to analyze health");
  }
  return response.json();
}
