import Foundation
import SwiftData

/// An activity recorded with the phone (GPS + band heart rate).
@Model
public final class StoredActivity {
    @Attribute(.unique) public var id: UUID
    public var start: Date
    public var end: Date
    /// The finished `ActivityRecorder`, as JSON.
    public var data: Data
    public var exported: Bool

    init(id: UUID, recorder: ActivityRecorder, data: Data) {
        self.id = id
        start = recorder.start
        end = recorder.end ?? recorder.start
        self.data = data
        exported = false
    }

    public var recorder: ActivityRecorder? { try? JSONDecoder().decode(ActivityRecorder.self, from: data) }
}
