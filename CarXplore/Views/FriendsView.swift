import MapKit
import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var game: GameStore
    @EnvironmentObject private var friends: FriendsStore
    @State private var codeInput = ""

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let detail: String
        let score: Int
        let friend: Friend?
    }

    private var leaderboard: [Entry] {
        let me = Entry(id: "me", name: friends.me.map { "\($0.displayName) (dig)" } ?? "Dig",
                       detail: "\(game.exploredAreaKm2.formatted(.number.precision(.fractionLength(1)))) km² · \(game.unlocked.count) trofæer",
                       score: game.score, friend: nil)
        let others = friends.friends.map { f in
            Entry(id: f.id.uuidString, name: f.name,
                  detail: "\(f.exploredKm2.formatted(.number.precision(.fractionLength(1)))) km² · \(f.trophies) trofæer",
                  score: f.score, friend: f)
        }
        return ([me] + others).sorted { $0.score > $1.score }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Leaderboard") {
                    ForEach(Array(leaderboard.enumerated()), id: \.element.id) { index, entry in
                        if let friend = entry.friend {
                            NavigationLink(value: friend) { row(rank: index + 1, entry: entry) }
                                .swipeActions {
                                    Button("Fjern", role: .destructive) {
                                        Task { await friends.remove(friend) }
                                    }
                                }
                        } else {
                            row(rank: index + 1, entry: entry)
                                .listRowBackground(Color.accentColor.opacity(0.12))
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("Vens kode, fx K7PQ2M", text: $codeInput)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Button("Tilføj") {
                            let code = codeInput
                            Task {
                                if await friends.add(code: code) { codeInput = "" }
                            }
                        }
                        .disabled(codeInput.trimmingCharacters(in: .whitespaces).count != 6)
                    }
                    HStack {
                        Text("Din kode")
                        Spacer()
                        Text(friends.myCode).font(.body.monospaced().bold())
                        ShareLink(item: "Kør om kap med mig på CarXplore! Min vennekode er \(friends.myCode)") {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                } header: {
                    Text("Tilføj ven")
                } footer: {
                    if friends.isDemo {
                        Text("Demo-tilstand: vennerne er testdata, fordi appen ikke er forbundet til en server (se README).")
                    } else {
                        Text("Del din kode med venner. Når de taster den ind, kan I se hinandens fremskridt.")
                    }
                }
            }
            .navigationTitle("Venner")
            .navigationDestination(for: Friend.self) { FriendDetailView(friend: $0) }
            .refreshable { await friends.refresh() }
            .alert("Fejl", isPresented: Binding(
                get: { friends.errorMessage != nil },
                set: { if !$0 { friends.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(friends.errorMessage ?? "")
            }
        }
    }

    private func row(rank: Int, entry: Entry) -> some View {
        HStack(spacing: 12) {
            Text(rank <= 3 ? ["🥇", "🥈", "🥉"][rank - 1] : "\(rank).")
                .font(.title3)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.headline)
                    if entry.friend?.isDriving == true {
                        Image(systemName: "car.fill").font(.caption).foregroundStyle(.green)
                    }
                }
                Text(entry.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(entry.score)").font(.headline.monospacedDigit())
        }
    }
}

struct FriendDetailView: View {
    let friend: Friend

    var body: some View {
        List {
            if let coordinate = friend.coordinate {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))) {
                        Marker(friend.name, systemImage: friend.isDriving ? "car.fill" : "person.fill",
                               coordinate: coordinate)
                    }
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
                }
            }
            Section("Status") {
                LabeledContent("Bil", value: friend.car)
                LabeledContent("Kører nu", value: friend.isDriving ? "Ja" : "Nej")
                if let lastSeen = friend.lastSeen {
                    LabeledContent("Sidst set", value: lastSeen.formatted(.relative(presentation: .named)))
                }
            }
            Section("Fremskridt") {
                LabeledContent("Udforsket",
                               value: "\(friend.exploredKm2.formatted(.number.precision(.fractionLength(1)))) km²")
                LabeledContent("Trofæer", value: "\(friend.trophies)")
                LabeledContent("Point", value: "\(friend.score)")
            }
        }
        .navigationTitle(friend.name)
    }
}
