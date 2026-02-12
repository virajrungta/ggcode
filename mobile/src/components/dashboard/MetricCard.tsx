import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Theme } from '../../theme';
import { LucideIcon } from 'lucide-react-native';

interface MetricCardProps {
  label: string;
  value: string | number;
  unit: string;
  icon: LucideIcon;
  color: string;
  trend?: 'up' | 'down' | 'stable';
  status?: 'good' | 'warning' | 'bad';
}

export function MetricCard({ label, value, unit, icon: Icon, color, status }: MetricCardProps) {
  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <View style={[styles.iconContainer, { backgroundColor: `${color}15` }]}>
          <Icon size={18} color={color} />
        </View>
        {status && status !== 'good' && (
          <View style={[styles.statusDot, { backgroundColor: status === 'bad' ? Theme.colors.statusBad : Theme.colors.statusWarning }]} />
        )}
      </View>
      
      <View style={styles.content}>
        <View style={styles.valueRow}>
          <Text style={styles.value}>{value}</Text>
          <Text style={styles.unit}>{unit}</Text>
        </View>
        <Text style={styles.label}>{label.toUpperCase()}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    padding: 16,
    flex: 1,
    minWidth: 140,
    backgroundColor: '#0F1612',
    borderWidth: 1,
    borderColor: '#222',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 16,
  },
  iconContainer: {
    width: 32,
    height: 32,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
  },
  statusDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
  },
  content: {
    gap: 4,
  },
  valueRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
  },
  value: {
    fontSize: 28,
    fontWeight: '800', // Extra bold
    color: '#FFFFFF',
    letterSpacing: -1,
  },
  unit: {
    fontSize: 14,
    fontWeight: '600',
    color: '#666',
    marginLeft: 4,
  },
  label: {
    fontSize: 10,
    fontWeight: '700',
    color: '#888', // Muted text
    letterSpacing: 1.5,
  },
});
