import Foundation
import SwiftData

/// A separate set of bills, such as Personal, Business or a family member's. This is a local
/// grouping only; it has nothing to do with a login.
@Model
final class Profile {
    var id: UUID = UUID()
    var name: String = ""
    var kind: ProfileKind = ProfileKind.personal
    /// Hex colour used to tint this profile's bills, e.g. "C8472F".
    var colorHex: String = Profile.palette[0]
    var sortOrder: Int = 0
    /// Days of the month this profile gets paid. Empty means no cutoffs are shown.
    var paydays: [Int] = [15, 30]

    /// Deleting a profile deletes its bills.
    @Relationship(deleteRule: .cascade, inverse: \Bill.profile)
    var bills: [Bill]? = []

    init(name: String = "", kind: ProfileKind = .personal) {
        self.name = name
        self.kind = kind
    }

    static let palette = ["C4472F", "2E7D32", "1565C0", "6A1B9A", "EF6C00", "00838F"]
}

enum ProfileSeeder {
    /// Makes sure at least one profile exists and that every bill belongs to one.
    static func ensureDefault(in context: ModelContext) {
        let profiles = (try? context.fetch(FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let fallback: Profile
        if let first = profiles.first {
            fallback = first
        } else {
            fallback = Profile(name: "Personal", kind: .personal)
            context.insert(fallback)
        }

        let orphans = (try? context.fetch(FetchDescriptor<Bill>(predicate: #Predicate { $0.profile == nil }))) ?? []
        for bill in orphans {
            bill.profile = fallback
        }
    }
}
