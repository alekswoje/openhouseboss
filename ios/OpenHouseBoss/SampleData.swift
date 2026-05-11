import Foundation

// Hard-coded sample data mirroring web/shared.jsx SAMPLE_VISITORS — used to
// power the mockup screens that haven't been wired up to live backend data yet.
struct SampleVisitor: Identifiable, Hashable {
    let id: Int
    let name: String
    let email: String
    let phone: String
    let signedAt: String
    let speaker: String
    let tag: String          // "buyer" | "seller" | "browser"
    let score: Int
    let summary: String
    let signals: [String]
    let spokeWords: Int
    let followUp: String
}

struct SampleTranscriptLine: Identifiable {
    let id = UUID()
    let who: String          // "agent" | "visitor" | "gap"
    let visitorId: Int?
    let name: String
    let timestamp: String
    let text: String
    let highlight: Bool
}

enum SampleData {
    static let visitors: [SampleVisitor] = [
        .init(
            id: 1,
            name: "Sarah Chen",
            email: "sarah@example.com",
            phone: "555-0101",
            signedAt: "2:05 PM",
            speaker: "B",
            tag: "buyer",
            score: 94,
            summary: "Actively house-hunting on the West Side with her husband Tom. Sold their Queens home last year, currently renting. Drawn by the kitchen photos. Needs 3+ bedrooms for two kids. Pre-approved to $1.4M, ready to close in 60 days.",
            signals: ["Pre-approved $1.4M", "Close in 60 days", "3+ bedrooms", "6 months searching"],
            spokeWords: 142,
            followUp: """
            Hi Sarah, it was so great meeting you today at the open house! I love how prepared you and Tom are — pre-approved and ready to move in 60 days is exactly the kind of position that gives buyers a real edge in this market. The home at $1.295M has been generating serious interest, so please don't hesitate to reach out if you'd like to schedule a private showing. I'd also be happy to send you comparable West Side listings that check your boxes — three bedrooms, great kitchen, the location you love.

            Looking forward to helping you and Tom find the perfect fit.

            Warm regards,
            John
            """
        ),
        .init(
            id: 2,
            name: "Mike Rodriguez",
            email: "mike@example.com",
            phone: "555-0102",
            signedAt: "2:22 PM",
            speaker: "C",
            tag: "seller",
            score: 88,
            summary: "Lives two blocks away on Riverside, in his home for 15 years. Kids heading to college; considering downsizing within six months. Came primarily to gauge the market. Explicitly requested a complimentary comp analysis on his property.",
            signals: ["Owner 15 yrs", "Downsizing 6mo", "Requested comp analysis", "Riverside, 2 blocks"],
            spokeWords: 98,
            followUp: """
            Hi Mike, it was great meeting you at the open house today — glad you stopped in. As promised, I'd love to put together a complimentary comparative market analysis for your place on Riverside so you have a clear picture of what your home could list for in today's market. Given the activity we're already seeing at this listing, I think you'd be pleasantly surprised by where values are right now in the neighborhood.

            When's a good time this week for a quick call or walkthrough?

            Warm regards,
            John
            """
        ),
        .init(
            id: 3,
            name: "Jennifer Park",
            email: "jen@example.com",
            phone: "555-0103",
            signedAt: "2:35 PM",
            speaker: "D",
            tag: "browser",
            score: 42,
            summary: "Local renter with a lease running until next year. Walked in out of curiosity after passing the building regularly. Loves the neighborhood but undecided between buying and continuing to rent. Open to low-pressure listing updates.",
            signals: ["Lease until 2027", "Neighborhood loyal", "No urgency", "Curious browser"],
            spokeWords: 64,
            followUp: """
            Hi Jennifer, it was so great meeting you at the open house today! I totally understand you're in the early stages of figuring out what makes sense for you, and there's absolutely no rush. As promised, I'll keep you on a low-key list so you can get a feel for what's available in the neighborhood whenever something similar comes up.

            If you ever want to chat through the rent-vs-buy decision, I'm always happy to help — no strings attached.

            Warm regards,
            John
            """
        ),
    ]

    static func visitorTranscript(forId vid: Int) -> [SampleTranscriptLine] {
        switch vid {
        case 1:
            return [
                .init(who: "agent",   visitorId: nil, name: "John", timestamp: "0:00", text: "Welcome in, glad you stopped by! I'm John, hosting today for the seller. What's your name?", highlight: false),
                .init(who: "visitor", visitorId: 1,   name: "Sarah Chen", timestamp: "0:06", text: "Hi, I'm Sarah. My husband Tom couldn't make it today, but I wanted to come check it out.", highlight: false),
                .init(who: "visitor", visitorId: 1,   name: "Sarah Chen", timestamp: "0:15", text: "About six months actually. We've been all over the West Side. We sold our place in Queens last year and we've been renting until we find the right thing.", highlight: true),
                .init(who: "visitor", visitorId: 1,   name: "Sarah Chen", timestamp: "0:27", text: "The kitchen looks amazing in the photos. And we need at least three bedrooms, we have two kids.", highlight: true),
                .init(who: "visitor", visitorId: 1,   name: "Sarah Chen", timestamp: "0:39", text: "Honestly we're ready now. Pre-approved up to one point four. We'd close in 60 days if it's the right house.", highlight: true),
            ]
        case 2:
            return [
                .init(who: "visitor", visitorId: 2, name: "Mike Rodriguez", timestamp: "2:07", text: "Two blocks over on Riverside. We've been in our place fifteen years. Kids are off to college. Thinking about downsizing maybe in the next six months.", highlight: true),
                .init(who: "visitor", visitorId: 2, name: "Mike Rodriguez", timestamp: "2:40", text: "Yeah that would actually be helpful. Can you email me?", highlight: true),
            ]
        default:
            return []
        }
    }
}
