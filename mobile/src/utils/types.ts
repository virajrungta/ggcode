export interface PlantData {
    id: string;
    name: string;
    scientificName: string;
    imageUrl?: string;
    compatible: boolean;
    // Confidence level for plant identification (0-100)
    confidence?: number;
    // Alternative suggestions when confidence is low
    alternatives?: Array<{
        name: string;
        scientificName: string;
        confidence: number;
    }>;
}

export interface Pot {
    id: string;
    name: string;
    plantData: PlantData | null;
}

export interface SensorData {
    temperature: number;
    humidity: number;
    light: number;
    soilMoisture: number;
}

export interface EnvironmentStatus {
    parameter: 'Temperature' | 'Humidity' | 'Light' | 'Soil Moisture';
    status: 'good' | 'warning' | 'bad';
    message: string;
}

// Identification state for better UX
export type IdentificationState = 
    | { type: 'idle' }
    | { type: 'capturing' }
    | { type: 'analyzing' }
    | { type: 'success'; results: PlantData[] }
    | { type: 'low_confidence'; results: PlantData[] }
    | { type: 'error'; message: string };
