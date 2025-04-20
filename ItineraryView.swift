//
//  ItineraryView.swift
//  TripPlannerApp
//
//  Created by Rohan Sen on 4/14/25.
//

import SwiftUI
import UniformTypeIdentifiers
import MapKit
import Foundation

// MARK: - Location Thumbnail
struct LocationThumbnail: View {
    let photoURL: URL?
    
    var body: some View {
        if let photoURL = photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .empty:
                    placeholderImage
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                case .failure:
                    placeholderImage
                        .overlay(
                            Image(systemName: "photo.slash")
                                .foregroundColor(.white)
                        )
                @unknown default:
                    placeholderImage
                }
            }
        } else {
            placeholderImage
        }
    }
    
    private var placeholderImage: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(.white)
            )
    }
}

// MARK: - Location Detail View for Itinerary
struct ItineraryLocationDetailView: View {
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
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                            )
                    }
                    
                    Group {
                        // Order and day info
                        HStack(spacing: 12) {
                            Text("Day \(location.day)")
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(dayColor(for: location.day))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                            
                            Text("Stop \(location.order + 1)")
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundColor(.primary)
                                .cornerRadius(8)
                        }
                        
                        if isEditing {
                            // Editable name
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Name")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                TextField("Location Name", text: $editedName)
                                    .padding()
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            
                            // Editable description
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Description")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                TextEditor(text: $editedDescription)
                                    .padding(8)
                                    .frame(minHeight: 180)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        } else {
                            // Display name
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Name")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text(location.name)
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .padding(.leading, 4)
                            }
                            
                            // Description
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Description")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text(location.description)
                                    .lineSpacing(6)
                                    .foregroundColor(.primary)
                                    .padding(.leading, 4)
                            }
                        }
                        
                        // Coordinates
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location Details")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "location.fill")
                                        .foregroundColor(.secondary)
                                        .frame(width: 20)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Latitude: \(String(format: "%.6f", location.coordinate.latitude))")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        Text("Longitude: \(String(format: "%.6f", location.coordinate.longitude))")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                if let placeID = location.placeID {
                                    HStack {
                                        Image(systemName: "g.circle.fill")
                                            .foregroundColor(.secondary)
                                            .frame(width: 20)
                                        
                                        Text("Google Place ID: \(placeID)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .navigationTitle(isEditing ? "Edit Location" : location.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditing {
                        Button("Cancel") {
                            // Reset edited values
                            editedName = location.name
                            editedDescription = location.description
                            isEditing = false
                        }
                        .foregroundColor(.red)
                    } else {
                        Button("Close") {
                            isPresented = false
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditing {
                        Button("Save") {
                            saveLocationChanges()
                            isEditing = false
                        }
                        .fontWeight(.semibold)
                        .disabled(editedName.isEmpty)
                    } else {
                        Button("Edit") {
                            isEditing = true
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
        }
        .accentColor(.primary)
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
// MARK: - Location Item View
struct LocationItemView: View {
    let location: Location
    let dayColor: Color
    let onMove: () -> Void
    let onTap: () -> Void
    @ObservedObject var viewModel: TripPlannerViewModel
    @State private var showingDetail = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Order indicator
            ZStack {
                Circle()
                    .fill(dayColor)
                    .frame(width: 36, height: 36)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                
                Text("\(location.order + 1)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            // Location details
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(location.description.count > 120 ? String(location.description.prefix(120)) + "..." : location.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                // Indicate there's more content
                if location.description.count > 120 {
                    Text("Tap to see more...")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            // Thumbnail image with info icon overlay
            ZStack(alignment: .bottomTrailing) {
                LocationThumbnail(photoURL: location.photoURL)
                
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "info")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .offset(x: 4, y: 4)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            showingDetail = true
        }
        .contextMenu {
            Button(action: onMove) {
                Label("Move to Different Day", systemImage: "arrow.left.arrow.right")
            }
            
            Button(action: {
                showingDetail = true
            }) {
                Label("View Details", systemImage: "info.circle")
            }
        }
        .sheet(isPresented: $showingDetail) {
            ItineraryLocationDetailView(
                location: location,
                viewModel: viewModel,
                isPresented: $showingDetail
            )
        }
    }
}
// MARK: - Itinerary List View
struct DaySectionView: View {
    let day: TripDay
    let viewModel: TripPlannerViewModel
    @Binding var movingLocation: Location?
    @Binding var showingDayPicker: Bool
    
    var body: some View {
        Section(header:
            HStack {
                Text("Day \(day.day)")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(day.locations.count) \(day.locations.count == 1 ? "location" : "locations")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        ) {
            ForEach(day.locations) { location in
                LocationItemView(
                    location: location,
                    dayColor: dayColor(for: location.day),
                    onMove: {
                        movingLocation = location
                        showingDayPicker = true
                    },
                    onTap: {},
                    viewModel: viewModel
                )
            }
            .onMove { indices, destination in
                viewModel.moveLocation(from: indices, to: destination, in: day.day)
                // Save changes after reordering
                viewModel.saveCurrentTrip()
            }
        }
    }
    
    // Helper function for day colors
    private func dayColor(for day: Int) -> Color {
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .pink, .teal, .indigo, .red
        ]
        
        let index = (day - 1) % colors.count
        return colors[index]
    }
}

struct ItineraryListView: View {
    @ObservedObject var viewModel: TripPlannerViewModel
    @Binding var isEditMode: EditMode
    @Binding var movingLocation: Location?
    @Binding var showingDayPicker: Bool
    
    var body: some View {
        List {
            ForEach(viewModel.tripDays) { day in
                DaySectionView(
                    day: day,
                    viewModel: viewModel,
                    movingLocation: $movingLocation,
                    showingDayPicker: $showingDayPicker
                )
            }
        }
        .listStyle(InsetGroupedListStyle())
        .environment(\.editMode, $isEditMode)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Updated Itinerary View
// In ItineraryView.swift, update the body property of the ItineraryView struct

struct ItineraryView: View {
    @ObservedObject var viewModel: TripPlannerViewModel
    @State private var isEditMode: EditMode = .inactive
    @State private var movingLocation: Location?
    @State private var showingDayPicker = false
    var showSaveDialog: () -> Void
    var showShareSheet: () -> Void
    var showImportPicker: () -> Void
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.tripDays.isEmpty {
                    VStack(spacing: 24) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 70))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.bottom, 8)
                        
                        Text("No Itinerary Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Search for a destination or create a new trip to start planning your itinerary")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Button(action: {
                            // Switch to search tab
                            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                  let tabBarController = windowScene.windows.first?.rootViewController as? UITabBarController else {
                                return
                            }
                            tabBarController.selectedIndex = 0
                        }) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("Start Planning")
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .shadow(color: Color.blue.opacity(0.3), radius: 3, x: 0, y: 2)
                        }
                        .padding(.top, 16)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else {
                    ItineraryListView(
                        viewModel: viewModel,
                        isEditMode: $isEditMode,
                        movingLocation: $movingLocation,
                        showingDayPicker: $showingDayPicker
                    )
                }
            }
            .navigationTitle(viewModel.searchQuery.isEmpty ? "Itinerary" : "Trip to \(viewModel.searchQuery)")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(action: {
                            // Save current trip without dialog
                            viewModel.saveCurrentTrip()
                        }) {
                            Label("Save Changes", systemImage: "square.and.arrow.down")
                        }
                        .disabled(viewModel.tripDays.isEmpty)
                        
                        Button(action: showSaveDialog) {
                            Label("Save As New Trip", systemImage: "doc.badge.plus")
                        }
                        .disabled(viewModel.tripDays.isEmpty)
                        
                        Button(action: showShareSheet) {
                            Label("Share Trip", systemImage: "square.and.arrow.up")
                        }
                        .disabled(viewModel.tripDays.isEmpty)
                        
                        Button(action: showImportPicker) {
                            Label("Import Trip", systemImage: "square.and.arrow.down.on.square")
                        }
                        
                        Divider()
                        
                        // Delete active trip - only show if there's an active trip
                        if let activeTripID = UserDefaults.standard.string(forKey: "activeTripID"), !viewModel.tripDays.isEmpty {
                            Button(role: .destructive, action: {
                                viewModel.deleteTrip(withID: activeTripID)
                                viewModel.createNewEmptyTrip(destination: "")
                            }) {
                                Label("Delete Trip", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.blue)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditMode.isEditing ? "Done" : "Edit") {
                        withAnimation {
                            isEditMode = isEditMode.isEditing ? .inactive : .active
                        }
                        if isEditMode == .inactive {
                            // Save changes when exiting edit mode
                            viewModel.saveCurrentTrip()
                        }
                    }
                    .disabled(viewModel.tripDays.isEmpty)
                }
            }
            .confirmationDialog("Move to Day", isPresented: $showingDayPicker, titleVisibility: .visible) {
                ForEach(viewModel.tripDays) { day in
                    if let movingLoc = movingLocation, day.day != movingLoc.day {
                        Button("Day \(day.day)") {
                            viewModel.moveLocationToDay(location: movingLoc, toDay: day.day)
                            movingLocation = nil
                        }
                    }
                }
                
                Button("Cancel", role: .cancel) {
                    movingLocation = nil
                }
            }
        }
    }
}

// MARK: - SavedTripsView
struct SavedTripsView: View {
    @ObservedObject var viewModel: TripPlannerViewModel
    @Binding var isPresented: Bool
    @State private var trips: [Trip] = []
    @State private var tripToDelete: Trip?
    @State private var showingDeleteConfirmation = false
    @State private var showingRenameDialog = false
    @State private var tripToRename: Trip?
    @State private var newTripName = ""
    @State private var searchText = ""
    
    var filteredTrips: [Trip] {
        if searchText.isEmpty {
            return trips
        } else {
            return trips.filter { $0.destination.lowercased().contains(searchText.lowercased()) }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search trips", text: $searchText)
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 15)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                List {
                    if filteredTrips.isEmpty {
                        VStack(spacing: 16) {
                            if searchText.isEmpty && trips.isEmpty {
                                Image(systemName: "suitcase")
                                    .font(.system(size: 60))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .padding(.top, 40)
                                
                                Text("No saved trips found")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                
                                Text("Start planning a new trip to save it here")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                
                                Button(action: {
                                    viewModel.createNewEmptyTrip(destination: "")
                                    isPresented = false
                                }) {
                                    HStack {
                                        Image(systemName: "plus")
                                        Text("Create New Trip")
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .padding(.top, 8)
                            } else {
                                Text("No trips match '\(searchText)'")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 20)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .padding()
                    } else {
                        ForEach(filteredTrips) { trip in
                            Button(action: {
                                if let tripID = viewModel.getTripID(byName: trip.destination) {
                                    viewModel.loadTrip(withID: tripID)
                                    isPresented = false
                                }
                            }) {
                                HStack {
                                    Image(systemName: "map.fill")
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                        .frame(width: 40, height: 40)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(trip.destination)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        HStack {
                                            Text("Created: \(formatDate(trip.createdDate))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            Spacer()
                                            
                                            Text("Modified: \(formatDate(trip.lastModifiedDate))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.leading, 4)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    tripToDelete = trip
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                Button {
                                    tripToRename = trip
                                    newTripName = trip.destination
                                    showingRenameDialog = true
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    if let tripID = viewModel.getTripID(byName: trip.destination) {
                                        viewModel.duplicateTrip(withID: tripID)
                                        updateTripsList()
                                    }
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                                .tint(.green)
                            }
                            .contextMenu {
                                Button(action: {
                                    tripToRename = trip
                                    newTripName = trip.destination
                                    showingRenameDialog = true
                                }) {
                                    Label("Rename", systemImage: "pencil")
                                }
                                
                                Button(action: {
                                    if let tripID = viewModel.getTripID(byName: trip.destination) {
                                        viewModel.duplicateTrip(withID: tripID)
                                        updateTripsList()
                                    }
                                }) {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                                
                                Button(role: .destructive, action: {
                                    tripToDelete = trip
                                    showingDeleteConfirmation = true
                                }) {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Saved Trips")
            .onAppear {
                updateTripsList()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.createNewEmptyTrip(destination: "")
                        isPresented = false
                    }) {
                        Label("New Trip", systemImage: "plus")
                    }
                }
            }
            .alert("Rename Trip", isPresented: $showingRenameDialog) {
                TextField("Trip Name", text: $newTripName)
                    .autocapitalization(.words)
                
                Button("Cancel", role: .cancel) {
                    tripToRename = nil
                    newTripName = ""
                }
                
                Button("Rename") {
                    if let trip = tripToRename, !newTripName.isEmpty {
                        if let tripID = viewModel.getTripID(byName: trip.destination) {
                            viewModel.renameTrip(withID: tripID, newName: newTripName)
                            updateTripsList()
                        }
                    }
                    tripToRename = nil
                    newTripName = ""
                }
                .fontWeight(.semibold)
            } message: {
                Text("Enter a new name for this trip.")
            }
            .alert("Delete Trip", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    tripToDelete = nil
                }
                
                Button("Delete", role: .destructive) {
                    if let trip = tripToDelete {
                        if let tripID = viewModel.getTripID(byName: trip.destination) {
                            viewModel.deleteTrip(withID: tripID)
                            updateTripsList()
                        }
                    }
                    tripToDelete = nil
                }
                .fontWeight(.semibold)
            } message: {
                if let trip = tripToDelete {
                    Text("Are you sure you want to delete '\(trip.destination)'? This action cannot be undone.")
                } else {
                    Text("Are you sure you want to delete this trip? This action cannot be undone.")
                }
            }
        }
        .accentColor(.primary)
    }
    
    private func updateTripsList() {
        trips = viewModel.getAllSavedTrips()
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Extensions for UTType (for fileImporter)
extension UTType {
    static let json = UTType(importedAs: "public.json")
}
