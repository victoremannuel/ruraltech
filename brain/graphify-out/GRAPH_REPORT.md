# Graph Report - brain  (2026-06-18)

## Corpus Check
- 192 files · ~159,098 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 56 nodes · 80 edges · 8 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Primitives.jsx, Primitives.jsx|Primitives.jsx, Primitives.jsx]]
- [[_COMMUNITY_Primitives 2.jsx, Primitives 2.jsx|Primitives 2.jsx, Primitives 2.jsx]]
- [[_COMMUNITY_MoreScreens 2.jsx, MoreScreens 2.jsx|MoreScreens 2.jsx, MoreScreens 2.jsx]]
- [[_COMMUNITY_MoreScreens.jsx, MoreScreens.jsx|MoreScreens.jsx, MoreScreens.jsx]]
- [[_COMMUNITY_DashboardScreen.jsx, DashboardScreen.jsx|DashboardScreen.jsx, DashboardScreen.jsx]]
- [[_COMMUNITY_DashboardScreen 2.jsx, DashboardScreen 2.jsx|DashboardScreen 2.jsx, DashboardScreen 2.jsx]]
- [[_COMMUNITY_LoginScreen.jsx, LoginScreen.jsx|LoginScreen.jsx, LoginScreen.jsx]]
- [[_COMMUNITY_LoginScreen 2.jsx, LoginScreen 2.jsx|LoginScreen 2.jsx, LoginScreen 2.jsx]]

## God Nodes (most connected - your core abstractions)
1. `DashboardScreen()` - 2 edges
2. `Pin()` - 2 edges
3. `DeviceDetailsScreen()` - 2 edges
4. `GeofenceScreen()` - 2 edges
5. `EventsScreen()` - 2 edges
6. `ProfileScreen()` - 2 edges
7. `HerdingScreen()` - 2 edges
8. `LoginScreen()` - 2 edges
9. `DashboardScreen()` - 2 edges
10. `Pin()` - 2 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Communities

### Community 0 - "Primitives.jsx, Primitives.jsx"
Cohesion: 0.26
Nodes (12): AppBar(), Badge(), Btn(), Card(), Chip(), Fab(), Field(), MapCanvas() (+4 more)

### Community 1 - "Primitives 2.jsx, Primitives 2.jsx"
Cohesion: 0.26
Nodes (12): AppBar(), Badge(), Btn(), Card(), Chip(), Fab(), Field(), MapCanvas() (+4 more)

### Community 2 - "MoreScreens 2.jsx, MoreScreens 2.jsx"
Cohesion: 0.48
Nodes (5): DeviceDetailsScreen(), EventsScreen(), GeofenceScreen(), HerdingScreen(), ProfileScreen()

### Community 3 - "MoreScreens.jsx, MoreScreens.jsx"
Cohesion: 0.48
Nodes (5): DeviceDetailsScreen(), EventsScreen(), GeofenceScreen(), HerdingScreen(), ProfileScreen()

### Community 4 - "DashboardScreen.jsx, DashboardScreen.jsx"
Cohesion: 0.67
Nodes (2): DashboardScreen(), Pin()

### Community 5 - "DashboardScreen 2.jsx, DashboardScreen 2.jsx"
Cohesion: 0.67
Nodes (2): DashboardScreen(), Pin()

### Community 6 - "LoginScreen.jsx, LoginScreen.jsx"
Cohesion: 0.67
Nodes (1): LoginScreen()

### Community 7 - "LoginScreen 2.jsx, LoginScreen 2.jsx"
Cohesion: 0.67
Nodes (1): LoginScreen()

## Suggested Questions
_Not enough signal to generate questions. This usually means the corpus has no AMBIGUOUS edges, no bridge nodes, no INFERRED relationships, and all communities are tightly cohesive. Add more files or run with --mode deep to extract richer edges._