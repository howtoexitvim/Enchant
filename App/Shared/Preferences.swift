import Foundation
struct AppPreferences: Codable, Equatable {
    var sound = true
    var haptics = true
    var autoSave = true
    var autoStop = false
    var healthEnabled = false
    var writeWorkout = false
    var mondayFirst = true
    var sensitivity = 0.12
    var idleSeconds = 60.0
    var automaticStart = false
}

struct PreferencesEnvelope: Codable { var revision: Int; var writerID: String; var values: AppPreferences }

extension AppPreferences {
    private enum CodingKeys: String, CodingKey { case sound, haptics, autoSave, autoStop, healthEnabled, writeWorkout, mondayFirst, sensitivity, idleSeconds, automaticStart }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? sound
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? haptics
        autoSave = try c.decodeIfPresent(Bool.self, forKey: .autoSave) ?? autoSave
        autoStop = try c.decodeIfPresent(Bool.self, forKey: .autoStop) ?? autoStop
        healthEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthEnabled) ?? healthEnabled
        writeWorkout = try c.decodeIfPresent(Bool.self, forKey: .writeWorkout) ?? writeWorkout
        mondayFirst = try c.decodeIfPresent(Bool.self, forKey: .mondayFirst) ?? mondayFirst
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? sensitivity
        idleSeconds = try c.decodeIfPresent(Double.self, forKey: .idleSeconds) ?? idleSeconds
        automaticStart = try c.decodeIfPresent(Bool.self, forKey: .automaticStart) ?? automaticStart
    }
}
