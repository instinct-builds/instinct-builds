import Foundation

/// 1.93: the text of the Help window. Every shortcut listed here must exist in the app's menus; a unit test reads
/// App.swift and checks each entry's menu item and key equivalent, so the window cannot list a shortcut that is not wired.
public enum HelpContent {
    public enum Mod: String, CaseIterable, Sendable { case command, shift, option, control }

    public struct Shortcut: Equatable, Sendable {
        public var key: String
        public var mods: Set<Mod>
        public init(_ key: String, _ mods: Set<Mod> = [.command]) { self.key = key; self.mods = mods }
        /// macOS order: control, option, shift, command.
        public var display: String {
            (mods.contains(.control) ? "⌃" : "") + (mods.contains(.option) ? "⌥" : "") + (mods.contains(.shift) ? "⇧" : "") + (mods.contains(.command) ? "⌘" : "") + key.uppercased()
        }
    }

    public struct Entry: Equatable, Sendable {
        public var title: String
        public var detail: String
        /// Text that must appear in App.swift on the line that declares the control, for entries naming a menu item or control.
        public var anchor: String?
        public var shortcut: Shortcut?
        public init(_ title: String, _ detail: String, anchor: String? = nil, shortcut: Shortcut? = nil) {
            self.title = title; self.detail = detail; self.anchor = anchor; self.shortcut = shortcut
        }
    }

    public struct Section: Equatable, Sendable {
        public var title: String
        public var entries: [Entry]
    }

    static func menu(_ title: String, _ detail: String, _ shortcut: Shortcut? = nil) -> Entry {
        Entry(title, detail, anchor: "Button(\"\(title)\"", shortcut: shortcut)
    }

    public static let sections: [Section] = [
        Section(title: "Bring files in", entries: [
            menu("Import Files…", "Add files to the library.", Shortcut("i")),
            menu("Watch Folder…", "New files in a folder land in the library on their own.", Shortcut("i", [.command, .shift])),
            menu("Read Finder Tags from Files", "Adds tags you set in Finder as ASSSETS tags. Imports read them automatically. Nothing is removed."),
            Entry("Search box", "Matches titles, tags, colors, client note text and reviewer labels.", anchor: "Search titles, tags, colors, notes, reviewers…"),
        ]),
        Section(title: "Organize", entries: [
            menu("New Collection", "Start a collection from the selection.", Shortcut("n", [.command, .shift])),
            Entry("Save as Smart", "Turns the current search and filters into a live collection.", anchor: "Label(\"Save as Smart\""),
            menu("Toggle Favorite", "Star or unstar the selection.", Shortcut("l")),
            menu("Stack as Versions", "Group the selection as versions of one asset.", Shortcut("g")),
            menu("Unstack", "Split a version stack.", Shortcut("g", [.command, .shift])),
            menu("Batch Rename…", "Rename the selection in bulk.", Shortcut("r", [.command, .option])),
            menu("Find Duplicates…", "Review duplicate files and merge them.", Shortcut("d", [.command, .option])),
            menu("Find Similar", "Show assets that look like the focused one.", Shortcut("f", [.command, .option])),
            menu("Library Health…", "Review the state of the library's files.", Shortcut("l", [.command, .option])),
        ]),
        Section(title: "Review and compare", entries: [
            menu("Compare Selection", "Side-by-side comparison with picks.", Shortcut("c", [.command, .option])),
            menu("Cull Current View", "Step through the current view one asset at a time.", Shortcut("k", [.command, .option])),
            menu("Place into Mockup…", "Place artwork into a mockup.", Shortcut("p", [.command, .option])),
        ]),
        Section(title: "Client feedback", entries: [
            menu("Export Review Gallery…", "Make a gallery file for a client to review.", Shortcut("g", [.command, .option])),
            menu("Import Client Feedback…", "Preview, then import picks, notes and decisions. Names are labels, not verified identities."),
            Entry("Undo Import Client Feedback", "Reverts a whole import, or is refused if boards or picks changed after it.", anchor: "Button(library.history.undoLabel", shortcut: Shortcut("z")),
            Entry("Open notes", "Header filter chip: only assets with unresolved client notes.", anchor: "Text(\"Open notes · "),
            Entry("Decisions", "Header filter chip: filter by Approve or Request changes.", anchor: "Label(model.decisionFilter == .any ? \"Decisions\""),
            menu("Copy Revision Brief", "Copies a plain-text to-do for the selection, or the current view."),
            menu("Export Client Notes as CSV…", "One row per note."),
            menu("Export Client Decisions as CSV…", "One row per reviewer decision."),
        ]),
        Section(title: "Export and share", entries: [
            menu("Export Selection As Shown…", "Export the selection as it appears.", Shortcut("e")),
            menu("Export Original Files…", "Copy the original files out.", Shortcut("e", [.command, .shift])),
            menu("Export with Presets…", "Export to sizes and crops from presets.", Shortcut("e", [.command, .option])),
            Entry("Write Finder Tags on Folder Export", "Off by default. When on, exported copies get the asset's tags as Finder tags. Your library files are never written to.", anchor: "Toggle(\"Write Finder Tags on Folder Export\""),
            menu("Contact Sheet & Brand Kit…", "Build a contact sheet or brand kit.", Shortcut("p", [.command, .shift])),
            menu("Reveal in Finder", "Show the selection's files in Finder.", Shortcut("r", [.command, .shift])),
        ]),
        Section(title: "Selection and boards", entries: [
            Entry("Add to Board", "Right-click an asset, then Add to Board, then New Board from Selection.", anchor: "Menu(\"Add to Board\""),
            menu("Select All Assets", "Select everything in the view.", Shortcut("a", [.command, .option])),
            menu("Deselect All", "Clear the selection.", Shortcut("d")),
        ]),
        Section(title: "Back up your library", entries: [
            menu("Back Up Library…", "Save the whole catalog to a file you choose. It does not include the asset files."),
            menu("Restore Library from Backup…", "Pick one of the automatic snapshots (one per launch, newest 5). Counts are shown before anything changes."),
            menu("Restore Library from File…", "Restore from a backup file. Counts are shown before anything changes."),
            Entry("If the library can't be read", "The unreadable file is kept next to it as studio-catalog.corrupt-…, never overwritten, and a banner explains."),
        ]),
        Section(title: "Help", entries: [
            Entry("ASSSETS Help", "Opens this window.", anchor: "Button(\"ASSSETS Help\"", shortcut: Shortcut("?")),
        ]),
    ]

    public static var entryCount: Int { sections.reduce(0) { $0 + $1.entries.count } }
    public static var shortcutCount: Int { sections.reduce(0) { $0 + $1.entries.filter { $0.shortcut != nil }.count } }
}
