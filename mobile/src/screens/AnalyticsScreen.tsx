import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, Dimensions, ScrollView, ActivityIndicator } from 'react-native';
import { Theme } from '../theme';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Svg, { Path, Defs, LinearGradient as SvgLinearGradient, Stop, Circle } from 'react-native-svg';
import { TrendingUp } from 'lucide-react-native';
import { getPots, getGrowthHistory, GrowthEntry } from '../firebase';
import { Pot } from '../utils/types';

const { width } = Dimensions.get('window');
const CHART_Height = 220;
const CHART_WIDTH = width - 48 - 40; // padding

export default function AnalyticsScreen() {
  const insets = useSafeAreaInsets();
  const [loading, setLoading] = useState(true);
  const [pots, setPots] = useState<Pot[]>([]);
  const [growthData, setGrowthData] = useState<GrowthEntry[]>([]);
  const [activePot, setActivePot] = useState<Pot | null>(null);

  useEffect(() => {
    async function loadData() {
      try {
        const fetchedPots = await getPots();
        setPots(fetchedPots);
        
        if (fetchedPots.length > 0) {
          const firstPot = fetchedPots[0];
          setActivePot(firstPot);
          const history = await getGrowthHistory(firstPot.id);
          setGrowthData(history);
        }
      } catch (e) {
        console.error("Failed to load analytics:", e);
      } finally {
        setLoading(false);
      }
    }
    loadData();
  }, []);

  if (loading) {
    return (
      <View style={[styles.container, { justifyContent: 'center', alignItems: 'center' }]}>
        <ActivityIndicator size="large" color={Theme.colors.primary} />
      </View>
    );
  }

  if (pots.length === 0 || growthData.length === 0) {
    return (
      <View style={[styles.container, { paddingTop: insets.top + 20, paddingHorizontal: 24 }]}>
         <View style={styles.header}>
            <View style={styles.badgeContainer}>
              <View style={styles.badgeLine} />
              <Text style={styles.badgeText}>STATS</Text>
            </View>
            <Text style={styles.headerTitle}>GROWTH</Text>
        </View>
        <View style={styles.emptyContainer}>
            <Text style={styles.emptyText}>
                {pots.length === 0 
                  ? "No plants tracked yet. Add a plant to see analytics." 
                  : "No growth data recorded for this plant yet."}
            </Text>
        </View>
      </View>
    );
  }

  // Process data for Chart
  const dataValues = growthData.map(d => d.height);
  // Ensure we have at least 2 points for a line
  const chartValues = dataValues.length === 1 ? [dataValues[0], dataValues[0]] : dataValues;
  const labels = growthData.map((d, i) => `Entry ${i + 1}`); // Simplified labels

  const max = Math.max(...chartValues);
  const min = Math.min(...chartValues);
  const range = max - min || 1;
  const stepX = CHART_WIDTH / (chartValues.length - 1);
  const stepY = (CHART_Height - 60) / range; // leave some padding

  const points = chartValues.map((val, index) => {
    const x = index * stepX;
    const y = CHART_Height - ((val - min) * stepY) - 30;
    return `${x},${y}`;
  }).join(' ');

  // Create area path
  const areaPath = `M0,${CHART_Height} L0,${CHART_Height - ((chartValues[0] - min) * stepY) - 30} ${points.replace(/,/g, ' ')} L${(chartValues.length - 1) * stepX},${CHART_Height} Z`;

  const totalGrowth = chartValues[chartValues.length - 1] - chartValues[0];
  const activePlantName = activePot?.plantData?.name || activePot?.name || 'Plant';

  return (
    <View style={styles.container}>
       <ScrollView contentContainerStyle={[styles.scrollContent, { paddingTop: insets.top + 20 }]}>
            <View style={styles.header}>
                <View style={styles.badgeContainer}>
                  <View style={styles.badgeLine} />
                  <Text style={styles.badgeText}>STATS</Text>
                </View>
                <Text style={styles.headerTitle}>GROWTH</Text>
                <Text style={styles.subHeader}>{activePlantName.toUpperCase()}</Text>
            </View>

            {/* Growth Chart */}
            <View style={styles.chartCard}>
                <View style={styles.cardHeader}>
                    <View>
                        <Text style={styles.cardTitle}>HEIGHT TRAJECTORY</Text>
                        <Text style={styles.cardSubtitle}>
                            {totalGrowth >= 0 ? '+' : ''}{totalGrowth}cm TOTAL GROWTH
                        </Text>
                    </View>
                    <View style={styles.iconContainer}>
                        <TrendingUp size={20} color={Theme.colors.primary} />
                    </View>
                </View>

                <View style={styles.chartContainer}>
                    <Svg height={CHART_Height} width={CHART_WIDTH}>
                        <Defs>
                            <SvgLinearGradient id="grad" x1="0" y1="0" x2="0" y2="1">
                                <Stop offset="0" stopColor={Theme.colors.primary} stopOpacity="0.2" />
                                <Stop offset="1" stopColor={Theme.colors.primary} stopOpacity="0" />
                            </SvgLinearGradient>
                        </Defs>
                        
                        {/* Area Fill */}
                        <Path d={areaPath} fill="url(#grad)" />
                        
                        {/* Line */}
                        <Path
                            d={`M${chartValues.map((val, index) => {
                                const x = index * stepX;
                                const y = CHART_Height - ((val - min) * stepY) - 30;
                                return `${x},${y}`;
                            }).join(' L')}`}
                            fill="none"
                            stroke={Theme.colors.primary}
                            strokeWidth="3"
                        />

                        {/* Dots */}
                        {chartValues.map((val, index) => {
                             const x = index * stepX;
                             const y = CHART_Height - ((val - min) * stepY) - 30;
                             return (
                                 <Circle key={index} cx={x} cy={y} r="6" fill="#000" stroke={Theme.colors.primary} strokeWidth="2" />
                             )
                        })}
                    </Svg>
                    
                    {/* Simplified X-Axis Labels (First and Last) */}
                    <View style={styles.labelsContainer}>
                        <Text style={styles.label}>{new Date(growthData[0].timestamp).toLocaleDateString()}</Text>
                        <Text style={styles.label}>{new Date(growthData[growthData.length - 1].timestamp).toLocaleDateString()}</Text>
                    </View>
                </View>
            </View>

             {/* Stats Grid */}
             <Text style={styles.sectionTitle}>SUMMARY</Text>
             <View style={styles.grid}>
                 <View style={styles.statCard}>
                     <Text style={styles.statValue}>
                        {growthData[growthData.length-1].healthScore}%
                     </Text>
                     <Text style={styles.statLabel}>HEALTH</Text>
                 </View>
                 <View style={styles.statCard}>
                     <Text style={styles.statValue}>
                        {growthData[growthData.length-1].leaves}
                     </Text>
                     <Text style={styles.statLabel}>LEAVES</Text>
                 </View>
                 <View style={styles.statCard}>
                     <Text style={styles.statValue}>
                        {growthData.length}
                     </Text>
                     <Text style={styles.statLabel}>ENTRIES</Text>
                 </View>
             </View>

       </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#050A07',
  },
  scrollContent: {
      paddingHorizontal: 24,
      paddingBottom: 100,
  },
  header: {
    marginBottom: 32,
  },
  subHeader: {
      color: '#888',
      fontSize: 14,
      fontWeight: '700',
      marginTop: 4,
      letterSpacing: 1,
  },
  badgeContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
    gap: 12,
  },
  badgeLine: {
    width: 24,
    height: 2,
    backgroundColor: Theme.colors.primary,
  },
  badgeText: {
    color: Theme.colors.primary,
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 2,
  },
  headerTitle: {
    fontSize: 42,
    fontWeight: '800',
    color: '#fff',
    letterSpacing: -2,
    lineHeight: 42,
  },
  chartCard: {
      padding: 24,
      marginBottom: 40,
      backgroundColor: '#0F1612',
      borderWidth: 1,
      borderColor: '#222',
  },
  cardHeader: {
      flexDirection: 'row',
      alignItems: 'flex-start',
      justifyContent: 'space-between',
      marginBottom: 32,
  },
  iconContainer: {
    width: 40,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  cardTitle: {
      fontSize: 14,
      fontWeight: '700',
      color: '#fff',
      letterSpacing: 1,
      marginBottom: 4,
  },
  cardSubtitle: {
      fontSize: 12,
      color: Theme.colors.primary,
      fontWeight: '700',
      letterSpacing: 0.5,
  },
  chartContainer: {
      alignItems: 'center',
  },
  labelsContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    width: '100%',
    marginTop: 16,
    paddingHorizontal: 4,
  },
  label: {
      fontSize: 10,
      color: '#666',
      fontWeight: '700',
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: '700',
    color: '#fff',
    marginBottom: 16,
    letterSpacing: 1,
  },
  grid: {
      flexDirection: 'row',
      gap: 12,
  },
  statCard: {
      flex: 1,
      padding: 16,
      alignItems: 'center',
      backgroundColor: '#0F1612',
      borderWidth: 1,
      borderColor: '#222',
      height: 100,
      justifyContent: 'center',
  },
  statValue: {
      fontSize: 28,
      fontWeight: '700',
      color: '#fff',
      marginBottom: 4,
      letterSpacing: -1,
  },
  statLabel: {
      fontSize: 10,
      color: '#888',
      fontWeight: '700',
      letterSpacing: 1,
  },
  emptyContainer: {
      marginTop: 40,
      padding: 24,
      backgroundColor: '#0F1612',
      borderWidth: 1,
      borderColor: '#222',
      alignItems: 'center',
  },
  emptyText: {
      color: '#888',
      textAlign: 'center',
      lineHeight: 22,
  }
});
