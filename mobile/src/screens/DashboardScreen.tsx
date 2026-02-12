import React, { useState, useEffect } from 'react';
import { View, StyleSheet, StatusBar, ActivityIndicator } from 'react-native';
import { Theme } from '../theme';
import { Pot, SensorData, EnvironmentStatus, PlantData } from '../utils/types';
import PotList from '../components/PotList';
import BluetoothSetup from '../components/BluetoothSetup';
import Dashboard from '../components/Dashboard';

// Firebase Services
import { 
  subscribeToPots, 
  savePot, 
  updatePotPlant,
  saveSensorReading
} from '../firebase';
import { getSensorStatus, analyzeHealth } from '../utils/api';

export default function DashboardScreen() {
  const [pots, setPots] = useState<Pot[]>([]);
  const [selectedPotId, setSelectedPotId] = useState<string | null>(null);
  const [isScanning, setIsScanning] = useState(false);
  const [loading, setLoading] = useState(true);

  // Selected Pot Data
  const selectedPot = pots.find((p: Pot) => p.id === selectedPotId);
  
  const [sensorData, setSensorData] = useState<SensorData | null>(null);
  const [envStatus, setEnvStatus] = useState<EnvironmentStatus[]>([]);

  // 1. Subscribe to Pots (Real-time)
  useEffect(() => {
    const unsubscribe = subscribeToPots((fetchedPots) => {
      setPots(fetchedPots);
      setLoading(false);
    });
    return () => unsubscribe();
  }, []);

  // 2. Real-time polling logic for sensors (Only when a pot with detailed view is open)
  // Note: ideally each pot would have its own sensor feed, but for this MVP 
  // we assume we are connecting to the active Bluetooth device of the selected pot.
  useEffect(() => {
    if (!selectedPot?.plantData) {
        setSensorData(null);
        setEnvStatus([]);
        return;
    }

    const fetchData = async () => {
        try {
            const sensors = await getSensorStatus();
            
            const formattedSensors: SensorData = {
                temperature: sensors.temperature,
                humidity: sensors.humidity,
                light: sensors.light_level,
                soilMoisture: sensors.soil_moisture
            };
            setSensorData(formattedSensors);

            // Optional: Save history to Firebase occasionally (e.g. here every poll, or debounce it)
            // For now, let's just log it or save it (careful with writes!)
            // await saveSensorReading(selectedPot.id, formattedSensors);

            const analysis = await analyzeHealth(selectedPot.plantData, sensors);
            
            const newEnvStatus: EnvironmentStatus[] = [
                { parameter: 'Temperature', status: 'good', message: 'Temperature is optimal' },
                { parameter: 'Humidity', status: 'good', message: 'Humidity is optimal' },
                { parameter: 'Light', status: 'good', message: 'Light levels are adequate' },
                { parameter: 'Soil Moisture', status: 'good', message: 'Soil moisture is healthy' }
            ];

            if (analysis.status !== "Healthy") {
                analysis.issues.forEach((issue: string) => {
                    const issueText = issue.toLowerCase();
                    if (issueText.includes("temperature") || issueText.includes("cold") || issueText.includes("hot")) {
                        const tempStat = newEnvStatus.find(s => s.parameter === 'Temperature');
                        if (tempStat) { tempStat.status = 'warning'; tempStat.message = issue; }
                    }
                    if (issueText.includes("soil") || issueText.includes("water")) {
                        const moistStat = newEnvStatus.find(s => s.parameter === 'Soil Moisture');
                        if (moistStat) { moistStat.status = 'warning'; moistStat.message = issue; }
                    }
                    if (issueText.includes("light") || issueText.includes("dark") || issueText.includes("bright")) {
                        const lightStat = newEnvStatus.find(s => s.parameter === 'Light');
                        if (lightStat) { lightStat.status = 'warning'; lightStat.message = issue; }
                    }
                    if (issueText.includes("humidity") || issueText.includes("dry") || issueText.includes("humid")) {
                        const humidStat = newEnvStatus.find(s => s.parameter === 'Humidity');
                        if (humidStat) { humidStat.status = 'warning'; humidStat.message = issue; }
                    }
                });
            }
            setEnvStatus(newEnvStatus);

        } catch (error) {
            console.error("Error polling data:", error);
        }
    };

    fetchData();
    const interval = setInterval(fetchData, 5000); // Poll every 5 seconds
    return () => clearInterval(interval);
  }, [selectedPot?.plantData]);

  const handleCreatePot = async (name: string) => {
    try {
      const newPot: Pot = {
          id: Date.now().toString(),
          name: name,
          plantData: null
      };
      await savePot(newPot); // Persist to Firebase
      setIsScanning(false);
    } catch (error) {
      console.error("Failed to create pot:", error);
      // Ideally show error toast
    }
  };

  const handleAddPlant = async (plant: PlantData) => {
    if (!selectedPotId) return;
    try {
      await updatePotPlant(selectedPotId, plant); // Persist to Firebase
      // No need to setPots manually, the subscription will update it
    } catch (error) {
      console.error("Failed to add plant:", error);
    }
  };

  if (loading) {
    return (
      <View style={[styles.container, { justifyContent: 'center', alignItems: 'center' }]}>
        <ActivityIndicator size="large" color={Theme.colors.primary} />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {isScanning && (
        <BluetoothSetup 
          onClose={() => setIsScanning(false)}
          onConnect={handleCreatePot}
        />
      )}

      {!selectedPotId ? (
        <PotList 
          pots={pots} 
          onSelectPot={(pot) => setSelectedPotId(pot.id)}
          onAddPot={() => setIsScanning(true)}
        />
      ) : (
        <Dashboard 
          plantData={selectedPot?.plantData || null}
          sensorData={sensorData}
          envStatus={envStatus}
          onAddPlant={handleAddPlant}
          onBack={() => setSelectedPotId(null)}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Theme.colors.bgMain,
  },
});

