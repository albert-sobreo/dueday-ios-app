import Foundation
import SwiftData
import Testing
@testable import DueDay

@MainActor private var matcherContainers: [ModelContainer] = []

@MainActor
struct AccountMatcherTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Profile.self, CustomProvider.self, CustomPaymentMethod.self,
            Bill.self, BillInstance.self, Payment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        matcherContainers.append(container)
        return container.mainContext
    }

    private func account(
        _ name: String, preset: String? = nil, number: String? = nil,
        profile: Profile, archived: Bool = false, in context: ModelContext
    ) -> Bill {
        let bill = Bill(name: name)
        bill.presetID = preset
        bill.accountNumber = number
        bill.profile = profile
        bill.isArchived = archived
        context.insert(bill)
        return bill
    }

    @Test func theSameAccountNumberMatchesEvenWithDifferentFormatting() throws {
        let context = try makeContext()
        let profile = Profile(name: "Personal"); context.insert(profile)
        let meralco = account("Meralco", preset: "meralco", number: "2011-4589-321", profile: profile, in: context)

        let found = AccountMatcher.find(
            in: [meralco], presetID: nil, name: "", accountNumber: "20114589321", profileID: profile.id
        )
        #expect(found === meralco)
    }

    @Test func theSameBillerMatchesWhenAnumberIsMissing() throws {
        let context = try makeContext()
        let profile = Profile(name: "Personal"); context.insert(profile)
        let meralco = account("Meralco", preset: "meralco", number: "20114589", profile: profile, in: context)

        let found = AccountMatcher.find(
            in: [meralco], presetID: "meralco", name: "Meralco", accountNumber: nil, profileID: profile.id
        )
        #expect(found === meralco)
    }

    @Test func aDifferentAccountNumberForTheSameBillerIsAnotherAccount() throws {
        let context = try makeContext()
        let profile = Profile(name: "Personal"); context.insert(profile)
        let home = account("Meralco", preset: "meralco", number: "11112222", profile: profile, in: context)

        let found = AccountMatcher.find(
            in: [home], presetID: "meralco", name: "Meralco", accountNumber: "99998888", profileID: profile.id
        )
        #expect(found == nil)
    }

    @Test func archivedAccountsAndOtherProfilesAreIgnored() throws {
        let context = try makeContext()
        let personal = Profile(name: "Personal"); context.insert(personal)
        let business = Profile(name: "Business"); context.insert(business)
        let archived = account("Meralco", preset: "meralco", number: "11112222", profile: personal, archived: true, in: context)
        let other = account("Meralco", preset: "meralco", number: "33334444", profile: business, in: context)

        #expect(AccountMatcher.find(
            in: [archived, other], presetID: "meralco", name: "Meralco", accountNumber: "11112222", profileID: personal.id
        ) == nil)
        #expect(AccountMatcher.find(
            in: [archived, other], presetID: "meralco", name: "Meralco", accountNumber: "33334444", profileID: personal.id
        ) == nil)
    }

    @Test func aCustomBillerMatchesByNameIgnoringCase() throws {
        let context = try makeContext()
        let profile = Profile(name: "Personal"); context.insert(profile)
        let water = account("Subic Water", number: nil, profile: profile, in: context)

        let found = AccountMatcher.find(
            in: [water], presetID: nil, name: "  subic water ", accountNumber: nil, profileID: profile.id
        )
        #expect(found === water)
    }

    @Test func aShortNumberIsNotTrustedOnItsOwn() throws {
        let context = try makeContext()
        let profile = Profile(name: "Personal"); context.insert(profile)
        let gym = account("Gym", number: "12", profile: profile, in: context)

        let found = AccountMatcher.find(
            in: [gym], presetID: nil, name: "Something else", accountNumber: "12", profileID: profile.id
        )
        #expect(found == nil)
    }
}
