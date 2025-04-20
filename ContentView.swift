import SwiftUI
import UniformTypeIdentifiers
import MapKit
import Foundation
import UIKit

// Extension to dismiss keyboard when return is pressed
extension View {
    func dismissKeyboardOnReturn() -> some View {
        self.onSubmit {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

// Extension to dismiss keyboard when tapping outside a text field
extension View {
    func dismissKeyboard() -> some View {
        return self.onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var viewModel = TripPlannerViewModel()
    @State private var selectedTab = 0
    @State private var showingSavedTrips = false
    @State private var showingSaveDialog = false
    @State private var tripNameToSave = ""
    @State private var showingImportPicker = false
    @State private var showingShareSheet = false
    @State private var exportedTripData: Data?
    
    var body: some View {
        TabView(selection: $selectedTab) {
            SearchView(viewModel: viewModel, showSavedTrips: { showingSavedTrips = true })
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(0)
            
            MapView(viewModel: viewModel)
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(1)
            
            ItineraryView(
                viewModel: viewModel,
                showSaveDialog: { showingSaveDialog = true },
                showShareSheet: {
                    exportedTripData = viewModel.exportTrip()
                    if exportedTripData != nil {
                        showingShareSheet = true
                    }
                },
                showImportPicker: { showingImportPicker = true }
            )
            .tabItem {
                Label("Itinerary", systemImage: "list.bullet.clipboard.fill")
            }
            .tag(2)
        }
        .accentColor(.primary)
        .onAppear {
            viewModel.loadLastActiveTrip()
            viewModel.setupAutoSave()
            
            // Set up tab bar appearance for both light and dark mode
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            
            // Enhanced styling for tab bar items
            let selectedColor = UIColor.systemBlue
            let unselectedColor = UIColor.secondaryLabel
            
            appearance.stackedLayoutAppearance.normal.iconColor = unselectedColor
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: unselectedColor]
            appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
            
            UITabBar.appearance().standardAppearance = appearance
            
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.saveBeforeBackground()
        }
        .sheet(isPresented: $showingSavedTrips) {
            SavedTripsView(viewModel: viewModel, isPresented: $showingSavedTrips)
        }
        .alert("Save Trip", isPresented: $showingSaveDialog) {
            TextField("Trip Name", text: $tripNameToSave)
                .autocapitalization(.words)
            
            Button("Cancel", role: .cancel) {
                tripNameToSave = ""
            }
            
            Button("Save") {
                if !tripNameToSave.isEmpty {
                    viewModel.saveTripAsNew(withName: tripNameToSave)
                } else {
                    viewModel.saveCurrentTrip()
                }
                tripNameToSave = ""
            }
            .fontWeight(.semibold)
        } message: {
            Text("Enter a name for your trip or leave blank to use the destination name.")
        }
        .sheet(isPresented: $showingShareSheet) {
            if let data = exportedTripData {
                if let jsonString = String(data: data, encoding: .utf8) {
                    ActivityViewController(activityItems: [jsonString])
                } else {
                    ActivityViewController(activityItems: [data])
                }
            }
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [UTType.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let selectedFile: URL = try result.get().first else { return }
                
                if selectedFile.startAccessingSecurityScopedResource() {
                    defer { selectedFile.stopAccessingSecurityScopedResource() }
                    
                    let data = try Data(contentsOf: selectedFile)
                    let importSuccess = viewModel.importTrip(data: data)
                    
                    if importSuccess {
                        selectedTab = 2 // Switch to itinerary tab
                    }
                }
            } catch {
                viewModel.error = "Error importing file: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Activity View Controller for sharing
struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {}
}

struct SearchView: View {
    @ObservedObject var viewModel: TripPlannerViewModel
    var showSavedTrips: () -> Void
    @State private var showingNewTripDialog = false
    @State private var newTripDestination = ""
    @State private var funFacts: [String] = []
    @State private var isLoadingFacts = false
    @State private var lastFetchedDestination: String = ""
    @State private var previousLocationCount = 0
    @State private var initialLoadDone = false
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Trip Planner")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.primary)
                        
                        if let activeTrip = viewModel.getActiveTrip() {
                            Text("Current Trip: \(activeTrip.destination)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                        }
                        
                        Text("Where would you like to go?")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    
                    // Search field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Destination")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.secondary)
                                .padding(.leading, 12)
                            
                            TextField("Enter destination (e.g., 'Paris' or 'Tokyo')", text: $viewModel.searchQuery)
                                .padding(.vertical, 12)
                                .autocapitalization(.words)
                                .dismissKeyboardOnReturn()
                            
                            if !viewModel.searchQuery.isEmpty {
                                Button(action: {
                                    viewModel.searchQuery = ""
                                    funFacts = []
                                    isLoadingFacts = false
                                    lastFetchedDestination = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                                .padding(.trailing, 12)
                            }
                        }
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                    
                    // Trip Duration Slider
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Trip Duration")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(viewModel.numberOfDays) \(viewModel.numberOfDays == 1 ? "day" : "days")")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            HStack {
                                Text("1")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Slider(value: Binding(
                                    get: { Double(viewModel.numberOfDays) },
                                    set: { viewModel.numberOfDays = Int($0) }
                                ), in: 1...14, step: 1)
                                .accentColor(.blue)
                                
                                Text("14")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // Buttons
                    VStack(spacing: 16) {
                        Button(action: {
                            funFacts = []
                            lastFetchedDestination = ""
                            viewModel.planTrip()
                        }) {
                            HStack {
                                Image(systemName: "airplane.departure")
                                Text("Plan My Trip")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.searchQuery.isEmpty ? Color.blue.opacity(0.4) : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(color: Color.blue.opacity(0.3), radius: 3, x: 0, y: 2)
                        }
                        .disabled(viewModel.searchQuery.isEmpty || viewModel.isLoading)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                funFacts = []
                                lastFetchedDestination = ""
                                showSavedTrips()
                            }) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                    Text("My Trips")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: Color.orange.opacity(0.3), radius: 3, x: 0, y: 2)
                            }
                            
                            Button(action: { showingNewTripDialog = true }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("New Trip")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: Color.green.opacity(0.3), radius: 3, x: 0, y: 2)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Fun Facts Section
                    if !viewModel.isLoading && !viewModel.locations.isEmpty && !funFacts.isEmpty {
                        let destination = viewModel.getActiveTrip()?.destination ?? viewModel.searchQuery
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("About \(destination)")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.bottom, 4)
                            
                            ForEach(funFacts, id: \.self) { fact in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(.yellow)
                                        .font(.system(size: 20))
                                    
                                    Text(fact)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        .transition(.opacity)
                    }
                    
                    // Error display
                    if let error = viewModel.error {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                
                                Text("Error")
                                    .font(.headline)
                                    .foregroundColor(.red)
                            }
                            
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.top, 16)
                .background(Color(.systemBackground))
                .dismissKeyboard()
                .alert("Create New Trip", isPresented: $showingNewTripDialog) {
                    TextField("Destination", text: $newTripDestination)
                        .autocapitalization(.words)
                    
                    Button("Cancel", role: .cancel) {
                        newTripDestination = ""
                    }
                    
                    Button("Create") {
                        if !newTripDestination.isEmpty {
                            viewModel.createNewEmptyTrip(destination: newTripDestination)
                            funFacts = []
                            lastFetchedDestination = ""
                        }
                        newTripDestination = ""
                    }
                    .fontWeight(.semibold)
                } message: {
                    Text("Enter the destination for your new trip.")
                }
                .opacity(viewModel.isLoading ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
                .onAppear {
                    if !initialLoadDone {
                        initialLoadDone = true
                        
                        if let activeTripID = UserDefaults.standard.string(forKey: "activeTripID") {
                            viewModel.loadTrip(withID: activeTripID)
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if let activeTrip = viewModel.getActiveTrip(), !viewModel.locations.isEmpty {
                                    fetchFunFacts(for: activeTrip.destination)
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: viewModel.locations) { newLocations in
                let currentDestination = viewModel.getActiveTrip()?.destination ?? viewModel.searchQuery
                
                if !newLocations.isEmpty &&
                   (lastFetchedDestination != currentDestination ||
                    newLocations.count != previousLocationCount) {
                    
                    if !currentDestination.isEmpty {
                        fetchFunFacts(for: currentDestination)
                    }
                }
                
                previousLocationCount = newLocations.count
            }
            
            // Enhanced Loading Screen
            if viewModel.isLoading {
                ZStack {
                    Color(.systemBackground)
                        .opacity(0.8)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 24) {
                        ZStack {
                            Circle()
                                .stroke(Color.blue.opacity(0.3), lineWidth: 8)
                                .frame(width: 100, height: 100)
                            
                            Circle()
                                .trim(from: 0, to: 0.7)
                                .stroke(Color.blue, lineWidth: 8)
                                .frame(width: 100, height: 100)
                                .rotationEffect(Angle(degrees: isLoadingFacts ? 360 : 0))
                                .animation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false), value: isLoadingFacts)
                                .onAppear {
                                    isLoadingFacts = true
                                }
                                .onDisappear {
                                    isLoadingFacts = false
                                }
                            
                            Image(systemName: "airplane")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                                .foregroundColor(.blue)
                        }
                        
                        VStack(spacing: 8) {
                            Text("Creating Your")
                                .font(.title3)
                                .fontWeight(.medium)
                            
                            Text("\(viewModel.searchQuery) Adventure")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        Text("Discovering the best places for you to visit...")
                            .foregroundColor(.secondary)
                        
                        // Loading progress indicators
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Finding top attractions")
                                    .foregroundColor(.primary)
                            }
                            
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Planning your daily route")
                                    .foregroundColor(.primary)
                            }
                            
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Gathering location details")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .padding(30)
                    .background(Color(.systemBackground))
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                    .transition(.opacity)
                }
                .edgesIgnoringSafeArea(.all)
            }
        }
    }
    
    // Helper function to fetch fun facts
    private func fetchFunFacts(for destination: String) {
        isLoadingFacts = true
        lastFetchedDestination = destination
        funFacts = []
        
        viewModel.fetchDynamicFunFacts(for: destination) { newFacts in
            self.funFacts = newFacts
            self.isLoadingFacts = false
        }
    }
}

// MARK: - MapView
struct MapView: View {
    @ObservedObject var viewModel: TripPlannerViewModel
    @State private var selectedLocation: Location?
    @State private var mapType: MKMapType = .standard
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Map(coordinateRegion: $viewModel.region,
                interactionModes: .all,
                showsUserLocation: false,
                userTrackingMode: nil,
                annotationItems: viewModel.locations,
                annotationContent: { location in
                    MapAnnotation(coordinate: location.coordinate) {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(dayColor(for: location.day))
                                    .frame(width: 36, height: 36)
                                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                                
                                Text("\(location.order + 1)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            .onTapGesture {
                                withAnimation(.spring()) {
                                    selectedLocation = location
                                }
                            }
                            
                            if selectedLocation?.id == location.id {
                                Text(location.name)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(6)
                                    .background(Color(.systemBackground))
                                    .cornerRadius(8)
                                    .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                                    .transition(.scale)
                            }
                        }
                    }
                }
            )
            .mapStyle(mapType == .standard ? .standard :
                     (mapType == .hybrid ? .hybrid : .imagery))
            .edgesIgnoringSafeArea(.all)
            
            VStack {
                // Controls overlay at top
                VStack(spacing: 12) {
                    // Map type picker with improved visibility
                    Picker("Map Type", selection: $mapType) {
                        Text("Standard").tag(MKMapType.standard)
                        Text("Satellite").tag(MKMapType.satellite)
                        Text("Hybrid").tag(MKMapType.hybrid)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    
                    // Day filter buttons
                    if !viewModel.tripDays.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(viewModel.tripDays) { day in
                                    Button(action: {
                                        focusMapOnDay(day.day)
                                    }) {
                                        HStack {
                                            Image(systemName: "calendar.day.timeline.left")
                                                .font(.system(size: 14))
                                            Text("Day \(day.day)")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(dayColor(for: day.day))
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .background(Color(.systemBackground).opacity(0.95))
                .cornerRadius(15)
                .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 2)
                .padding(.top, 10)
                .padding(.horizontal, 10)
                
                Spacer()
            }
            
            // Location detail card
            if let location = selectedLocation {
                LocationDetailCard(
                    location: location,
                    viewModel: viewModel,
                    isPresented: Binding<Bool>(
                        get: { selectedLocation != nil },
                        set: { if !$0 { selectedLocation = nil } }
                    )
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedLocation != nil)
            }
        }
    }
    
    // More distinct day colors that will be visible in both dark and light mode
    private func dayColor(for day: Int) -> Color {
        let colors: [Color] = [
            .blue,
            .green,
            .orange,
            .purple,
            .pink,
            .teal,
            .indigo,
            .red,
            .mint,
            .cyan,
            .brown,
            .yellow,
            .gray
        ]
        
        let index = (day - 1) % colors.count
        return colors[index]
    }
    
    private func focusMapOnDay(_ day: Int) {
        guard let dayLocations = viewModel.tripDays.first(where: { $0.day == day })?.locations, !dayLocations.isEmpty else {
            return
        }
        
        // Calculate the center and span for the day's locations
        let coordinates = dayLocations.map { $0.coordinate }
        
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        // Add some padding to the span
        let latDelta = (maxLat - minLat) * 1.5
        let lonDelta = (maxLon - minLon) * 1.5
        
        withAnimation(.easeInOut(duration: 0.5)) {
            viewModel.region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: max(latDelta, 0.02), longitudeDelta: max(lonDelta, 0.02))
            )
        }
    }
}

// MARK: - Location Detail Card
struct LocationDetailCard: View {
    let location: Location
    @ObservedObject var viewModel: TripPlannerViewModel
    @Binding var isPresented: Bool
    @State private var isEditing = false
    @State private var editedName: String
    @State private var editedDescription: String
    
    init(location: Location, viewModel: TripPlannerViewModel, isPresented: Binding<Bool>) {
        self.location = location
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._isPresented = isPresented
        self._editedName = State(initialValue: location.name)
        self._editedDescription = State(initialValue: location.description)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if !isEditing {
                        Text(location.name)
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        HStack(spacing: 8) {
                            Text("Day \(location.day)")
                                .font(.subheadline)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(dayColor(for: location.day).opacity(0.2))
                                .foregroundColor(dayColor(for: location.day))
                                .cornerRadius(4)
                            
                            Text("Stop \(location.order + 1)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Edit Location")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                }
                
                Spacer()
                
                if isEditing {
                    Button(action: {
                        // Cancel editing
                        editedName = location.name
                        editedDescription = location.description
                        isEditing = false
                    }) {
                        Text("Cancel")
                            .foregroundColor(.red)
                    }
                    .padding(.trailing, 8)
                    
                    Button(action: {
                        // Save edits
                        saveLocationChanges()
                        isEditing = false
                    }) {
                        Text("Save")
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    .disabled(editedName.isEmpty)
                } else {
                    Button(action: {
                        isEditing = true
                    }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    .padding(.trailing, 8)
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding()
            
            Divider()
                .background(Color.secondary.opacity(0.3))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Photo
                    if let photoURL = location.photoURL {
                        AsyncImage(url: photoURL) { phase in
                            switch phase {
                            case .empty:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .aspectRatio(16/9, contentMode: .fill)
                                    .overlay(
                                        ProgressView()
                                            .scaleEffect(1.2)
                                    )
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .aspectRatio(16/9, contentMode: .fill)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.largeTitle)
                                            .foregroundColor(.white)
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                            )
                    }
                    
                    if isEditing {
                        // Name editing
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("Location Name", text: $editedName)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                        
                        // Description editing
                        VStack(alignment: .leading, spacing: 8) {
                                                    Text("Description")
                                                        .font(.headline)
                                                        .foregroundColor(.primary)
                                                    
                                                    TextEditor(text: $editedDescription)
                                                        .padding(4)
                                                        .frame(height: 150)
                                                        .background(Color(.secondarySystemBackground))
                                                        .cornerRadius(8)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 8)
                                                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                                        )
                                                }
                                            } else {
                                                // Description
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text("Description")
                                                        .font(.headline)
                                                        .foregroundColor(.primary)
                                                    
                                                    Text(location.description)
                                                        .font(.body)
                                                        .lineSpacing(4)
                                                        .foregroundColor(.primary)
                                                }
                                                
                                                Divider()
                                                    .padding(.vertical, 4)
                                                
                                                // Location details
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text("Location Details")
                                                        .font(.headline)
                                                        .foregroundColor(.primary)
                                                    
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text("Latitude: \(String(format: "%.6f", location.coordinate.latitude))")
                                                            .font(.subheadline)
                                                            .foregroundColor(.secondary)
                                                        
                                                        Text("Longitude: \(String(format: "%.6f", location.coordinate.longitude))")
                                                            .font(.subheadline)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    .padding()
                                                    .background(Color(.secondarySystemBackground))
                                                    .cornerRadius(8)
                                                }
                                            }
                                        }
                                        .padding(.horizontal)
                                        .padding(.bottom)
                                    }
                                }
                                .background(Color(.systemBackground))
                                .cornerRadius(16)
                                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                                .frame(height: isEditing ? 520 : 450)
                                .padding()
                            }
                            
                            private func dayColor(for day: Int) -> Color {
                                let colors: [Color] = [
                                    .blue, .green, .orange, .purple, .pink, .teal, .indigo, .red
                                ]
                                
                                let index = (day - 1) % colors.count
                                return colors[index]
                            }
                            
                            private func saveLocationChanges() {
                                // Update location in viewModel.locations
                                if let index = viewModel.locations.firstIndex(where: { $0.id == location.id }) {
                                    viewModel.locations[index].name = editedName
                                    viewModel.locations[index].description = editedDescription
                                }
                                
                                // Update location in viewModel.tripDays
                                if let dayIndex = viewModel.tripDays.firstIndex(where: { $0.day == location.day }),
                                   let locIndex = viewModel.tripDays[dayIndex].locations.firstIndex(where: { $0.id == location.id }) {
                                    viewModel.tripDays[dayIndex].locations[locIndex].name = editedName
                                    viewModel.tripDays[dayIndex].locations[locIndex].description = editedDescription
                                }
                                
                                // Save changes to current trip
                                viewModel.saveCurrentTrip()
                            }
                        }
