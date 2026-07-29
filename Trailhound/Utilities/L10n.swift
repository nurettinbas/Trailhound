import Foundation

enum L10n {
    static func string(_ key: StaticString) -> String {
        SharedL10n.text(String(describing: key), bundle: .main)
    }

    static var tripStartedTitle: String { string("trip.started.title") }
    static var tripStartedBody: String { string("trip.started.body") }
    static var tripEndedTitle: String { string("trip.ended.title") }
    static var tripDiscardedTitle: String { string("trip.discarded.title") }
    static var tripDiscardedBody: String { string("trip.discarded.body") }
    static var recordingStarted: String { string("recording.started") }
    static var categoryPersonal: String { string("category.personal") }
    static var categoryBusiness: String { string("category.business") }
    static var speedKmh: String { string("unit.speed_kmh") }
    static var stop: String { string("action.stop") }
    static var delete: String { string("action.delete") }
    static var share: String { string("action.share") }

    static var notificationsTitle: String { string("notifications.title") }
    static var notificationsEmptyTitle: String { string("notifications.empty.title") }
    static var notificationsEmptyMessage: String { string("notifications.empty.message") }
    static var notificationsClearAll: String { string("notifications.clear_all") }

    static var pause: String { string("action.pause") }
    static var resume: String { string("action.resume") }
    static var recordingPaused: String { string("recording.paused") }
    static var settingsRecordingSection: String { string("settings.recording.section") }
    static var settingsAutoRecording: String { string("settings.recording.auto") }
    static var settingsRecordingSounds: String { string("settings.recording.sounds") }
    static var settingsRecordingSensitivitySection: String { string("settings.recording.sensitivity") }
    static var settingsIdleTimeout: String { string("settings.recording.idle_timeout") }
    static var settingsLowSpeedStop: String { string("settings.recording.low_speed_stop") }
    static var settingsRecordingStartSpeed: String { string("settings.recording.start_speed") }
    static var settingsRecordingStopSpeed: String { string("settings.recording.stop_speed") }
    static var settingsStopSpeed: String { string("settings.recording.trip_stop_speed") }
    static var settingsStopMinimumDistance: String { string("settings.recording.min_distance") }
    static var settingsStopMinimumDuration: String { string("settings.recording.min_duration") }
    static var settingsTripStopMinimumDuration: String { string("settings.recording.trip_stop_min_duration") }
    static var tripStopsSection: String { string("trip.stops.section") }
    static var tripEditTimesSection: String { string("trip.edit.times") }
    static var tripTrimPointsSection: String { string("trip.trim.points") }
    static var tripTrimHead: String { string("trip.trim.head") }
    static var tripTrimTail: String { string("trip.trim.tail") }
    static var tripStartedAt: String { string("trip.started_at") }
    static var tripEndedAt: String { string("trip.ended_at") }
    static var tripDetailTitle: String { string("trip.detail.title") }
    static var tripPointStart: String { string("trip.point.start") }
    static var tripPointEnd: String { string("trip.point.end") }
    static var tripPointStop: String { string("trip.point.stop") }
    static var tripMapOfflineHint: String { string("trip.map.offline_hint") }
    static var orphanStaleNotificationTitle: String { string("orphan.stale.title") }
    static var orphanStaleNotificationBody: String { string("orphan.stale.body") }
    static var all: String { string("filter.all") }
    static var duration: String { string("label.duration") }
    static var currentSpeed: String { string("label.current_speed") }
    static var maxAbbr: String { string("label.max_abbr") }
    static var avgAbbr: String { string("label.avg_abbr") }
    static var labelDistance: String { string("label.distance") }
    static var placeHome: String { string("place.home") }
    static var placeWork: String { string("place.work") }
    static var placeOther: String { string("place.other") }

    static func placeNearName(_ name: String) -> String {
        String(format: string("place.near_name"), name)
    }

    static var tripsEmptyTitle: String { string("trips.empty.title") }
    static var tripsEmptyMessage: String { string("trips.empty.message") }
    static var tripsEmptyFilteredTitle: String { string("trips.empty.filtered.title") }
    static var tripsEmptyFilteredMessage: String { string("trips.empty.filtered.message") }
    static var tripsSearchEmpty: String { string("trips.search.empty") }
    static var tripsMergeTitle: String { string("trips.merge.title") }
    static func tripsMergeMessage(_ count: Int) -> String {
        String(format: string("trips.merge.message"), count)
    }
    static var a11ySelected: String { string("a11y.selected") }
    static var a11yNotSelected: String { string("a11y.not_selected") }
    static var tripEditCategoryAndLabel: String { string("trip.edit.category_and_label") }
    static var tripEditCategory: String { string("trip.edit.category") }
    static var tripEditLabel: String { string("trip.edit.label") }
    static var tripEditNote: String { string("trip.edit.note") }
    static var tripEditNotePlaceholder: String { string("trip.edit.note_placeholder") }
    static var tripEditSave: String { string("trip.edit.save") }
    static var labelNone: String { string("label.none") }
    static var actionClose: String { string("action.close") }
    static var actionAdd: String { string("action.add") }
    static var mapStylePicker: String { string("map.style.picker") }
    static func settingsAutoDeleteDays(_ days: Int) -> String {
        String(format: string("settings.privacy.auto_delete.days"), days)
    }
    static var settingsPrivacyRadiusUnit: String { string("settings.privacy.radius_unit") }
    static var categorySection: String { string("category.section") }
    static var categoryBuiltinBadge: String { string("category.builtin_badge") }
    static var categoryNewPlaceholder: String { string("category.new_placeholder") }
    static var fuelUnitKWhPer100km: String { string("fuel.unit.kwh_per_100km") }
    static var fuelUnitLPer100km: String { string("fuel.unit.l_per_100km") }
    static var labelWork: String { string("label.work") }
    static var labelMarket: String { string("label.market") }
    static var labelHoliday: String { string("label.holiday") }
    static var labelOther: String { string("label.other") }
    static var sectionToday: String { string("section.today") }
    static var sectionYesterday: String { string("section.yesterday") }
    static var sectionThisWeek: String { string("section.this_week") }
    static var sectionThisMonth: String { string("section.this_month") }
    static var sectionOlder: String { string("section.older") }
    static var searchTrips: String { string("search.trips") }
    static var tripsFilters: String { string("trips.filters") }
    static var actionMerge: String { string("action.merge") }
    static var actionCategory: String { string("action.category") }
    static var mapFullscreen: String { string("map.fullscreen") }
    static var mapStyleLight: String { string("map.style.light") }
    static var mapStyleDark: String { string("map.style.dark") }
    static var speedLegendSlow: String { string("speed.legend.slow") }
    static var tripSpeedChart: String { string("trip.speed_chart") }
    static var speedLegendMedium: String { string("speed.legend.medium") }
    static var speedLegendFast: String { string("speed.legend.fast") }
    static var tripSummary: String { string("trip.summary") }
    static var estimatedFuel: String { string("label.estimated_fuel") }
    static var maxSpeed: String { string("label.max_speed") }
    static var averageSpeed: String { string("label.average_speed") }
    static var fuelPetrol: String { string("fuel.petrol") }
    static var fuelDiesel: String { string("fuel.diesel") }
    static var fuelElectric: String { string("fuel.electric") }
    static var fuelHybrid: String { string("fuel.hybrid") }
    static var tripLocationOverrides: String { string("trip.location.overrides") }
    static var tripStartPlaceName: String { string("trip.start_place_name") }
    static var tripEndPlaceName: String { string("trip.end_place_name") }
    static var tripStartAddress: String { string("trip.start_address") }
    static var tripEndAddress: String { string("trip.end_address") }
    static var placeSuggestionSection: String { string("place.suggestion.section") }
    static var placePickerSelectedLocation: String { string("place.picker.selected_location") }
    static var placePickerMoveMapHint: String { string("place.picker.move_map_hint") }
    static var placePickerUseCurrentLocation: String { string("place.picker.use_current_location") }
    static var placePickerResolvingAddress: String { string("place.picker.resolving_address") }
    static var placePickerNearbySection: String { string("place.picker.nearby_section") }
    static var placePickerSearchPlaceholder: String { string("place.picker.search.placeholder") }
    static var placePickerSearchSection: String { string("place.picker.search.section") }
    static var placePickerSearchEmpty: String { string("place.picker.search.empty") }
    static var placePickerSearchHint: String { string("place.picker.search.hint") }
    static var placePickerSearchLoading: String { string("place.picker.search.loading") }
    static var placePickerSearchClear: String { string("place.picker.search.clear") }
    static var placePickerUseAddressAsName: String { string("place.picker.use_address_as_name") }
    static var placePickerEditTitle: String { string("place.picker.edit_title") }
    static var placePickerNewTitle: String { string("place.picker.new_title") }
    static var placePickerSave: String { string("place.picker.save") }
    static var placePrivacyZoneHint: String { string("place.privacy_zone.hint") }
    static var settingsFavoritePlaces: String { string("settings.favorite_places") }
    static var settingsFavoritePlacesHint: String { string("settings.favorite_places.hint") }
    static var settingsFavoritePlacesEmpty: String { string("settings.favorite_places.empty") }
    static var settingsAddPlace: String { string("settings.add_place") }

    static var actionRefresh: String { string("action.refresh") }
    static var settingsTitle: String { string("settings.title") }
    static var settingsVehiclePairingSection: String { string("settings.vehicle_pairing.section") }
    static var settingsPairedVehicle: String { string("settings.vehicle_pairing.paired") }
    static var settingsConnectionType: String { string("settings.vehicle_pairing.type") }
    static var settingsConnectionStatus: String { string("settings.vehicle_pairing.connection") }
    static var settingsConnected: String { string("settings.connection.connected") }
    static var settingsDisconnected: String { string("settings.connection.disconnected") }
    static var settingsChangeVehicle: String { string("settings.vehicle_pairing.change") }
    static var settingsRemovePairing: String { string("settings.vehicle_pairing.remove") }
    static var settingsPairVehicleHint: String { string("settings.vehicle_pairing.hint") }
    static var settingsDefineVehicle: String { string("settings.vehicle_pairing.define") }
    static var settingsLanguageSection: String { string("settings.language.section") }
    static var settingsLanguageSystemHint: String { string("settings.language.system_hint") }
    static var settingsFuelSection: String { string("settings.fuel.section") }
    static var settingsFuelConsumption: String { string("settings.fuel.consumption") }
    static var settingsFuelPrice: String { string("settings.fuel.price") }
    static var settingsFuelHint: String { string("settings.fuel.hint") }
    static var settingsPrivacySection: String { string("settings.privacy.section") }
    static var settingsAppLock: String { string("settings.privacy.app_lock") }
    static var settingsPrivacyRadius: String { string("settings.privacy.radius") }
    static var settingsBlurExport: String { string("settings.privacy.blur_export") }
    static var settingsAutoDelete: String { string("settings.privacy.auto_delete") }
    static var settingsAutoDeleteNever: String { string("settings.privacy.auto_delete.never") }
    static var settingsPermissionsSection: String { string("settings.permissions.section") }
    static var settingsLocationPermission: String { string("settings.permissions.location") }
    static var settingsPermissionGranted: String { string("settings.permissions.granted") }
    static var settingsPermissionRequired: String { string("settings.permissions.required") }
    static var settingsRequestLocationPermission: String { string("settings.permissions.request_location") }
    static var settingsOpenSystemSettings: String { string("settings.permissions.open_settings") }
    static var settingsBackgroundLocationHint: String { string("settings.permissions.background_location_hint") }
    static var settingsBackupSection: String { string("settings.backup.section") }
    static var settingsExportJSON: String { string("settings.backup.json") }
    static var settingsExportCSV: String { string("settings.backup.csv") }
    static var settingsExportGPX: String { string("settings.backup.gpx") }
    static var settingsExportKML: String { string("settings.backup.kml") }
    static var settingsExportPreparing: String { string("settings.backup.exporting") }
    static var settingsShareFile: String { string("settings.backup.share") }
    static var settingsAboutSection: String { string("settings.about.section") }
    static var settingsVersion: String { string("settings.about.version") }
    static var settingsDeveloperMode: String { string("settings.developer_mode") }
    static var settingsAboutPrivacy: String { string("settings.about.privacy") }
    static var settingsLocationNotDetermined: String { string("settings.location.not_determined") }
    static var settingsLocationWhenInUse: String { string("settings.location.when_in_use") }
    static var settingsLocationAlways: String { string("settings.location.always") }
    static var settingsLocationDenied: String { string("settings.location.denied") }
    static var settingsLocationRestricted: String { string("settings.location.restricted") }
    static var vehiclePairingTitle: String { string("vehicle.pairing.title") }
    static var vehiclePairingMessage: String { string("vehicle.pairing.message") }
    static var vehiclePairingConnectionType: String { string("vehicle.pairing.connection_type") }
    static var vehiclePairingBluetooth: String { string("vehicle.pairing.bluetooth") }
    static var vehiclePairingSkip: String { string("vehicle.pairing.skip") }
    static var vehiclePairingSavedVehicles: String { string("vehicle.pairing.saved_vehicles") }
    static var vehiclePairingConnectedDevice: String { string("vehicle.pairing.connected_device") }
    static var vehiclePairingConfirm: String { string("vehicle.pairing.confirm") }
    static var vehiclePairingBluetoothSetupHint: String { string("vehicle.pairing.bluetooth_setup_hint") }
    static var vehiclePairingWaitingBluetooth: String { string("vehicle.pairing.waiting_bluetooth") }
    static var vehiclePairingNoConnection: String { string("vehicle.pairing.no_connection") }
    static var vehiclePairingMissingConnection: String { string("vehicle.pairing.missing_connection") }
    static var vehicleDefaultName: String { string("vehicle.default_name") }
    static var vehicleAutoTrigger: String { string("vehicle.auto_trigger") }
    static var tripListSetupVehicleTitle: String { string("trip.list.setup_vehicle.title") }
    static var tripListSetupVehicleMessage: String { string("trip.list.setup_vehicle.message") }
    static var appLockReason: String { string("settings.privacy.app_lock_reason") }
    static var settingsConfirmExternalStart: String { string("settings.privacy.confirm_external_start") }
    static var appLockTitle: String { string("settings.privacy.app_lock_title") }
    static var appLockUnlock: String { string("settings.privacy.app_lock_unlock") }
    static var appLockUnavailableTitle: String { string("settings.privacy.app_lock_unavailable_title") }
    static var appLockUnavailable: String { string("settings.privacy.app_lock_unavailable") }
    static var externalStartConfirmTitle: String { string("recording.external_start.title") }
    static var externalStartConfirmMessage: String { string("recording.external_start.message") }
    static var externalStartConfirmAction: String { string("recording.external_start.confirm") }
    static var cancel: String { string("action.cancel") }
    static var ok: String { string("action.ok") }
    static var settingsSiriShortcutsHint: String { string("settings.siri.shortcuts_hint") }
    static var settingsSiriShortcutsLink: String { string("settings.siri.shortcuts_link") }
    static var tabTrips: String { string("tab.trips") }
    static var tabStats: String { string("tab.stats") }
    static var tabPairing: String { string("tab.pairing") }
    static var tabSettings: String { string("tab.settings") }

    static var pairingTabTitle: String { string("pairing.tab.title") }
    static var pairingTabHeroTitle: String { string("pairing.tab.hero.title") }
    static var pairingTabStatusConnected: String { string("pairing.tab.status.connected") }
    static var pairingTabStatusDisconnected: String { string("pairing.tab.status.disconnected") }
    static var pairingTabRefreshing: String { string("pairing.tab.refreshing") }
    static var pairingTabRefreshUpdated: String { string("pairing.tab.refresh.updated") }
    static var pairingTabRemovePairing: String { string("pairing.tab.remove_pairing") }
    static var pairingTabDeleteVehicleTitle: String { string("pairing.tab.delete_vehicle.title") }
    static var pairingTabDeleteVehicleMessage: String { string("pairing.tab.delete_vehicle.message") }
    static var pairingTabDeleteVehicleMessageActive: String { string("pairing.tab.delete_vehicle.message_active") }
    static var pairingTabAddVehicle: String { string("pairing.tab.add_vehicle") }
    static var pairingTabAddFirstVehicle: String { string("pairing.tab.add_first_vehicle") }
    static var pairingTabSavedVehicles: String { string("pairing.tab.saved_vehicles") }
    static var pairingTabActivePairing: String { string("pairing.tab.active_pairing") }
    static var pairingTabActiveBadge: String { string("pairing.tab.active_badge") }
    static var pairingTabSetupTitle: String { string("pairing.tab.setup.title") }
    static var pairingTabSetupSubtitle: String { string("pairing.tab.setup.subtitle") }
    static var pairingTabSelectVehicle: String { string("pairing.tab.select_vehicle") }
    static var pairingTabBluetoothSetupTitle: String { string("pairing.tab.bluetooth_setup.title") }
    static var pairingShortcutsGuideTitle: String { string("pairing.shortcuts.guide.title") }
    static var pairingShortcutsGuideIntro: String { string("pairing.shortcuts.guide.intro") }
    static var pairingShortcutsGuideCardTitle: String { string("pairing.shortcuts.guide.card.title") }
    static var pairingShortcutsGuideCardSubtitle: String { string("pairing.shortcuts.guide.card.subtitle") }
    static var pairingShortcutsGuideCardButton: String { string("pairing.shortcuts.guide.card.button") }
    static var pairingShortcutsGuidePrerequisiteTitle: String { string("pairing.shortcuts.guide.prerequisite.title") }
    static var pairingShortcutsGuidePrerequisiteBody: String { string("pairing.shortcuts.guide.prerequisite.body") }
    static var pairingShortcutsGuideSilentStart: String { string("pairing.shortcuts.guide.silent_start") }
    static var pairingShortcutsGuideTriggersTitle: String { string("pairing.shortcuts.guide.triggers.title") }
    static var pairingShortcutsGuideTriggersIntro: String { string("pairing.shortcuts.guide.triggers.intro") }
    static var pairingShortcutsGuideTriggersBluetoothTitle: String { string("pairing.shortcuts.guide.triggers.bluetooth.title") }
    static var pairingShortcutsGuideTriggersBluetoothBody: String { string("pairing.shortcuts.guide.triggers.bluetooth.body") }
    static var pairingShortcutsGuideTriggersCarPlayTitle: String { string("pairing.shortcuts.guide.triggers.carplay.title") }
    static var pairingShortcutsGuideTriggersCarPlayBody: String { string("pairing.shortcuts.guide.triggers.carplay.body") }
    static var pairingShortcutsGuideTriggersWiFiTitle: String { string("pairing.shortcuts.guide.triggers.wifi.title") }
    static var pairingShortcutsGuideTriggersWiFiBody: String { string("pairing.shortcuts.guide.triggers.wifi.body") }
    static var pairingShortcutsGuideConnectTitle: String { string("pairing.shortcuts.guide.connect.title") }
    static var pairingShortcutsGuideConnectStep1: String { string("pairing.shortcuts.guide.connect.step1") }
    static var pairingShortcutsGuideConnectStep2: String { string("pairing.shortcuts.guide.connect.step2") }
    static var pairingShortcutsGuideConnectStep3: String { string("pairing.shortcuts.guide.connect.step3") }
    static var pairingShortcutsGuideConnectStep4: String { string("pairing.shortcuts.guide.connect.step4") }
    static var pairingShortcutsGuideConnectStep5: String { string("pairing.shortcuts.guide.connect.step5") }
    static var pairingShortcutsGuideDisconnectTitle: String { string("pairing.shortcuts.guide.disconnect.title") }
    static var pairingShortcutsGuideDisconnectStep1: String { string("pairing.shortcuts.guide.disconnect.step1") }
    static var pairingShortcutsGuideDisconnectStep2: String { string("pairing.shortcuts.guide.disconnect.step2") }
    static var pairingShortcutsGuideDisconnectStep3: String { string("pairing.shortcuts.guide.disconnect.step3") }
    static var pairingShortcutsGuideDisconnectStep4: String { string("pairing.shortcuts.guide.disconnect.step4") }
    static var pairingShortcutsGuideNote: String { string("pairing.shortcuts.guide.note") }
    static var pairingShortcutsGuideOpenShortcuts: String { string("pairing.shortcuts.guide.open_shortcuts") }
    static var pairingShortcutsGuideDone: String { string("pairing.shortcuts.guide.done") }
    static var settingsShortcutsAutomationGuide: String { string("settings.shortcuts.automation_guide") }
    static var shortcutStartTitle: String { string("shortcut.start.title") }
    static var shortcutStopTitle: String { string("shortcut.stop.title") }
    static var pairingTabRecordingStatus: String { string("pairing.tab.recording_status") }
    static var pairingReadinessTitle: String { string("pairing.tab.readiness.title") }
    static var pairingReadinessLocationAlways: String { string("pairing.tab.readiness.location_always") }
    static var pairingReadinessVehiclePaired: String { string("pairing.tab.readiness.vehicle_paired") }
    static var pairingReadinessConnectionDetected: String { string("pairing.tab.readiness.connection_detected") }
    static var pairingTabDefineVehicle: String { string("pairing.tab.define_vehicle") }
    static var pairingTabConnectionNow: String { string("pairing.tab.connection_now") }
    static var pairingTabConnectionDetected: String { string("pairing.tab.connection_detected") }
    static var pairingTabConnectionNotDetected: String { string("pairing.tab.connection_not_detected") }
    static var pairingTabPairNow: String { string("pairing.tab.pair_now") }
    static var pairingTabPairedSuccess: String { string("pairing.tab.paired_success") }
    static var pairingTabWaitingConnection: String { string("pairing.tab.wait_connection") }
    static var pairingSuggestionTitle: String { string("pairing.suggestion.title") }
    static var pairingSuggestionBody: String { string("pairing.suggestion.body") }
    static var pairingTabConfirmVehicleHint: String { string("pairing.tab.confirm_vehicle_hint") }
    static var pairingTabAdvanced: String { string("pairing.tab.advanced") }
    static var pairingTabPickChannelHint: String { string("pairing.tab.pick_channel_hint") }
    static func pairingTabDebugDevice(_ device: String) -> String {
        String(format: string("pairing.tab.debug.device"), device)
    }
    static func pairingTabDebugUID(_ uid: String) -> String {
        String(format: string("pairing.tab.debug.uid"), uid)
    }
    static func pairingTabDebugMatchMethod(_ method: String) -> String {
        String(format: string("pairing.tab.debug.match_method"), method)
    }
    static var pairingTabDebugMatchUID: String { string("pairing.tab.debug.match.uid") }
    static var pairingTabDebugMatchName: String { string("pairing.tab.debug.match.name") }
    static var pairingTabDebugMatchLegacy: String { string("pairing.tab.debug.match.legacy") }
    static var pairingTabDebugMatchLastKnown: String { string("pairing.tab.debug.match.last_known") }
    static var pairingTabFirstSetupHint: String { string("pairing.tab.first_setup_hint") }
    static var pairingTabEmptyTitle: String { string("pairing.tab.empty.title") }
    static var pairingTabEmptyMessage: String { string("pairing.tab.empty.message") }
    static var pairingTabVehicleSection: String { string("pairing.tab.vehicle.section") }
    static var pairingTabVehicleName: String { string("pairing.tab.vehicle.name") }
    static var pairingTabVehicleIcon: String { string("pairing.tab.vehicle.icon") }
    static var pairingTabVehicleNotFound: String { string("pairing.tab.vehicle.not_found") }
    static var pairingTabFuelType: String { string("pairing.tab.vehicle.fuel_type") }
    static var pairingTabChargePrice: String { string("pairing.tab.vehicle.charge_price") }
    static var pairingTabDefaultVehicle: String { string("pairing.tab.vehicle.default") }
    static var pairingTabSave: String { string("pairing.tab.save") }
    static var pairingTabNewVehicleName: String { string("pairing.tab.new_vehicle_name") }
    static var pairingTabMissingConnection: String { string("pairing.tab.missing_connection") }
    static var pairingTabWaitingBluetooth: String { string("pairing.tab.waiting_bluetooth") }
    static var pairingLiveConnectionTitle: String { string("pairing.live_connection.title") }
    static var pairingLiveConnectionNone: String { string("pairing.live_connection.none") }
    static func pairingConnectionBluetooth(_ name: String, _ portType: String) -> String {
        String(format: string("pairing.connection.bluetooth"), name, portType)
    }

    static var orphanBannerTitle: String { string("orphan.banner.title") }
    static var orphanBannerMessage: String { string("orphan.banner.message") }
    static var orphanResume: String { string("orphan.banner.resume") }
    static var orphanSave: String { string("orphan.banner.save") }
    static var orphanAlreadyEnded: String { string("orphan.error.already_ended") }
    static var orphanResumeBusy: String { string("orphan.error.resume_busy") }
    static var orphanResumeFailed: String { string("orphan.error.resume_failed") }

    static func orphanSaveFailed(_ detail: String) -> String {
        String(format: string("orphan.error.save_failed"), detail)
    }

    static func orphanDeleteFailed(_ detail: String) -> String {
        String(format: string("orphan.error.delete_failed"), detail)
    }

    static func storeOpenFailed(_ detail: String) -> String {
        String(format: string("store.open_failed"), detail)
    }

    static var storeRecoveredAfterReset: String { string("store.recovered_after_reset") }
    static var settingsRestoreAutoBackup: String { string("settings.backup.restore_auto") }
    static var settingsRestoreBestBackup: String { string("settings.backup.restore_best") }
    static func settingsBackupRestoreRow(size: String, date: String) -> String {
        String(format: string("settings.backup.restore_row"), size, date)
    }
    static var settingsBackupRestoreHint: String { string("settings.backup.restore_hint") }
    static var settingsRestoreConfirmTitle: String { string("settings.backup.restore_confirm_title") }
    static func settingsRestoreConfirmMessage(_ backupFileName: String) -> String {
        String(format: string("settings.backup.restore_confirm_message"), backupFileName)
    }
    static var settingsRestoreRestartTitle: String { string("settings.backup.restore_restart_title") }
    static var settingsRestoreRestartMessage: String { string("settings.backup.restore_restart_message") }
    static var settingsRestoreRestartAction: String { string("settings.backup.restore_restart_action") }
    static var storeRestoreNoBackup: String { string("store.restore_no_backup") }
    static var storeOpenFailedInMemory: String { string("store.open_failed_in_memory") }
    static var errorTitle: String { string("alert.error.title") }
    static var infoTitle: String { string("alert.info.title") }

    static func pairingTabSaveFailed(_ detail: String) -> String {
        String(format: string("pairing.tab.save_failed"), detail)
    }

    static func pairingTabDeleteFailed(_ detail: String) -> String {
        String(format: string("pairing.tab.delete_failed"), detail)
    }

    static func placeSuggestionVisits(_ count: Int) -> String {
        let format = string("place.suggestion.visits")
        return String(format: format, count)
    }

    static func weekSummary(distance: String, duration: String) -> String {
        let format = string("week.summary")
        return String(format: format, distance, duration)
    }

    static func formatSpeedKmh(_ kmh: Double) -> String {
        String(format: "%.0f %@", kmh, speedKmh)
    }

    static func maxSpeedDetail(_ speed: String) -> String {
        let format = string("trip.max_speed_detail")
        return String(format: format, speed)
    }

    static var locationBadgeAlways: String { string("location.badge.always") }
    static var locationBadgeWhenInUse: String { string("location.badge.when_in_use") }
    static var locationBadgeDenied: String { string("location.badge.denied") }
    static var pairingLocationWarning: String { string("pairing.location.warning") }
    static var locationBannerGrant: String { string("location.banner.grant") }
    static var locationBannerSettings: String { string("location.banner.settings") }

    static var autoLogSectionTitle: String { string("auto_log.section.title") }
    static var autoLogSectionHint: String { string("auto_log.section.hint") }
    static var autoLogEmpty: String { string("auto_log.empty") }
    static var autoLogClear: String { string("auto_log.clear") }

    static func autoLogBluetoothConnectedStarted(_ time: String, _ vehicle: String?, _ delay: Int) -> String {
        String(format: string("auto_log.bt.connected.started"), time, vehicle ?? "—", delay)
    }

    static func autoLogBluetoothConnectedAwaitingGPS(_ time: String, _ vehicle: String?, _ delay: Int) -> String {
        String(format: string("auto_log.bt.connected.awaiting_gps"), time, vehicle ?? "—", delay)
    }

    static func autoLogBluetoothConnectedCancelled(_ time: String, _ vehicle: String?) -> String {
        String(format: string("auto_log.bt.connected.cancelled"), time, vehicle ?? "—")
    }

    static func autoLogBluetoothConnectedSkipped(_ time: String, _ vehicle: String?) -> String {
        String(format: string("auto_log.bt.connected.skipped"), time, vehicle ?? "—")
    }

    static func autoLogBluetoothDisconnectedStopped(_ time: String, _ delay: Int, _ distance: String) -> String {
        String(format: string("auto_log.bt.disconnected.stopped"), time, delay, distance)
    }

    static func autoLogBluetoothDisconnectedSkipped(_ time: String) -> String {
        String(format: string("auto_log.bt.disconnected.skipped"), time)
    }

    static func autoLogMotionStarted(_ time: String) -> String {
        String(format: string("auto_log.motion.started"), time)
    }

    static func autoLogMotionStopped(_ time: String, _ distance: String) -> String {
        String(format: string("auto_log.motion.stopped"), time, distance)
    }
}
