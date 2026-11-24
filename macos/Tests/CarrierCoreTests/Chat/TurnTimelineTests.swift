import Testing

@testable import CarrierCore

@Test func eachMessageOfThePersonStartsATurnWithTheStartOfTheFirstAnswer() {
    let feed: [FeedRow] = [
        .user(id: "u1", text: "first\nquestion"), .agent(id: "a1", text: "Yes,\nit is so", inProgress: false), .agent(id: "a2", text: "more", inProgress: false),
        .user(id: "u2", text: "second"), .tools(id: "t1", ToolGroup(calls: [])),
    ]
    let markers = turnMarkers(in: feed)
    #expect(markers.map(\.id) == ["u1", "u2"])
    #expect(markers[0].title == "first question" && markers[0].preview == "Yes, it is so")
    #expect(markers[1].preview.isEmpty)
    #expect(markers[0].rowIDs == ["u1", "a1", "a2"] && markers[1].rowIDs == ["u2", "t1"])
    #expect(turns(showing: ["a2"], in: markers) == ["u1"] && turns(showing: ["a2", "t1"], in: markers) == ["u1", "u2"] && turns(showing: [], in: markers).isEmpty)
}

@Test func longTextsAreCutWithAnEllipsis() {
    let markers = turnMarkers(in: [.user(id: "u", text: String(repeating: "x", count: 200)), .agent(id: "a", text: "ok", inProgress: true)])
    #expect(markers[0].title.count == 91 && markers[0].title.hasSuffix("…"))
}
