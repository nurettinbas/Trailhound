import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct PlacePickerView: View {
  var editingPlace: SavedPlace?
  var draft: PlaceDraft?
  var onSaved: ((String) -> Void)?

  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Environment(LocationService.self) private var locationService
  @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
  @Query private var places: [SavedPlace]
  @Bindable private var settings = AppSettings.shared

  @State private var name = ""
  @State private var kind: SavedPlaceKind = .home
  @State private var isPrivacyZone = false
  @State private var latitude = 38.4192
  @State private var longitude = 27.1287
  @State private var cameraPosition: MapCameraPosition = .automatic
  @State private var selectedAddress: String?
  @State private var suggestedName: String?
  @State private var isResolvingAddress = false
  @State private var nearbyPlaces: [NearbyPlaceOption] = []
  @State private var isLoadingNearby = false
  @State private var searchQuery = ""
  @State private var searchResults: [NearbyPlaceOption] = []
  @State private var isSearchingPlaces = false
  @State private var coordinateText = ""
  @State private var coordinateError: String?
  @State private var didLoadInitialValues = false
  @State private var geocodeTask: Task<Void, Never>?
  @State private var nearbyTask: Task<Void, Never>?
  @State private var searchTask: Task<Void, Never>?
  @FocusState private var isNameFocused: Bool
  @FocusState private var isSearchFocused: Bool
  @FocusState private var isCoordinateFocused: Bool

  private let geocodingService = GeocodingService()

  private var isEditing: Bool { editingPlace != nil }
  private var isSeededFromDraft: Bool { draft != nil }

  init(
    editingPlace: SavedPlace? = nil,
    draft: PlaceDraft? = nil,
    onSaved: ((String) -> Void)? = nil
  ) {
    self.editingPlace = editingPlace
    self.draft = draft
    self.onSaved = onSaved
  }

  private var selectedCoordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  private var trimmedSearchQuery: String {
    searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var isPlaceSearchActive: Bool {
    trimmedSearchQuery.count >= 2
  }

  private var showsInlineSearchResults: Bool {
    isPlaceSearchActive || isSearchingPlaces
  }

  private var showsNearbySection: Bool {
    !isPlaceSearchActive && (isLoadingNearby || !nearbyPlaces.isEmpty)
  }

  private var locationSectionRowKinds: [LocationSectionRowKind] {
    var rows: [LocationSectionRowKind] = [.search]
    rows.append(.map)
    rows.append(.selected)
    rows.append(.coordinates)
    if let suggestedName, name != suggestedName {
      rows.append(.useAddressAsName)
    }
    rows.append(.useCurrentLocation)
    return rows
  }

  private enum LocationSectionRowKind {
    case search
    case map
    case selected
    case coordinates
    case useAddressAsName
    case useCurrentLocation
  }

  private func locationSectionPosition(_ kind: LocationSectionRowKind) -> GlassRowPosition {
    let rows = locationSectionRowKinds
    guard let index = rows.firstIndex(of: kind) else { return .middle }
    return GlassRowPosition.index(index, in: rows.count)
  }

  private var suggestions: [(name: String, coordinate: CLLocationCoordinate2D, visits: Int)] {
    // Skip expensive frequent-route scan when opening from a trip seed.
    guard !isSeededFromDraft, !isEditing else { return [] }
    return FrequentRoutesService.placeSuggestions(
      from: trips,
      places: places,
      privacyRadius: settings.privacyRadiusMeters
    )
  }

  var body: some View {
    Form {
      if !suggestions.isEmpty && !isEditing && !isSeededFromDraft {
        Section(L10n.placeSuggestionSection) {
          ForEach(Array(suggestions.enumerated()), id: \.element.name) { index, suggestion in
            Button {
              applySuggestion(suggestion)
            } label: {
              HStack {
                VStack(alignment: .leading) {
                  Text(suggestion.name)
                  Text(L10n.placeSuggestionVisits(suggestion.visits))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle")
              }
            }
            .buttonStyle(.plain)
            .glassRow(position: GlassRowPosition.index(index, in: suggestions.count))
          }
        }
      }

      Section {
        TextField(L10n.string("place.name.field"), text: $name)
          .focused($isNameFocused)
          .submitLabel(.done)
          .onSubmit { dismissNameKeyboard() }
          .glassRow(position: .first)

        Picker(L10n.string("place.kind.field"), selection: $kind) {
          ForEach(SavedPlaceKind.allCases, id: \.self) { kind in
            Text(kind.displayName).tag(kind)
          }
        }
        .glassRow(position: .middle)

        Toggle(L10n.string("place.privacy_zone"), isOn: $isPrivacyZone)
          .glassRow(position: .last)
      } header: {
        Text(L10n.string("place.info.section"))
      } footer: {
        Text(L10n.placePrivacyZoneHint)
      }

      Section {
        VStack(alignment: .leading, spacing: 12) {
          locationSearchField

          if showsInlineSearchResults {
            inlineSearchResults
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassRow(position: locationSectionPosition(.search))

        mapPicker
          .glassRow(position: locationSectionPosition(.map))

        selectedLocationCard
          .glassRow(position: locationSectionPosition(.selected))

        coordinateEntryRow
          .glassRow(position: locationSectionPosition(.coordinates))

        if let suggestedName, name != suggestedName {
          Button(L10n.placePickerUseAddressAsName) {
            name = suggestedName
          }
          .glassRow(position: locationSectionPosition(.useAddressAsName))
        }

        Button(L10n.placePickerUseCurrentLocation) {
          useCurrentLocation()
        }
        .glassRow(position: locationSectionPosition(.useCurrentLocation))
      } header: {
        Text(L10n.string("place.location.section"))
      } footer: {
        Text(L10n.placePickerSearchHint)
      }

      if showsNearbySection {
        Section(L10n.placePickerNearbySection) {
          if isLoadingNearby {
            HStack {
              ProgressView()
              Text(L10n.placePickerResolvingAddress)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .glassRow(position: nearbyPlaces.isEmpty ? .only : .first)
          }

          ForEach(Array(nearbyPlaces.enumerated()), id: \.element.id) { index, place in
            Button {
              selectPlaceOption(place)
            } label: {
              placeResultRow(place)
            }
            .buttonStyle(.plain)
            .glassRow(position: nearbyRowPosition(placeIndex: index))
          }
        }
      }

      Section {
        Button(L10n.placePickerSave) {
          dismissNameKeyboard()
          savePlace()
        }
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .glassListRow()
      }
    }
    .navigationTitle(isEditing ? L10n.placePickerEditTitle : L10n.placePickerNewTitle)
    .glassListChrome()
    .dismissKeyboardOnScroll()
    .keyboardDoneToolbar()
    .onAppear {
      if !didLoadInitialValues {
        loadEditingPlaceIfNeeded()
        loadDraftIfNeeded()
        didLoadInitialValues = true
      }
      syncCoordinateTextFromSelection()
      moveCamera(to: selectedCoordinate, animated: false)
      refreshLocationDetails()
    }
    .onDisappear {
      geocodeTask?.cancel()
      nearbyTask?.cancel()
      searchTask?.cancel()
    }
    .onChange(of: searchQuery) { _, _ in
      schedulePlaceSearch()
    }
    .onChange(of: latitude) { _, _ in
      guard !isCoordinateFocused else { return }
      syncCoordinateTextFromSelection()
    }
    .onChange(of: longitude) { _, _ in
      guard !isCoordinateFocused else { return }
      syncCoordinateTextFromSelection()
    }
  }

  private var coordinateEntryRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L10n.placeCoordinatesField)
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(spacing: 10) {
        TextField(L10n.placeCoordinatesPlaceholder, text: $coordinateText)
          .font(.subheadline.monospacedDigit())
          .keyboardType(.numbersAndPunctuation)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .focused($isCoordinateFocused)
          .submitLabel(.go)
          .onSubmit { applyCoordinateText() }

        Button(L10n.placeCoordinatesApply) {
          applyCoordinateText()
        }
        .buttonStyle(.bordered)
        .disabled(coordinateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }

      if let coordinateError {
        Text(coordinateError)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }

  private var locationSearchField: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .font(.body.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      TextField(L10n.placePickerSearchPlaceholder, text: $searchQuery)
        .font(.body)
        .focused($isSearchFocused)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .onSubmit { schedulePlaceSearch() }

      if !searchQuery.isEmpty {
        Button {
          clearPlaceSearch()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.body)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.placePickerSearchClear)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassField(cornerRadius: 12)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(L10n.placePickerSearchPlaceholder)
  }

  @ViewBuilder
  private var inlineSearchResults: some View {
    VStack(alignment: .leading, spacing: 0) {
      if isSearchingPlaces {
        HStack(spacing: 10) {
          ProgressView()
          Text(L10n.placePickerSearchLoading)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
      } else if searchResults.isEmpty {
        Text(L10n.placePickerSearchEmpty)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 8)
      } else {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(searchResults) { place in
              Button {
                selectPlaceOption(place)
              } label: {
                placeResultRow(place)
                  .padding(.vertical, 10)
              }
              .buttonStyle(.plain)

              if place.id != searchResults.last?.id {
                Divider()
              }
            }
          }
        }
        .frame(maxHeight: 280)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var nearbyRowCount: Int {
    (isLoadingNearby ? 1 : 0) + nearbyPlaces.count
  }

  private func nearbyRowPosition(placeIndex: Int) -> GlassRowPosition {
    let offset = isLoadingNearby ? 1 : 0
    return GlassRowPosition.index(placeIndex + offset, in: nearbyRowCount)
  }

  private var mapPicker: some View {
    MapReader { proxy in
      ZStack {
        Map(position: $cameraPosition, interactionModes: .all)
          .onMapCameraChange(frequency: .onEnd) { context in
            updateSelection(from: context.region.center)
          }

        centerPin

        VStack {
          Spacer()
          Text(L10n.placePickerMoveMapHint)
            .font(.caption2.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(.bottom, 10)
        }
        .allowsHitTesting(false)
      }
      .contentShape(Rectangle())
      .onTapGesture { point in
        guard let coordinate = proxy.convert(point, from: .local) else { return }
        moveCamera(to: coordinate)
        refreshLocationDetails()
      }
    }
    .frame(height: 260)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .padding(.top, 4)
    .padding(.bottom, 8)
    .accessibilityLabel(L10n.placePickerSelectedLocation)
    .accessibilityValue(selectedLocationSummary)
  }

  private var centerPin: some View {
    VStack(spacing: 0) {
      Image(systemName: "mappin.circle.fill")
        .font(.system(size: 40))
        .foregroundStyle(.red)
        .background(Circle().fill(.white).padding(4))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        .accessibilityHidden(true)

      Ellipse()
        .fill(.black.opacity(0.18))
        .frame(width: 14, height: 5)
        .offset(y: 2)
    }
    .offset(y: -20)
    .allowsHitTesting(false)
  }

  private func placeResultRow(_ place: NearbyPlaceOption) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "mappin.and.ellipse")
        .foregroundStyle(.blue)
        .padding(.top, 2)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(place.name)
          .font(.body.weight(.medium))
          .foregroundStyle(.primary)
        if let subtitle = place.subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(placeOptionAccessibilityLabel(place))
  }

  private func placeOptionAccessibilityLabel(_ place: NearbyPlaceOption) -> String {
    if let subtitle = place.subtitle, !subtitle.isEmpty {
      return "\(place.name), \(subtitle)"
    }
    return place.name
  }

  private var selectedLocationCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(L10n.placePickerSelectedLocation, systemImage: kind.systemImage)
        .font(.subheadline.weight(.semibold))

      if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(name)
          .font(.headline)
      }

      Text(DateFormatters.formatCoordinate(selectedCoordinate))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)

      if isResolvingAddress {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(L10n.placePickerResolvingAddress)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else if let selectedAddress {
        Text(selectedAddress)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(selectedLocationSummary)
  }

  private var selectedLocationSummary: String {
    var parts = [name, DateFormatters.formatCoordinate(selectedCoordinate), selectedAddress]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if parts.isEmpty {
      parts = [DateFormatters.formatCoordinate(selectedCoordinate)]
    }
    return parts.joined(separator: ", ")
  }

  private func loadEditingPlaceIfNeeded() {
    guard let editingPlace else { return }
    name = editingPlace.name
    kind = editingPlace.kind
    isPrivacyZone = editingPlace.isPrivacyZone
    latitude = editingPlace.latitude
    longitude = editingPlace.longitude
  }

  private func loadDraftIfNeeded() {
    guard editingPlace == nil, let draft else { return }
    name = draft.name
    kind = draft.kind
    isPrivacyZone = draft.kind == .home
    latitude = draft.latitude
    longitude = draft.longitude
    selectedAddress = draft.address
    if !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      suggestedName = draft.name
    }
  }

  private func syncCoordinateTextFromSelection() {
    coordinateText = CoordinateParsing.format(selectedCoordinate)
    coordinateError = nil
  }

  private func applyCoordinateText() {
    dismissNameKeyboard()
    guard let coordinate = CoordinateParsing.parse(coordinateText) else {
      coordinateError = L10n.placeCoordinatesInvalid
      return
    }
    coordinateError = nil
    moveCamera(to: coordinate)
    refreshLocationDetails()
    syncCoordinateTextFromSelection()
  }

  private func updateSelection(from coordinate: CLLocationCoordinate2D) {
    latitude = coordinate.latitude
    longitude = coordinate.longitude
    refreshLocationDetails()
  }

  private func moveCamera(to coordinate: CLLocationCoordinate2D, animated: Bool = true) {
    let region = MKCoordinateRegion(
      center: coordinate,
      span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    if animated {
      withAnimation(.easeInOut(duration: 0.25)) {
        cameraPosition = .region(region)
      }
    } else {
      cameraPosition = .region(region)
    }
    latitude = coordinate.latitude
    longitude = coordinate.longitude
  }

  private func useCurrentLocation() {
    guard let location = locationService.lastLocation else { return }
    moveCamera(to: location.coordinate)
    refreshLocationDetails()
  }

  private func refreshLocationDetails() {
    scheduleAddressLookup()
    if !isPlaceSearchActive {
      loadNearbyPlaces()
    }
  }

  private func scheduleAddressLookup() {
    geocodeTask?.cancel()
    let coordinate = selectedCoordinate
    isResolvingAddress = true

    geocodeTask = Task {
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }

      let result = await geocodingService.lookupPlace(
        at: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
      )
      guard !Task.isCancelled else { return }

      await MainActor.run {
        selectedAddress = result.address
        suggestedName = result.suggestedName
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let suggestedName,
           !suggestedName.isEmpty {
          name = suggestedName
        }
        isResolvingAddress = false
      }
    }
  }

  private func loadNearbyPlaces() {
    nearbyTask?.cancel()
    let coordinate = selectedCoordinate
    isLoadingNearby = true

    nearbyTask = Task {
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else { return }

      let results = await geocodingService.nearbyPointsOfInterest(around: coordinate)
      guard !Task.isCancelled else { return }

      await MainActor.run {
        guard !isPlaceSearchActive else { return }
        nearbyPlaces = results
        isLoadingNearby = false
      }
    }
  }

  private func schedulePlaceSearch() {
    searchTask?.cancel()

    let query = trimmedSearchQuery
    guard query.count >= 2 else {
      searchResults = []
      isSearchingPlaces = false
      loadNearbyPlaces()
      return
    }

    isSearchingPlaces = true
    let coordinate = selectedCoordinate

    searchTask = Task {
      try? await Task.sleep(for: .milliseconds(375))
      guard !Task.isCancelled else { return }

      let results = await geocodingService.searchPlaces(query: query, near: coordinate)
      guard !Task.isCancelled else { return }

      await MainActor.run {
        guard trimmedSearchQuery == query else { return }
        searchResults = results
        isSearchingPlaces = false
      }
    }
  }

  private func clearPlaceSearch() {
    searchQuery = ""
    searchResults = []
    isSearchingPlaces = false
    searchTask?.cancel()
    isSearchFocused = false
    loadNearbyPlaces()
  }

  private func selectPlaceOption(_ place: NearbyPlaceOption) {
    isSearchFocused = false
    searchQuery = ""
    searchResults = []
    isSearchingPlaces = false
    searchTask?.cancel()

    name = place.name
    suggestedName = place.name
    selectedAddress = place.subtitle
    moveCamera(to: place.coordinate)
    refreshLocationDetails()
  }

  private func applySuggestion(_ suggestion: (name: String, coordinate: CLLocationCoordinate2D, visits: Int)) {
    name = suggestion.name
    suggestedName = suggestion.name
    moveCamera(to: suggestion.coordinate)
    refreshLocationDetails()
  }

  private func dismissNameKeyboard() {
    isNameFocused = false
    isSearchFocused = false
    isCoordinateFocused = false
    KeyboardDismiss.dismiss()
  }

  private func savePlace() {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let privacy = isPrivacyZone || kind == .home

    if let editingPlace {
      editingPlace.name = trimmedName
      editingPlace.latitude = latitude
      editingPlace.longitude = longitude
      editingPlace.kind = kind
      editingPlace.isPrivacyZone = privacy
    } else {
      let place = SavedPlace(
        name: trimmedName,
        latitude: latitude,
        longitude: longitude,
        kind: kind,
        isPrivacyZone: privacy
      )
      modelContext.insert(place)
    }

    try? modelContext.save()
    onSaved?(trimmedName)
    dismiss()
  }
}

#Preview {
  NavigationStack {
    PlacePickerView()
  }
  .environment(LocationService())
  .modelContainer(PreviewData.shared.container)
}
