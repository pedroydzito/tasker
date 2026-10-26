import Foundation

/// Respostas cruas das APIs do Google (somente os campos que usamos).

protocol PagedResponse: Decodable {
    associatedtype Item: Decodable
    var items: [Item]? { get }
    var nextPageToken: String? { get }
}

struct GTaskList: Codable {
    var id: String
    var title: String?
}

struct GTaskListsResponse: PagedResponse {
    let items: [GTaskList]?
    let nextPageToken: String?
}

struct GTask: Codable {
    var id: String
    var title: String?
    var notes: String?
    var status: String?
    var due: String?
    var completed: String?
    var updated: String?
    var parent: String?
    var position: String?
    var deleted: Bool?
    var hidden: Bool?
    var webViewLink: String?
}

struct GTasksResponse: PagedResponse {
    let items: [GTask]?
    let nextPageToken: String?
}

struct GCalendar: Decodable {
    let id: String
    let summary: String?
    let summaryOverride: String?
    let backgroundColor: String?
    let selected: Bool?
    let primary: Bool?
    let hidden: Bool?
}

struct GCalendarListResponse: PagedResponse {
    let items: [GCalendar]?
    let nextPageToken: String?
}

struct GEventTime: Decodable {
    let date: String?
    let dateTime: String?
}

struct GAttendee: Decodable {
    let isSelf: Bool?
    let responseStatus: String?

    enum CodingKeys: String, CodingKey {
        case isSelf = "self"
        case responseStatus
    }
}

struct GEvent: Decodable {
    let id: String
    let summary: String?
    let status: String?
    let start: GEventTime?
    let end: GEventTime?
    let htmlLink: String?
    let colorId: String?
    let attendees: [GAttendee]?
}

struct GEventsResponse: PagedResponse {
    let items: [GEvent]?
    let nextPageToken: String?
}
