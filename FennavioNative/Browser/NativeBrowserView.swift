import SwiftUI

/// An intentionally small native browsing shell. Both phone postures and iPad
/// keep navigation at the bottom; WebKit owns the actual webpage surface.
struct NativeBrowserView: View {
    @Bindable var session: NativeBrowserSession

    @FocusState private var addressFocused: Bool
    @State private var addressDraft = ""
    @State private var showsTabs = false
    @State private var showsSpaces = false
    @State private var newSpaceName = ""
    @State private var spaceToDelete: UUID?
    @State private var confirmsSpaceDeletion = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ZStack {
                if let tab = session.selectedTab, tab.address == "about:blank" {
                    ContentUnavailableView(
                        "New Tab",
                        systemImage: "globe",
                        description: Text("Enter an address or search below to begin.")
                    )
                }
                if let tab = session.selectedTab {
                    NativeWebPage(session: session, tabID: tab.id)
                        .id(tab.id)
                        .opacity(tab.address == "about:blank" ? 0 : 1)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .sheet(isPresented: $showsTabs) { tabsSheet }
        .sheet(isPresented: $showsSpaces) { spacesSheet }
        .onAppear(perform: refreshAddress)
        .onChange(of: session.selectedTabID) { _, _ in refreshAddress() }
        .onChange(of: session.isPrivate) { _, _ in refreshAddress() }
        .onChange(of: session.pageRevision) { _, _ in
            if !addressFocused { refreshAddress() }
        }
    }

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button {
                    showsSpaces = true
                } label: {
                    Label(
                        session.selectedSpaceName, systemImage: session.isPrivate ? "hand.raised" : "square.stack.3d.up"
                    )
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                }
                .accessibilityLabel("Choose Space")

                Spacer(minLength: 0)

                if session.isPrivate {
                    Button("End Private Session") {
                        session.endPrivateSession()
                    }
                    .font(.footnote)
                }

                Text("WebKit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let status = session.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button(action: session.goBack) {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 28, minHeight: 44)
            }
            .disabled(!session.canGoBack)
            .accessibilityLabel("Back")

            Button(action: session.goForward) {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 28, minHeight: 44)
            }
            .disabled(!session.canGoForward)
            .accessibilityLabel("Forward")

            TextField("Address or search", text: $addressDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($addressFocused)
                .onSubmit {
                    session.navigate(to: addressDraft)
                    addressFocused = false
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("native-address-field")

            Button(action: session.reloadOrStop) {
                Image(systemName: session.isLoading ? "xmark" : "arrow.clockwise")
                    .frame(minWidth: 28, minHeight: 44)
            }
            .accessibilityLabel(session.isLoading ? "Stop" : "Reload")

            Button {
                showsTabs = true
            } label: {
                Image(systemName: "square.on.square")
                    .frame(minWidth: 28, minHeight: 44)
                    .overlay(alignment: .topTrailing) {
                        Text("\(session.tabs.count)")
                            .font(.system(size: 9, weight: .semibold))
                            .offset(x: 4, y: -1)
                    }
            }
            .accessibilityLabel("Tabs")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var tabsSheet: some View {
        NavigationStack {
            List {
                ForEach(session.tabs) { tab in
                    Button {
                        session.selectTab(tab.id)
                        showsTabs = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tab.title)
                                    .lineLimit(1)
                                Text(tab.address == "about:blank" ? "New tab" : tab.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if session.selectedTabID == tab.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .swipeActions {
                        Button("Close", role: .destructive) {
                            session.closeTab(tab.id)
                        }
                    }
                }
            }
            .navigationTitle(session.isPrivate ? "Private Tabs" : "Tabs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { showsTabs = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Tab", systemImage: "plus") {
                        session.newTab()
                        showsTabs = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var spacesSheet: some View {
        NavigationStack {
            List {
                Section("Spaces") {
                    ForEach(session.spaces) { space in
                        Button {
                            session.switchToSpace(space.id)
                            showsSpaces = false
                        } label: {
                            HStack {
                                Text(space.name)
                                Spacer()
                                if !session.isPrivate && session.selectedSpaceID == space.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .swipeActions {
                            if session.spaces.count > 1 {
                                Button("Delete", role: .destructive) {
                                    spaceToDelete = space.id
                                    confirmsSpaceDeletion = true
                                }
                            }
                        }
                    }
                    Button {
                        session.switchToPrivate()
                        showsSpaces = false
                    } label: {
                        Label("Private Browsing", systemImage: "hand.raised")
                    }
                }

                Section("New Space") {
                    TextField("Space name", text: $newSpaceName)
                    Button("Create Space") {
                        session.createSpace(name: newSpaceName)
                        newSpaceName = ""
                        showsSpaces = false
                    }
                }
            }
            .navigationTitle("Spaces")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showsSpaces = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .confirmationDialog(
            "Delete this Space and its website data?",
            isPresented: $confirmsSpaceDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Space", role: .destructive) {
                if let spaceToDelete { session.deleteSpace(spaceToDelete) }
                spaceToDelete = nil
            }
            Button("Cancel", role: .cancel) { spaceToDelete = nil }
        }
    }

    private func refreshAddress() {
        let address = session.selectedTab?.address ?? ""
        addressDraft = address == "about:blank" ? "" : address
    }
}
