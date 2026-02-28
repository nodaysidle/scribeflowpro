import SwiftUI
import SwiftData

struct MeetingSidebarView: View {
    @Binding var selectedMeeting: Meeting?
    @Query(sort: \Meeting.date, order: .reverse)
    private var meetings: [Meeting]

    @State private var searchText = ""

    private var filteredMeetings: [Meeting] {
        if searchText.isEmpty { return meetings }
        return meetings.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.rawTranscript.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(filteredMeetings, selection: $selectedMeeting) { meeting in
            MeetingSidebarRow(meeting: meeting)
                .tag(meeting)
        }
        .searchable(text: $searchText, prompt: "Search meetings")
        .navigationTitle("Meetings")
        .overlay {
            if filteredMeetings.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "No Meetings",
                        systemImage: "list.bullet",
                        description: Text("Recorded meetings will appear here.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }
}

private struct MeetingSidebarRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(meeting.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(formattedDuration)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            if !meeting.participants.isEmpty {
                Text(meeting.participants.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var formattedDuration: String {
        let minutes = Int(meeting.duration) / 60
        let seconds = Int(meeting.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
