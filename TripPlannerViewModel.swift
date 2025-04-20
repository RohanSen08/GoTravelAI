//
//  TripPlannerViewModel.swift
//  TripPlannerApp
//
//  Created by Rohan Sen on 4/7/25.
//

import SwiftUI
import MapKit
import Foundation


// MARK: - Models

struct Location: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var description: String
    var coordinate: CLLocationCoordinate2D
    var photoURL: URL?
    var placeID: String?
    var day: Int
    var order: Int
    
    static func == (lhs: Location, rhs: Location) -> Bool {
        lhs.id == rhs.id
    }
}

struct TripDay: Identifiable {
    let id = UUID()
    let day: Int
    var locations: [Location]
}

class TripPlannerViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var locations: [Location] = []
    @Published var tripDays: [TripDay] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var debugInfo: String? // Added for debugging
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @Published var numberOfDays: Int = 3 // Default to 3 days
    
    func planTrip() {
        guard !searchQuery.isEmpty else { return }
        
        isLoading = true
        error = nil
        debugInfo = nil
        
        let prompt = """
        Plan a detailed trip to \(searchQuery) with the following requirements:
        1. Create a \(numberOfDays)-day itinerary
        2. For each day, recommend 3-5 locations to visit
        3. Include brief descriptions for each location
        4. Provide exact coordinates (latitude and longitude) for each location
        5. IMPORTANT: For each location, include a precise and valid Google Maps place_id that can be used with the Places API

        Format the response as a JSON object with this structure:
        {
          "days": [
            {
              "day": 1,
              "locations": [
                {
                  "name": "Location name",
                  "description": "Brief description",
                  "latitude": 00.0000,
                  "longitude": 00.0000,
                  "place_id": "GoogleMapsPlaceIDString"
                }
              ]
            }
          ]
        }
        
        Important: Return only the valid JSON with no other text. For the place_id, use accurate Google Maps Place IDs for each location.
        """
        
        getResponseFromGemini(prompt: prompt) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                switch result {
                case .success(let jsonString):
                    self?.parseAndStoreTripData(jsonString: jsonString)
                case .failure(let error):
                    self?.error = error.localizedDescription
                }
            }
        }
    }

    private func getResponseFromGemini(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        // API endpoint for Gemini-Pro model
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(APIKeys.geminiAPIKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Updated request format for Gemini 2.0
        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        [
                            "text": prompt
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "topP": 0.8,
                "topK": 40,
                "maxOutputTokens": 4096
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No data received", code: 0)))
                return
            }
            
            // For debugging - print the raw response
            if let responseString = String(data: data, encoding: .utf8) {
                print("Raw Gemini API response: \(responseString)")
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {
                    completion(.success(text))
                } else {
                    if let responseString = String(data: data, encoding: .utf8),
                       responseString.contains("error") {
                        completion(.failure(NSError(domain: "API Error: \(responseString)", code: 0)))
                    } else {
                        completion(.failure(NSError(domain: "Invalid response format", code: 0)))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    
    private func parseAndStoreTripData(jsonString: String) {
        // Extract JSON from the response if wrapped in markdown or other text
        var cleanedJsonString = jsonString
        if let jsonStartIndex = jsonString.range(of: "{")?.lowerBound,
           let jsonEndIndex = jsonString.range(of: "}", options: .backwards)?.upperBound {
            let jsonRange = jsonStartIndex..<jsonEndIndex
            cleanedJsonString = String(jsonString[jsonRange])
        }
        
        guard let jsonData = cleanedJsonString.data(using: .utf8) else {
            self.error = "Failed to convert response to data"
            return
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let days = json["days"] as? [[String: Any]] else {
                self.error = "Failed to parse JSON structure"
                return
            }
            
            var allLocations: [Location] = []
            var newTripDays: [TripDay] = []
            
            for dayData in days {
                guard let dayNumber = dayData["day"] as? Int,
                      let locationsData = dayData["locations"] as? [[String: Any]] else {
                    continue
                }
                
                var dayLocations: [Location] = []
                
                for (index, locationData) in locationsData.enumerated() {
                    guard let name = locationData["name"] as? String,
                          let description = locationData["description"] as? String,
                          let latitude = locationData["latitude"] as? Double,
                          let longitude = locationData["longitude"] as? Double else {
                        continue
                    }
                    
                    // Extract place_id if available
                    let placeID = locationData["place_id"] as? String
                    
                    let location = Location(
                        name: name,
                        description: description,
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                        photoURL: nil,
                        placeID: placeID,
                        day: dayNumber,
                        order: index
                    )
                    
                    dayLocations.append(location)
                    allLocations.append(location)
                    
                    // First, try to verify if the place ID exists
                    if let placeID = placeID {
                        self.verifyAndFetchPhoto(location: location, placeID: placeID)
                    } else {
                        // Fallback to search by name
                        self.searchAndFetchPhoto(location: location)
                    }
                }
                
                let tripDay = TripDay(day: dayNumber, locations: dayLocations)
                newTripDays.append(tripDay)
            }
            
            self.locations = allLocations
            self.tripDays = newTripDays
            
            // Center the map on the first location
            if let firstLocation = allLocations.first {
                self.region = MKCoordinateRegion(
                    center: firstLocation.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            }
            
        } catch {
            self.error = "Failed to parse response: \(error.localizedDescription)"
        }
    }
    
    func verifyAndFetchPhoto(location: Location, placeID: String) {
        // Verify place ID and fetch photo
        let placeDetailsURL = URL(string: "https://maps.googleapis.com/maps/api/place/details/json?place_id=\(placeID)&fields=name,photos&key=\(APIKeys.googlePlacesAPIKey)")!
        
        print("Verifying place ID: \(placeID) for location: \(location.name)")
        
        URLSession.shared.dataTask(with: placeDetailsURL) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Place details error for \(location.name): \(error.localizedDescription)")
                // Fallback to search by name
                self.searchAndFetchPhoto(location: location)
                return
            }
            
            guard let data = data else {
                print("No data received for place details: \(location.name)")
                self.searchAndFetchPhoto(location: location)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("Place details response for \(location.name): \(json)")
                    
                    if let status = json["status"] as? String, status == "OK",
                       let result = json["result"] as? [String: Any],
                       let photos = result["photos"] as? [[String: Any]],
                       let firstPhoto = photos.first,
                       let photoReference = firstPhoto["photo_reference"] as? String {
                        
                        // Now fetch the actual photo
                        let photoURL = URL(string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=\(photoReference)&key=\(APIKeys.googlePlacesAPIKey)")
                        
                        DispatchQueue.main.async {
                            print("Photo URL for \(location.name): \(String(describing: photoURL))")
                            self.updatePhotoURL(for: location, with: photoURL)
                        }
                    } else {
                        print("No photos found in place details for \(location.name), falling back to search")
                        self.searchAndFetchPhoto(location: location)
                    }
                } else {
                    print("Failed to parse place details JSON for \(location.name)")
                    self.searchAndFetchPhoto(location: location)
                }
            } catch {
                print("Error parsing place details for \(location.name): \(error.localizedDescription)")
                self.searchAndFetchPhoto(location: location)
            }
        }.resume()
    }
    
    func searchAndFetchPhoto(location: Location) {
        print("Searching for location by name: \(location.name)")
        let nameEncoded = location.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? location.name
        let searchURL = URL(string: "https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=\(nameEncoded)&inputtype=textquery&fields=photos,place_id&key=\(APIKeys.googlePlacesAPIKey)")!
        
        URLSession.shared.dataTask(with: searchURL) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Search error for \(location.name): \(error.localizedDescription)")
                self.fetchPlaceNearbyCoordinates(location: location)
                return
            }
            
            guard let data = data else {
                print("No data received for search: \(location.name)")
                self.fetchPlaceNearbyCoordinates(location: location)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("Search response for \(location.name): \(json)")
                    
                    if let status = json["status"] as? String, status == "OK",
                       let candidates = json["candidates"] as? [[String: Any]],
                       let firstPlace = candidates.first {
                        
                        if let placeID = firstPlace["place_id"] as? String {
                            print("Found place ID via search for \(location.name): \(placeID)")
                            
                            // Store the place ID for future use
                            DispatchQueue.main.async {
                                if let index = self.locations.firstIndex(where: { $0.id == location.id }) {
                                    self.locations[index].placeID = placeID
                                }
                            }
                            
                            // Check if there are photos directly in the search results
                            if let photos = firstPlace["photos"] as? [[String: Any]],
                               let firstPhoto = photos.first,
                               let photoReference = firstPhoto["photo_reference"] as? String {
                                
                                let photoURL = URL(string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=\(photoReference)&key=\(APIKeys.googlePlacesAPIKey)")
                                
                                DispatchQueue.main.async {
                                    print("Photo URL from search for \(location.name): \(String(describing: photoURL))")
                                    self.updatePhotoURL(for: location, with: photoURL)
                                }
                            } else {
                                // Fetch photo using the found place ID
                                self.fetchPhotoForPlaceID(location: location, placeID: placeID)
                            }
                        } else {
                            print("No place ID found in search results for \(location.name)")
                            self.fetchPlaceNearbyCoordinates(location: location)
                        }
                    } else {
                        print("Search did not return valid candidates for \(location.name)")
                        self.fetchPlaceNearbyCoordinates(location: location)
                    }
                } else {
                    print("Failed to parse search JSON for \(location.name)")
                    self.fetchPlaceNearbyCoordinates(location: location)
                }
            } catch {
                print("Error parsing search results for \(location.name): \(error.localizedDescription)")
                self.fetchPlaceNearbyCoordinates(location: location)
            }
        }.resume()
    }
    
    func fetchPhotoForPlaceID(location: Location, placeID: String) {
        let photoDetailsURL = URL(string: "https://maps.googleapis.com/maps/api/place/details/json?place_id=\(placeID)&fields=photos&key=\(APIKeys.googlePlacesAPIKey)")!
        
        URLSession.shared.dataTask(with: photoDetailsURL) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Photo details error for \(location.name): \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received for photo details: \(location.name)")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let result = json["result"] as? [String: Any],
                   let photos = result["photos"] as? [[String: Any]],
                   let firstPhoto = photos.first,
                   let photoReference = firstPhoto["photo_reference"] as? String {
                    
                    let photoURL = URL(string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=\(photoReference)&key=\(APIKeys.googlePlacesAPIKey)")
                    
                    DispatchQueue.main.async {
                        print("Photo URL from details for \(location.name): \(String(describing: photoURL))")
                        self.updatePhotoURL(for: location, with: photoURL)
                    }
                } else {
                    print("No photos found in place details for \(location.name)")
                }
            } catch {
                print("Error parsing photo details for \(location.name): \(error.localizedDescription)")
            }
        }.resume()
    }
    
    func fetchPlaceNearbyCoordinates(location: Location) {
        // Try to find a place near the coordinates
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        let nearbyURL = URL(string: "https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=\(lat),\(lng)&radius=100&key=\(APIKeys.googlePlacesAPIKey)")!
        
        print("Searching for nearby places at \(lat),\(lng) for \(location.name)")
        
        URLSession.shared.dataTask(with: nearbyURL) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Nearby search error for \(location.name): \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received for nearby search: \(location.name)")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   let firstPlace = results.first,
                   let placeID = firstPlace["place_id"] as? String {
                    
                    print("Found nearby place ID for \(location.name): \(placeID)")
                    
                    // Store the place ID
                    DispatchQueue.main.async {
                        if let index = self.locations.firstIndex(where: { $0.id == location.id }) {
                            self.locations[index].placeID = placeID
                        }
                    }
                    
                    // Check if there are photos directly in the nearby results
                    if let photos = firstPlace["photos"] as? [[String: Any]],
                       let firstPhoto = photos.first,
                       let photoReference = firstPhoto["photo_reference"] as? String {
                        
                        let photoURL = URL(string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=\(photoReference)&key=\(APIKeys.googlePlacesAPIKey)")
                        
                        DispatchQueue.main.async {
                            print("Photo URL from nearby search for \(location.name): \(String(describing: photoURL))")
                            self.updatePhotoURL(for: location, with: photoURL)
                        }
                    } else {
                        // Fetch photo using the found place ID
                        self.fetchPhotoForPlaceID(location: location, placeID: placeID)
                    }
                } else {
                    print("No nearby places found for \(location.name)")
                    // Try to use a stock photo service as last resort
                    self.useStockImage(for: location)
                }
            } catch {
                print("Error parsing nearby search results for \(location.name): \(error.localizedDescription)")
                self.useStockImage(for: location)
            }
        }.resume()
    }
    
    func useStockImage(for location: Location) {
        // As a last resort, we could use a stock image service or a placeholder
        // For example, using Unsplash's API to get a relevant image
        // This is just an example - you might want to implement your own fallback
        let query = location.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "landmark"
        let stockImageURL = URL(string: "https://source.unsplash.com/400x300/?\(query)")
        
        DispatchQueue.main.async {
            print("Using stock image for \(location.name): \(String(describing: stockImageURL))")
            self.updatePhotoURL(for: location, with: stockImageURL)
        }
    }
    
    func updatePhotoURL(for location: Location, with photoURL: URL?) {
        // Update the photo URL in both locations array and tripDays
        if let index = self.locations.firstIndex(where: { $0.id == location.id }) {
            self.locations[index].photoURL = photoURL
        }
        
        if let dayIndex = self.tripDays.firstIndex(where: { $0.day == location.day }),
           let locIndex = self.tripDays[dayIndex].locations.firstIndex(where: { $0.id == location.id }) {
            self.tripDays[dayIndex].locations[locIndex].photoURL = photoURL
        }
    }
    
    func moveLocation(from source: IndexSet, to destination: Int, in day: Int) {
        guard let dayIndex = tripDays.firstIndex(where: { $0.day == day }) else { return }
        
        var locations = tripDays[dayIndex].locations
        locations.move(fromOffsets: source, toOffset: destination)
        
        // Update order
        for (index, var location) in locations.enumerated() {
            location.order = index
            
            // Also update in main locations array
            if let mainIndex = self.locations.firstIndex(where: { $0.id == location.id }) {
                self.locations[mainIndex].order = index
            }
        }
        
        tripDays[dayIndex].locations = locations
    }
    
    func moveLocationToDay(location: Location, toDay: Int) {
        // Remove from current day
        if let currentDayIndex = tripDays.firstIndex(where: { $0.day == location.day }) {
            tripDays[currentDayIndex].locations.removeAll(where: { $0.id == location.id })
            
            // Reorder remaining locations
            for (index, var loc) in tripDays[currentDayIndex].locations.enumerated() {
                loc.order = index
                
                if let mainIndex = self.locations.firstIndex(where: { $0.id == loc.id }) {
                    self.locations[mainIndex].order = index
                }
            }
        }
        
        // Add to new day
        if let newDayIndex = tripDays.firstIndex(where: { $0.day == toDay }) {
            var updatedLocation = location
            updatedLocation.day = toDay
            updatedLocation.order = tripDays[newDayIndex].locations.count
            
            tripDays[newDayIndex].locations.append(updatedLocation)
            
            // Update in main locations array
            if let mainIndex = self.locations.firstIndex(where: { $0.id == location.id }) {
                self.locations[mainIndex].day = toDay
                self.locations[mainIndex].order = updatedLocation.order
            }
        }
        
        // Save changes
        saveCurrentTrip()
    }
}

// MARK: - Codable Models for Persistence

// Extend Location to be Codable
extension Location: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, description, latitude, longitude, photoURLString, placeID, day, order
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let photoURLString = try container.decodeIfPresent(String.self, forKey: .photoURLString)
        photoURL = photoURLString != nil ? URL(string: photoURLString!) : nil
        placeID = try container.decodeIfPresent(String.self, forKey: .placeID)
        day = try container.decode(Int.self, forKey: .day)
        order = try container.decode(Int.self, forKey: .order)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encodeIfPresent(photoURL?.absoluteString, forKey: .photoURLString)
        try container.encodeIfPresent(placeID, forKey: .placeID)
        try container.encode(day, forKey: .day)
        try container.encode(order, forKey: .order)
    }
}

// Extend TripDay to be Codable
extension TripDay: Codable {
    enum CodingKeys: String, CodingKey {
        case id, day, locations
    }
}

// Add a Trip model to store trip metadata
struct Trip: Codable, Identifiable {
    let id = UUID()
    var destination: String
    var createdDate: Date
    var lastModifiedDate: Date
    var mapRegion: MapRegionData
    var numberOfDays: Int = 3 // Default to 3 days
    
    
    struct MapRegionData: Codable {
        var centerLatitude: Double
        var centerLongitude: Double
        var latitudeDelta: Double
        var longitudeDelta: Double
        
        init(from region: MKCoordinateRegion) {
            centerLatitude = region.center.latitude
            centerLongitude = region.center.longitude
            latitudeDelta = region.span.latitudeDelta
            longitudeDelta = region.span.longitudeDelta
        }
        
        func toCoordinateRegion() -> MKCoordinateRegion {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude),
                span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
            )
        }
    }
}

// Replace the fetchDynamicFunFacts function in TripPlannerViewModel.swift
extension TripPlannerViewModel {
    // Function to fetch fun facts about a destination using Gemini API
    func fetchDynamicFunFacts(for destination: String, completion: @escaping ([String]) -> Void) {
        guard !destination.isEmpty else {
            completion([])
            return
        }
        
        // Default facts in case API call fails
        let defaultFacts = [
            "This destination has unique cultural attractions waiting to be explored.",
            "Local cuisine is an important part of experiencing this destination.",
            "Consider learning a few basic phrases in the local language before your trip."
        ]
        
        // Create prompt for Gemini
        let prompt = """
        Generate exactly 3 interesting and educational fun facts about \(destination) as a travel destination.
        Each fact should be unique and provide valuable information for travelers.
        Format the response as a JSON array with exactly 3 facts, like this:
        ["Fact 1", "Fact 2", "Fact 3"]
        Keep each fact to 1-2 sentences and make them engaging. Return ONLY the JSON array with no additional text.
        """
        
        // API endpoint for Gemini-Pro model
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(APIKeys.geminiAPIKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Prepare the request body
        let body: [String: Any] = [
            "model": "gemini-2.0-flash",
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        [
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            DispatchQueue.main.async {
                completion(defaultFacts)
            }
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error fetching fun facts: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(defaultFacts)
                }
                return
            }
            
            guard let data = data else {
                print("No data received when fetching fun facts")
                DispatchQueue.main.async {
                    completion(defaultFacts)
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {
                    
                    // The response might be wrapped in ```json ... ``` or similar, so extract the actual JSON array
                    var cleanedJsonString = text
                    if let jsonStartIndex = text.range(of: "[")?.lowerBound,
                       let jsonEndIndex = text.range(of: "]", options: .backwards)?.upperBound {
                        let jsonRange = jsonStartIndex..<jsonEndIndex
                        cleanedJsonString = String(text[jsonRange])
                    }
                    
                    if let factsData = cleanedJsonString.data(using: .utf8),
                       let facts = try? JSONSerialization.jsonObject(with: factsData) as? [String],
                       !facts.isEmpty {
                        DispatchQueue.main.async {
                            completion(facts)
                        }
                    } else {
                        // Parse failed, try to extract facts manually
                        let manuallyExtractedFacts = self.extractFactsFromText(text)
                        if !manuallyExtractedFacts.isEmpty {
                            DispatchQueue.main.async {
                                completion(manuallyExtractedFacts)
                            }
                        } else {
                            DispatchQueue.main.async {
                                completion(defaultFacts)
                            }
                        }
                    }
                } else {
                    print("Invalid response format from Gemini API")
                    DispatchQueue.main.async {
                        completion(defaultFacts)
                    }
                }
            } catch {
                print("Error parsing Gemini API response: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(defaultFacts)
                }
            }
        }.resume()
    }
    
    // Helper function to extract facts from text when JSON parsing fails
    private func extractFactsFromText(_ text: String) -> [String] {
        // Look for patterns like "1. Fact" or numbered lists
        var facts: [String] = []
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            
            // Check for numbered lines, quoted text, or just plain sentences
            if trimmedLine.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) != nil {
                // Handle numbered lists (e.g., "1. Fact")
                if let fact = trimmedLine.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
                    let factText = trimmedLine[fact.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !factText.isEmpty {
                        facts.append(factText)
                    }
                }
            } else if trimmedLine.hasPrefix("\"") && trimmedLine.hasSuffix("\"") {
                // Handle quoted text
                let factText = trimmedLine.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
                if !factText.isEmpty {
                    facts.append(factText)
                }
            } else if !trimmedLine.contains(":") && !trimmedLine.contains("{") && !trimmedLine.contains("}") && trimmedLine.count > 15 {
                // Likely a plain fact sentence
                facts.append(trimmedLine)
            }
        }
        
        // If we've found more than 3 potential facts, only keep the first 3
        if facts.count > 3 {
            facts = Array(facts.prefix(3))
        }
        
        return facts
    }
}

// MARK: - Data Persistence Extension
extension TripPlannerViewModel {
    
    // MARK: - Storage Keys
    private enum StorageKeys {
        static let savedTripsIDs = "savedTripsIDs"
        static let activeTripID = "activeTripID"
        static let tripPrefix = "trip_"
    }
    
    // MARK: - Save Current Trip
    func saveCurrentTrip() {
        if let activeTripID = UserDefaults.standard.string(forKey: StorageKeys.activeTripID) {
            // Update existing trip
            saveTrip(withID: activeTripID)
        } else if !locations.isEmpty {
            // Create new trip if we have locations but no active ID
            saveTripAsNew(withName: searchQuery)
        }
    }
    
    // MARK: - Save New Trip
    func saveTripAsNew(withName customName: String) {
        guard !locations.isEmpty else { return }
        
        do {
            let tripName = customName.isEmpty ? searchQuery : customName
            let tripID = UUID().uuidString
            
            // Create trip object
            let trip = Trip(
                destination: tripName,
                createdDate: Date(),
                lastModifiedDate: Date(),
                mapRegion: Trip.MapRegionData(from: region)
            )
            
            // Save trip data
            try saveTrip(trip: trip, withID: tripID)
            
            // Set as active trip
            UserDefaults.standard.set(tripID, forKey: StorageKeys.activeTripID)
            
            print("Successfully saved new trip: \(tripName) with ID: \(tripID)")
        } catch {
            self.error = "Failed to save new trip: \(error.localizedDescription)"
            print("Error saving new trip: \(error)")
        }
    }
    
    // MARK: - Save Trip with ID
    private func saveTrip(withID tripID: String) {
        do {
            // Create or update trip object
            var trip: Trip
            
            if let existingTripData = UserDefaults.standard.data(forKey: "\(StorageKeys.tripPrefix)\(tripID)"),
               let existingTrip = try? JSONDecoder().decode(Trip.self, from: existingTripData) {
                // Update existing trip
                trip = existingTrip
                trip.lastModifiedDate = Date()
                trip.mapRegion = Trip.MapRegionData(from: region)
            } else {
                // Create new trip metadata
                trip = Trip(
                    destination: searchQuery,
                    createdDate: Date(),
                    lastModifiedDate: Date(),
                    mapRegion: Trip.MapRegionData(from: region),
                    numberOfDays: numberOfDays
                )
            }
            
            try saveTrip(trip: trip, withID: tripID)
            
        } catch {
            self.error = "Failed to save trip: \(error.localizedDescription)"
            print("Error saving trip: \(error)")
        }
    }
    
    // MARK: - Save Trip Helper
    private func saveTrip(trip: Trip, withID tripID: String) throws {
        // Save trip metadata
        let tripData = try JSONEncoder().encode(trip)
        UserDefaults.standard.set(tripData, forKey: "\(StorageKeys.tripPrefix)\(tripID)")
        
        // Save locations
        let locationsData = try JSONEncoder().encode(locations)
        UserDefaults.standard.set(locationsData, forKey: "\(StorageKeys.tripPrefix)\(tripID)_locations")
        
        // Save trip days
        let tripDaysData = try JSONEncoder().encode(tripDays)
        UserDefaults.standard.set(tripDaysData, forKey: "\(StorageKeys.tripPrefix)\(tripID)_days")
        
        // Add to saved trips list if not already there
        var savedTripsIDs = UserDefaults.standard.stringArray(forKey: StorageKeys.savedTripsIDs) ?? []
        if !savedTripsIDs.contains(tripID) {
            savedTripsIDs.append(tripID)
            UserDefaults.standard.set(savedTripsIDs, forKey: StorageKeys.savedTripsIDs)
        }
    }
    
    // MARK: - Load Trip
    func loadTrip(withID tripID: String) {
        do {
            // Load trip metadata
            guard let tripData = UserDefaults.standard.data(forKey: "\(StorageKeys.tripPrefix)\(tripID)"),
                  let trip = try? JSONDecoder().decode(Trip.self, from: tripData) else {
                throw NSError(domain: "TripPlannerApp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load trip data"])
            }
            
            // Load locations
            guard let locationsData = UserDefaults.standard.data(forKey: "\(StorageKeys.tripPrefix)\(tripID)_locations"),
                  let savedLocations = try? JSONDecoder().decode([Location].self, from: locationsData) else {
                throw NSError(domain: "TripPlannerApp", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load locations"])
            }
            
            // Load trip days
            guard let tripDaysData = UserDefaults.standard.data(forKey: "\(StorageKeys.tripPrefix)\(tripID)_days"),
                  let savedTripDays = try? JSONDecoder().decode([TripDay].self, from: tripDaysData) else {
                throw NSError(domain: "TripPlannerApp", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to load trip days"])
            }
            
            // Set as active trip
            UserDefaults.standard.set(tripID, forKey: StorageKeys.activeTripID)
            
            // Update view model state
            self.searchQuery = trip.destination
            self.locations = savedLocations
            self.tripDays = savedTripDays
            self.region = trip.mapRegion.toCoordinateRegion()
            self.numberOfDays = trip.numberOfDays // Add this line
            
            print("Successfully loaded trip: \(trip.destination)")
        } catch {
            self.error = "Failed to load trip: \(error.localizedDescription)"
            print("Error loading trip: \(error)")
        }
    }
    
    // MARK: - Get All Saved Trips
    func getAllSavedTrips() -> [Trip] {
        let savedTripsIDs = UserDefaults.standard.stringArray(forKey: StorageKeys.savedTripsIDs) ?? []
        var trips: [Trip] = []
        
        for tripID in savedTripsIDs {
            if let tripData = UserDefaults.standard.data(forKey: "\(StorageKeys.tripPrefix)\(tripID)"),
               let trip = try? JSONDecoder().decode(Trip.self, from: tripData) {
                trips.append(trip)
            }
        }
        
        // Sort by most recently modified
        return trips.sorted(by: { $0.lastModifiedDate > $1.lastModifiedDate })
    }
    
    // MARK: - Delete Trip
    func deleteTrip(withID tripID: String) {
        // Remove from saved trips list
        var savedTripsIDs = UserDefaults.standard.stringArray(forKey: StorageKeys.savedTripsIDs) ?? []
        savedTripsIDs.removeAll(where: { $0 == tripID })
        UserDefaults.standard.set(savedTripsIDs, forKey: StorageKeys.savedTripsIDs)
        
        // Delete trip data
        UserDefaults.standard.removeObject(forKey: "\(StorageKeys.tripPrefix)\(tripID)")
        UserDefaults.standard.removeObject(forKey: "\(StorageKeys.tripPrefix)\(tripID)_locations")
        UserDefaults.standard.removeObject(forKey: "\(StorageKeys.tripPrefix)\(tripID)_days")
        
        // If this was the active trip, clear the active trip ID
        if UserDefaults.standard.string(forKey: StorageKeys.activeTripID) == tripID {
            UserDefaults.standard.removeObject(forKey: StorageKeys.activeTripID)
        }
        
        print("Successfully deleted trip with ID: \(tripID)")
    }
    
    // MARK: - Create New Empty Trip
    func createNewEmptyTrip(destination: String) {
        // Clear current data
        self.searchQuery = destination
        self.locations = []
        self.tripDays = []
        
        // Reset to default region
        self.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        
        // Clear active trip reference
        UserDefaults.standard.removeObject(forKey: StorageKeys.activeTripID)
    }
    
    // MARK: - Duplicate Trip
    func duplicateTrip(withID tripID: String, newName: String? = nil) {
        do {
            // Check if original trip exists
            guard let tripData = UserDefaults.standard.data(forKey: "\(StorageKeys.tripPrefix)\(tripID)"),
                  let originalTrip = try? JSONDecoder().decode(Trip.self, from: tripData),
                  let locationsData = UserDefaults.standard.data(forKey: "\(StorageKeys.tripPrefix)\(tripID)_locations"),
                  let tripDaysData = UserDefaults.standard.data(forKey: "\(StorageKeys.tripPrefix)\(tripID)_days") else {
                throw NSError(domain: "TripPlannerApp", code: 4, userInfo: [NSLocalizedDescriptionKey: "Original trip not found"])
            }
            
            // Create new trip ID
            let newTripID = UUID().uuidString
            
            // Create new trip with copied data
            var newTrip = originalTrip
            newTrip.destination = newName ?? "\(originalTrip.destination) (Copy)"
            newTrip.createdDate = Date()
            newTrip.lastModifiedDate = Date()
            
            // Save new trip metadata
            let newTripData = try JSONEncoder().encode(newTrip)
            UserDefaults.standard.set(newTripData, forKey: "\(StorageKeys.tripPrefix)\(newTripID)")
            
            // Copy locations and trip days
            UserDefaults.standard.set(locationsData, forKey: "\(StorageKeys.tripPrefix)\(newTripID)_locations")
            UserDefaults.standard.set(tripDaysData, forKey: "\(StorageKeys.tripPrefix)\(newTripID)_days")
            
            // Add to saved trips list
            var savedTripsIDs = UserDefaults.standard.stringArray(forKey: StorageKeys.savedTripsIDs) ?? []
            savedTripsIDs.append(newTripID)
            UserDefaults.standard.set(savedTripsIDs, forKey: StorageKeys.savedTripsIDs)
            
            print("Successfully duplicated trip: \(originalTrip.destination) as \(newTrip.destination)")
            
        } catch {
            self.error = "Failed to duplicate trip: \(error.localizedDescription)"
            print("Error duplicating trip: \(error)")
        }
    }
    
    // MARK: - Rename Trip
    func renameTrip(withID tripID: String, newName: String) {
        guard !newName.isEmpty,
              let tripData = UserDefaults.standard.data(forKey: "\(StorageKeys.tripPrefix)\(tripID)"),
              var trip = try? JSONDecoder().decode(Trip.self, from: tripData) else {
            self.error = "Cannot rename trip: Trip not found or invalid name"
            return
        }
        
        trip.destination = newName
        trip.lastModifiedDate = Date()
        
        if let encodedTrip = try? JSONEncoder().encode(trip) {
            UserDefaults.standard.set(encodedTrip, forKey: "\(StorageKeys.tripPrefix)\(tripID)")
            
            // Update search query if this is the active trip
            let activeTripID = UserDefaults.standard.string(forKey: StorageKeys.activeTripID)
            if activeTripID == tripID {
                self.searchQuery = newName
            }
            
            print("Successfully renamed trip to: \(newName)")
        } else {
            self.error = "Failed to encode renamed trip"
        }
    }
    
    // MARK: - Get Trip ID By Name
    func getTripID(byName name: String) -> String? {
        let savedTripsIDs = UserDefaults.standard.stringArray(forKey: StorageKeys.savedTripsIDs) ?? []
        
        for tripID in savedTripsIDs {
            if let tripData = UserDefaults.standard.data(forKey: "\(StorageKeys.tripPrefix)\(tripID)"),
               let trip = try? JSONDecoder().decode(Trip.self, from: tripData),
               trip.destination == name {
                return tripID
            }
        }
        
        return nil
    }
    
    // MARK: - Get Active Trip
    func getActiveTrip() -> Trip? {
        guard let activeTripID = UserDefaults.standard.string(forKey: StorageKeys.activeTripID),
              let tripData = UserDefaults.standard.data(forKey: "\(StorageKeys.tripPrefix)\(activeTripID)"),
              let trip = try? JSONDecoder().decode(Trip.self, from: tripData) else {
            return nil
        }
        
        return trip
    }
    
    // MARK: - Load Last Active Trip
    func loadLastActiveTrip() {
        if let activeTripID = UserDefaults.standard.string(forKey: StorageKeys.activeTripID) {
            loadTrip(withID: activeTripID)
        } else {
            // If no active trip, check if there are any saved trips
            let savedTripsIDs = UserDefaults.standard.stringArray(forKey: StorageKeys.savedTripsIDs) ?? []
            if let firstTripID = savedTripsIDs.first {
                loadTrip(withID: firstTripID)
            }
        }
    }
    
    // MARK: - Auto Save
    func setupAutoSave() {
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.locations.isEmpty else { return }
            self.saveCurrentTrip()
        }
    }
    
    // MARK: - App Lifecycle
    func saveBeforeBackground() {
        if !locations.isEmpty {
            saveCurrentTrip()
        }
    }
    
    // MARK: - Export & Import
    func exportTrip(withID tripID: String? = nil) -> Data? {
        let targetTripID = tripID ?? UserDefaults.standard.string(forKey: StorageKeys.activeTripID)
        
        guard let tripID = targetTripID else {
            if !locations.isEmpty {
                // Export current unsaved trip
                do {
                    let exportData: [String: Any] = [
                        "destination": searchQuery,
                        "createdDate": Date().timeIntervalSince1970,
                        "locations": try JSONEncoder().encode(locations),
                        "tripDays": try JSONEncoder().encode(tripDays),
                        "region": [
                            "centerLatitude": region.center.latitude,
                            "centerLongitude": region.center.longitude,
                            "latitudeDelta": region.span.latitudeDelta,
                            "longitudeDelta": region.span.longitudeDelta
                        ]
                    ]
                    
                    return try JSONSerialization.data(withJSONObject: exportData)
                } catch {
                    self.error = "Failed to export trip: \(error.localizedDescription)"
                    return nil
                }
            }
            return nil
        }
        
        // Export existing trip
        do {
            guard let tripData = UserDefaults.standard.data(forKey: "\(StorageKeys.tripPrefix)\(tripID)"),
                  let trip = try? JSONDecoder().decode(Trip.self, from: tripData),
                  let locationsData = UserDefaults.standard.data(forKey: "\(StorageKeys.tripPrefix)\(tripID)_locations"),
                  let tripDaysData = UserDefaults.standard.data(forKey: "\(StorageKeys.tripPrefix)\(tripID)_days") else {
                throw NSError(domain: "TripPlannerApp", code: 5, userInfo: [NSLocalizedDescriptionKey: "Trip not found for export"])
            }
            
            let exportData: [String: Any] = [
                "destination": trip.destination,
                "createdDate": trip.createdDate.timeIntervalSince1970,
                "lastModifiedDate": trip.lastModifiedDate.timeIntervalSince1970,
                "locations": locationsData,
                "tripDays": tripDaysData,
                "region": [
                    "centerLatitude": trip.mapRegion.centerLatitude,
                    "centerLongitude": trip.mapRegion.centerLongitude,
                    "latitudeDelta": trip.mapRegion.latitudeDelta,
                    "longitudeDelta": trip.mapRegion.longitudeDelta
                ]
            ]
            
            return try JSONSerialization.data(withJSONObject: exportData)
        } catch {
            self.error = "Failed to export trip: \(error.localizedDescription)"
            return nil
        }
    }
    
    func importTrip(data: Data) -> Bool {
        do {
            guard let importData = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "TripPlannerApp", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid import data format"])
            }
            
            // Extract destination
            guard let destination = importData["destination"] as? String else {
                throw NSError(domain: "TripPlannerApp", code: 7, userInfo: [NSLocalizedDescriptionKey: "Missing destination in import data"])
            }
            
            // Extract locations
            let locationsData: Data
            if let encodedLocations = importData["locations"] as? Data {
                locationsData = encodedLocations
            } else if let locationsDict = importData["locations"],
                      let encodedLocations = try? JSONSerialization.data(withJSONObject: locationsDict) {
                locationsData = encodedLocations
            } else {
                throw NSError(domain: "TripPlannerApp", code: 8, userInfo: [NSLocalizedDescriptionKey: "Invalid locations data format"])
            }
            
            // Extract trip days
            let tripDaysData: Data
            if let encodedTripDays = importData["tripDays"] as? Data {
                tripDaysData = encodedTripDays
            } else if let tripDaysDict = importData["tripDays"],
                      let encodedTripDays = try? JSONSerialization.data(withJSONObject: tripDaysDict) {
                tripDaysData = encodedTripDays
            } else {
                throw NSError(domain: "TripPlannerApp", code: 9, userInfo: [NSLocalizedDescriptionKey: "Invalid trip days data format"])
            }
            
            // Decode locations and trip days
            let importedLocations = try JSONDecoder().decode([Location].self, from: locationsData)
            let importedTripDays = try JSONDecoder().decode([TripDay].self, from: tripDaysData)
            
            // Extract region if available
            var importedRegion = region
            if let regionData = importData["region"] as? [String: Double],
               let centerLat = regionData["centerLatitude"],
               let centerLng = regionData["centerLongitude"],
               let latDelta = regionData["latitudeDelta"],
               let lngDelta = regionData["longitudeDelta"] {
                
                importedRegion = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng),
                    span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
                )
            }
            
            // Create dates
            let createdDate = Date(timeIntervalSince1970: importData["createdDate"] as? TimeInterval ?? Date().timeIntervalSince1970)
            let lastModifiedDate = Date(timeIntervalSince1970: importData["lastModifiedDate"] as? TimeInterval ?? Date().timeIntervalSince1970)
            
            // Create new trip ID
            let newTripID = UUID().uuidString
            
            // Create trip object
            let trip = Trip(
                destination: destination,
                createdDate: createdDate,
                lastModifiedDate: lastModifiedDate,
                mapRegion: Trip.MapRegionData(from: importedRegion)
            )
            
            // Save trip data
            let tripData = try JSONEncoder().encode(trip)
            UserDefaults.standard.set(tripData, forKey: "\(StorageKeys.tripPrefix)\(newTripID)")
            UserDefaults.standard.set(locationsData, forKey: "\(StorageKeys.tripPrefix)\(newTripID)_locations")
            UserDefaults.standard.set(tripDaysData, forKey: "\(StorageKeys.tripPrefix)\(newTripID)_days")
            
            // Add to saved trips
            var savedTripsIDs = UserDefaults.standard.stringArray(forKey: StorageKeys.savedTripsIDs) ?? []
            savedTripsIDs.append(newTripID)
            UserDefaults.standard.set(savedTripsIDs, forKey: StorageKeys.savedTripsIDs)
            
            // Set as active trip
            UserDefaults.standard.set(newTripID, forKey: StorageKeys.activeTripID)
            
            // Update view model
            self.searchQuery = destination
            self.locations = importedLocations
            self.tripDays = importedTripDays
            self.region = importedRegion
            
            print("Successfully imported trip: \(destination)")
            return true
        } catch {
            self.error = "Failed to import trip: \(error.localizedDescription)"
            print("Error importing trip: \(error)")
            return false
        }
    }
}
